// Worker Cloudflare servi sur https://edu.mathys.cc : comptage anonyme des installations d'EduBar.
//
// POST /v1/installation        → 201 {"id": uuid v4}. Seule l'empreinte SHA-256 de l'id est stockée.
// POST /v1/signal {id,version} → 204 ; un seul compte par jour (Europe/Paris) et par installation.
// GET  /v1/stats (Bearer)      → agrégats. Secret : EDU_STATS_TOKEN.
// Cron quotidien               → agrège les présences de plus de 35 jours puis les supprime, puis purge
//                                les installations sans présence depuis plus de 35 jours.
//
// Non-identifiabilité : ni IP, ni User-Agent, ni pays, ni heure, ni en-tête ne sont stockés ou
// journalisés. L'IP ne sert qu'à une clé de limitation de débit, hachée en mémoire.

const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const VERSION = /^\d{1,3}\.\d{1,3}\.\d{1,3}$/;
const CORPS_MAX = 1024;
const RETENTION_JOURS = 35;
// Plafond global de créations d'installations par jour (Europe/Paris), compté dans D1 sans aucune IP.
export const PLAFOND_CREATIONS_JOUR = 500;

// Clé de limiteur : IPv4 entière, IPv6 réduite à son préfixe /64 (un abonné reçoit au moins un /64).
// Salée par le jour et un secret existant puis hachée : l'empreinte ne s'inverse pas par énumération
// et change chaque jour. Calculée en mémoire, jamais stockée ni journalisée.
function reseauDe(ip) {
  const m4 = /^(?:::ffff:)?(\d{1,3}(?:\.\d{1,3}){3})$/i.exec(ip);
  if (m4) return m4[1];
  if (!ip.includes(':')) return ip;
  const [tete, queue = null] = ip.split('::');
  const a = tete ? tete.split(':') : [];
  const b = queue ? queue.split(':') : [];
  const groupes = queue === null ? a : [...a, ...Array(Math.max(0, 8 - a.length - b.length)).fill('0'), ...b];
  return groupes.slice(0, 4).map((g) => g.toLowerCase().padStart(4, '0')).join(':') + '::/64';
}

export async function cleLimiteur(ip, sel, jour) {
  return sha256hex(`${jour}|${sel || ''}|${reseauDe(ip)}`);
}

const ENTETES = { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' };

const json = (corps, statut = 200) =>
  new Response(JSON.stringify(corps), { status: statut, headers: { ...ENTETES, 'Content-Type': 'application/json' } });
const vide = (statut) => new Response(null, { status: statut, headers: ENTETES });
const nonTrouve = () => json({ erreur: 'introuvable' }, 404);

async function sha256hex(texte) {
  const h = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(texte));
  return [...new Uint8Array(h)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// Date AAAA-MM-JJ en Europe/Paris.
const FORMAT_JOUR = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Paris', year: 'numeric', month: '2-digit', day: '2-digit' });
export function jourParis(date = new Date()) {
  return FORMAT_JOUR.format(date);
}

export function decaler(jour, n) {
  const [a, m, j] = jour.split('-').map(Number);
  return new Date(Date.UTC(a, m - 1, j + n)).toISOString().slice(0, 10);
}

async function egalTempsConstant(a, b) {
  const [ha, hb] = await Promise.all([sha256hex(a), sha256hex(b)]);
  let d = 0;
  for (let i = 0; i < ha.length; i++) d |= ha.charCodeAt(i) ^ hb.charCodeAt(i);
  return d === 0;
}

// Lecture bornée : refus d'après Content-Length avant toute lecture, puis lecture par blocs
// interrompue dès que CORPS_MAX est dépassé (Content-Length absent ou menteur).
async function lireCorps(request) {
  const annonce = request.headers.get('Content-Length');
  if (annonce !== null && Number(annonce) > CORPS_MAX) return { trop: true };
  if (!request.body) return { texte: '' };
  const lecteur = request.body.getReader();
  const blocs = [];
  let total = 0;
  for (;;) {
    const { done, value } = await lecteur.read();
    if (done) break;
    total += value.byteLength;
    if (total > CORPS_MAX) {
      await lecteur.cancel().catch(() => {});
      return { trop: true };
    }
    blocs.push(value);
  }
  const buf = new Uint8Array(total);
  let pos = 0;
  for (const b of blocs) { buf.set(b, pos); pos += b.byteLength; }
  return { texte: new TextDecoder().decode(buf) };
}

// Limiteur par réseau (voir cleLimiteur). Sans binding (tests, local), aucune limite.
async function autorise(limiteur, request, env, jour) {
  if (!limiteur) return true;
  const ip = request.headers.get('CF-Connecting-IP') || 'inconnue';
  const { success } = await limiteur.limit({ key: await cleLimiteur(ip, env.EDU_STATS_TOKEN, jour) });
  return success;
}

async function installation(request, env, jour) {
  const { trop } = await lireCorps(request);
  if (trop) return json({ erreur: 'taille' }, 413);
  if (!(await autorise(env.LIMITER, request, env, jour))) return json({ erreur: 'limite' }, 429);
  const id = crypto.randomUUID();
  // Plafond atomique : comptage et insertion en une seule instruction, donc pas de dépassement
  // possible en concurrence. Aucune ligne insérée (changes = 0) : plafond atteint.
  const r = await env.DB.prepare(
    `INSERT INTO installations (empreinte, jour)
     SELECT ?, ? WHERE (SELECT COUNT(*) FROM installations WHERE jour = ?) < ?`)
    .bind(await sha256hex(id), jour, jour, PLAFOND_CREATIONS_JOUR).run();
  if (!r?.meta?.changes) return json({ erreur: 'limite' }, 429);
  return json({ id }, 201);
}

async function signal(request, env, jour) {
  const { trop, texte } = await lireCorps(request);
  if (trop) return json({ erreur: 'taille' }, 413);
  // Limiteur dédié (binding LIMITER_SIGNAL), avant tout accès à D1.
  if (!(await autorise(env.LIMITER_SIGNAL, request, env, jour))) return json({ erreur: 'limite' }, 429);
  let c;
  try { c = JSON.parse(texte); } catch { return json({ erreur: 'requete' }, 400); }
  if (!c || typeof c !== 'object' || typeof c.id !== 'string' || typeof c.version !== 'string'
      || !UUID_V4.test(c.id) || !VERSION.test(c.version)) {
    return json({ erreur: 'requete' }, 400);
  }
  const empreinte = await sha256hex(c.id);
  const connue = await env.DB.prepare('SELECT 1 AS ok FROM installations WHERE empreinte = ?').bind(empreinte).first();
  if (!connue) return json({ erreur: 'inconnue' }, 404);
  await env.DB.prepare('INSERT OR IGNORE INTO presences (jour, empreinte, version) VALUES (?, ?, ?)')
    .bind(jour, empreinte, c.version).run();
  return vide(204);
}

async function stats(request, env, aujourdhui) {
  const auth = request.headers.get('Authorization') || '';
  const jeton = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!env.EDU_STATS_TOKEN || !jeton || !(await egalTempsConstant(jeton, env.EDU_STATS_TOKEN))) {
    return json({ erreur: 'jeton' }, 401);
  }
  const debut30 = decaler(aujourdhui, -29);
  const debut7 = decaler(aujourdhui, -6);
  const db = env.DB;

  // Pas de lecture de jours_agreges : ses jours ont plus de 35 jours, au-delà de la fenêtre de 30 jours.
  const [inst, jour, semaine, mois, pres, nouv, vers, ancienne] = await Promise.all([
    db.prepare('SELECT COUNT(*) AS n FROM installations').first(),
    db.prepare('SELECT COUNT(*) AS n FROM presences WHERE jour = ?').bind(aujourdhui).first(),
    db.prepare('SELECT COUNT(DISTINCT empreinte) AS n FROM presences WHERE jour >= ?').bind(debut7).first(),
    db.prepare('SELECT COUNT(DISTINCT empreinte) AS n FROM presences WHERE jour >= ?').bind(debut30).first(),
    db.prepare('SELECT jour, COUNT(*) AS n FROM presences WHERE jour >= ? GROUP BY jour').bind(debut30).all(),
    db.prepare('SELECT jour, COUNT(*) AS n FROM installations WHERE jour >= ? GROUP BY jour').bind(debut30).all(),
    db.prepare('SELECT version, COUNT(DISTINCT empreinte) AS n FROM presences WHERE jour >= ? GROUP BY version ORDER BY n DESC, version DESC')
      .bind(debut7).all(),
    db.prepare('SELECT MIN(jour) AS jour FROM presences').first(),
  ]);

  const actifsParJour = new Map((pres.results || []).map((r) => [r.jour, r.n]));
  const nouvellesParJour = new Map((nouv.results || []).map((r) => [r.jour, r.n]));

  const jours = [];
  for (let i = 29; i >= 0; i--) {
    const j = decaler(aujourdhui, -i);
    jours.push({ jour: j, actifs: actifsParJour.get(j) || 0, nouvelles: nouvellesParJour.get(j) || 0 });
  }
  return json({
    genere: new Date().toISOString(),
    installations: inst?.n || 0,
    actifs: { jour: jour?.n || 0, semaine: semaine?.n || 0, mois: mois?.n || 0 },
    jours,
    versions: (vers.results || []).map((r) => ({ version: r.version, actifs: r.n })),
    // Surveillance de la purge : doit rester sous 37 jours (elle vaut 36 chaque nuit entre minuit Paris et le cron de 03:17 UTC), sinon le cron ne tourne plus.
    presence_la_plus_ancienne: ancienne?.jour || null,
  });
}

export async function agreger(env, maintenant = new Date()) {
  const limite = decaler(jourParis(maintenant), -RETENTION_JOURS);
  await env.DB.batch([
    env.DB.prepare(
      `INSERT OR REPLACE INTO jours_agreges (jour, actifs, nouvelles)
       SELECT p.jour, COUNT(*), (SELECT COUNT(*) FROM installations i WHERE i.jour = p.jour)
       FROM presences p WHERE p.jour < ? GROUP BY p.jour`).bind(limite),
    env.DB.prepare('DELETE FROM presences WHERE jour < ?').bind(limite),
    // Installations sans présence depuis plus de 35 jours : les présences plus anciennes viennent
    // d'être supprimées, donc il ne reste que les récentes. Une installation neuve (jour >= limite)
    // n'est jamais purgée avant ce délai. Sous-requête non corrélée : un seul parcours de presences
    // (pas d'index sur empreinte, la clé primaire est (jour, empreinte)).
    env.DB.prepare(
      `DELETE FROM installations WHERE jour < ?
       AND empreinte NOT IN (SELECT empreinte FROM presences)`).bind(limite),
  ]);
}

export default {
  async fetch(request, env) {
    const { pathname } = new URL(request.url);
    const m = request.method;
    // Un seul jour par requête : limiteur et SQL ne peuvent plus diverger autour de minuit.
    const jour = jourParis();
    try {
      if (m === 'POST' && pathname === '/v1/installation') return await installation(request, env, jour);
      if (m === 'POST' && pathname === '/v1/signal') return await signal(request, env, jour);
      if (m === 'GET' && pathname === '/v1/stats') return await stats(request, env, jour);
    } catch {
      return json({ erreur: 'serveur' }, 500);
    }
    return nonTrouve();
  },
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(agreger(env));
  },
};

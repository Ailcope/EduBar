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

const ENTETES = { 'Cache-Control': 'no-store' };

const json = (corps, statut = 200) =>
  new Response(JSON.stringify(corps), { status: statut, headers: { ...ENTETES, 'Content-Type': 'application/json' } });
const vide = (statut) => new Response(null, { status: statut, headers: ENTETES });
const nonTrouve = () => json({ erreur: 'introuvable' }, 404);

async function sha256hex(texte) {
  const h = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(texte));
  return [...new Uint8Array(h)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// Date AAAA-MM-JJ en Europe/Paris.
export function jourParis(date = new Date()) {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Paris', year: 'numeric', month: '2-digit', day: '2-digit' }).format(date);
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

async function lireCorps(request) {
  const buf = await request.arrayBuffer();
  if (buf.byteLength > CORPS_MAX) return { trop: true };
  return { texte: new TextDecoder().decode(buf) };
}

async function installation(request, env) {
  const { trop } = await lireCorps(request);
  if (trop) return json({ erreur: 'taille' }, 413);
  if (env.LIMITER) {
    const ip = request.headers.get('CF-Connecting-IP') || 'inconnue';
    const { success } = await env.LIMITER.limit({ key: await cleLimiteur(ip, env.EDU_STATS_TOKEN, jourParis()) });
    if (!success) return json({ erreur: 'limite' }, 429);
  }
  const creees = await env.DB.prepare('SELECT COUNT(*) AS n FROM installations WHERE jour = ?').bind(jourParis()).first();
  if ((creees?.n || 0) >= PLAFOND_CREATIONS_JOUR) return json({ erreur: 'limite' }, 429);
  const id = crypto.randomUUID();
  await env.DB.prepare('INSERT INTO installations (empreinte, jour) VALUES (?, ?)')
    .bind(await sha256hex(id), jourParis()).run();
  return json({ id }, 201);
}

async function signal(request, env) {
  const { trop, texte } = await lireCorps(request);
  if (trop) return json({ erreur: 'taille' }, 413);
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
    .bind(jourParis(), empreinte, c.version).run();
  return vide(204);
}

async function stats(request, env) {
  const auth = request.headers.get('Authorization') || '';
  const jeton = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!env.EDU_STATS_TOKEN || !jeton || !(await egalTempsConstant(jeton, env.EDU_STATS_TOKEN))) {
    return json({ erreur: 'jeton' }, 401);
  }
  const aujourdhui = jourParis();
  const debut30 = decaler(aujourdhui, -29);
  const debut7 = decaler(aujourdhui, -6);
  const db = env.DB;

  const [inst, jour, semaine, mois, pres, nouv, agr, vers] = await Promise.all([
    db.prepare('SELECT COUNT(*) AS n FROM installations').first(),
    db.prepare('SELECT COUNT(*) AS n FROM presences WHERE jour = ?').bind(aujourdhui).first(),
    db.prepare('SELECT COUNT(DISTINCT empreinte) AS n FROM presences WHERE jour >= ?').bind(debut7).first(),
    db.prepare('SELECT COUNT(DISTINCT empreinte) AS n FROM presences WHERE jour >= ?').bind(debut30).first(),
    db.prepare('SELECT jour, COUNT(*) AS n FROM presences WHERE jour >= ? GROUP BY jour').bind(debut30).all(),
    db.prepare('SELECT jour, COUNT(*) AS n FROM installations WHERE jour >= ? GROUP BY jour').bind(debut30).all(),
    db.prepare('SELECT jour, actifs, nouvelles FROM jours_agreges WHERE jour >= ?').bind(debut30).all(),
    db.prepare('SELECT version, COUNT(DISTINCT empreinte) AS n FROM presences WHERE jour >= ? GROUP BY version ORDER BY n DESC, version DESC')
      .bind(debut7).all(),
  ]);

  const actifsParJour = new Map((agr.results || []).map((r) => [r.jour, r.actifs]));
  const nouvellesParJour = new Map((agr.results || []).map((r) => [r.jour, r.nouvelles]));
  for (const r of pres.results || []) actifsParJour.set(r.jour, r.n);
  for (const r of nouv.results || []) nouvellesParJour.set(r.jour, r.n);

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
    // n'est jamais purgée avant ce délai.
    env.DB.prepare(
      `DELETE FROM installations WHERE jour < ?
       AND NOT EXISTS (SELECT 1 FROM presences p WHERE p.empreinte = installations.empreinte)`).bind(limite),
  ]);
}

export default {
  async fetch(request, env) {
    const { pathname } = new URL(request.url);
    const m = request.method;
    try {
      if (m === 'POST' && pathname === '/v1/installation') return await installation(request, env);
      if (m === 'POST' && pathname === '/v1/signal') return await signal(request, env);
      if (m === 'GET' && pathname === '/v1/stats') return await stats(request, env);
    } catch {
      return json({ erreur: 'serveur' }, 500);
    }
    return nonTrouve();
  },
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(agreger(env));
  },
};

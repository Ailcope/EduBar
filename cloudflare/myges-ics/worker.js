// Worker Cloudflare servi sur https://edt.mathys.cc : emploi du temps myGES en flux iCal (.ics),
// pour s'y abonner depuis Google Agenda, Calendrier Apple, etc.
//
// Cron (toutes les 30 min) → lit l'agenda myGES (API Kordis, cf. docs/myges-api-kordis.md),
//                            construit le .ics et le garde en KV (clé « ics »).
// GET /<FEED_TOKEN>.ics     → sert le dernier .ics correct. Tout autre chemin : 404.
//
// Si myGES est en panne, le dernier .ics correct reste servi : l'abonnement ne se vide jamais.
// Secrets : MYGES_LOGIN, MYGES_PASSWORD, FEED_TOKEN, HC_PING_URL (facultatif, sonde Healthchecks).
// Aucun journal : ni identifiants ni jeton ne sont écrits nulle part.

const AUTH_URL = 'https://authentication.kordis.fr/oauth/authorize?response_type=token&client_id=skolae-app';
const API = 'https://api.kordis.fr';
// Kordis renvoie 403 sans User-Agent de navigateur (docs/myges-api-kordis.md §1).
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
const JOUR = 86_400_000;
const AVANT_JOURS = 14;
const APRES_JOURS = 120;
const ESSAIS = 3;

const nonTrouve = () => new Response('introuvable', { status: 404, headers: { 'Cache-Control': 'no-store' } });

async function sha256hex(texte) {
  const h = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(texte));
  return [...new Uint8Array(h)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function egalTempsConstant(a, b) {
  const [ha, hb] = await Promise.all([sha256hex(a), sha256hex(b)]);
  let d = 0;
  for (let i = 0; i < ha.length; i++) d |= ha.charCodeAt(i) ^ hb.charCodeAt(i);
  return d === 0;
}

// --- myGES -----------------------------------------------------------------------------------

// Rejoue sur 429 et 5xx (pannes passagères fréquentes chez Kordis).
async function appel(url, init) {
  let derniere;
  for (let i = 0; i < ESSAIS; i++) {
    if (i > 0) await new Promise((r) => setTimeout(r, 1000 * i));
    derniere = await fetch(url, init);
    if (derniere.status !== 429 && derniere.status < 500) return derniere;
  }
  return derniere;
}

// Jeton dans le fragment de Location (comreseaugesskolae://oauth2redirect#access_token=...).
// Valeur non décodée : un jeton peut contenir des « + ».
export function jetonDepuisLocation(location) {
  const fragment = (location ?? '').split('#')[1] ?? '';
  for (const paire of fragment.split('&')) {
    const i = paire.indexOf('=');
    if (i > 0 && paire.slice(0, i) === 'access_token' && i < paire.length - 1) return paire.slice(i + 1);
  }
  return null;
}

async function connexion(env) {
  const basic = btoa(String.fromCharCode(...new TextEncoder().encode(`${env.MYGES_LOGIN}:${env.MYGES_PASSWORD}`)));
  const r = await appel(AUTH_URL, { redirect: 'manual', headers: { Authorization: `Basic ${basic}`, 'User-Agent': UA } });
  const jeton = r.status === 302 ? jetonDepuisLocation(r.headers.get('Location')) : null;
  if (!jeton) throw new Error(`connexion myGES refusée (HTTP ${r.status})`);
  return jeton;
}

async function lireAgenda(env, maintenant) {
  const jeton = await connexion(env);
  const debut = maintenant - AVANT_JOURS * JOUR;
  const fin = maintenant + APRES_JOURS * JOUR;
  const r = await appel(`${API}/me/agenda?start=${debut}&end=${fin}`, {
    headers: { Authorization: `bearer ${jeton}`, 'User-Agent': UA, Accept: 'application/json' },
  });
  if (!r.ok) throw new Error(`agenda myGES indisponible (HTTP ${r.status})`);
  const corps = await r.json();
  const liste = Array.isArray(corps) ? corps : corps?.result;
  if (!Array.isArray(liste)) throw new Error('agenda myGES : réponse inattendue');
  return liste;
}

// --- iCal ------------------------------------------------------------------------------------

const propre = (s) => (typeof s === 'string' && s.trim() ? s.trim() : null);

// Même règle qu'EduBar (GESAgenda.isCourse) : type « Cours », ou type absent.
export function estUnCours(e) {
  const type = propre(e?.type);
  return type === null || type.toLowerCase() === 'cours';
}

// « T1 - Réseaux » → « Réseaux ».
const sansPeriode = (nom) => nom.replace(/^[TS]\d+\s*-\s*/i, '');

const echapper = (s) => s.replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\r?\n/g, '\\n');

// Lignes de 75 octets max (RFC 5545 §3.1), sans couper un caractère UTF-8.
export function plier(ligne) {
  const enc = new TextEncoder();
  const morceaux = [];
  let courant = '';
  let octets = 0;
  for (const c of ligne) {
    const n = enc.encode(c).length;
    const max = morceaux.length === 0 ? 75 : 74; // la suite commence par une espace
    if (octets + n > max) {
      morceaux.push(courant);
      courant = '';
      octets = 0;
    }
    courant += c;
    octets += n;
  }
  morceaux.push(courant);
  return morceaux.join('\r\n ');
}

const dateIcs = (ms) => new Date(ms).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');

export function construireIcs(evenements, maintenant) {
  const lignes = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Ailcope//myges-ics//FR',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:ESGI (myGES)',
    'X-WR-TIMEZONE:Europe/Paris',
    'REFRESH-INTERVAL;VALUE=DURATION:PT1H',
    'X-PUBLISHED-TTL:PT1H',
  ];
  const cours = evenements
    .filter((e) => estUnCours(e) && Number.isFinite(e.start_date) && Number.isFinite(e.end_date) && e.end_date > e.start_date)
    .sort((a, b) => a.start_date - b.start_date);
  for (const e of cours) {
    const nom = propre(e.name) ?? propre(e.discipline?.name) ?? 'Cours';
    const salles = (e.rooms ?? []).map((s) => propre(s?.name)).filter(Boolean);
    const campus = propre(e.rooms?.[0]?.campus);
    const lieu = salles.length ? salles.join(' · ') + (campus ? ` (${campus})` : '') : null;
    const details = [propre(e.teacher) ?? propre(e.discipline?.teacher), propre(e.modality)].filter(Boolean).join('\n');
    const uid = e.reservation_id != null ? `ges-${e.reservation_id}` : `ges-${e.start_date}-${empreinteCourte(nom)}`;
    lignes.push(
      'BEGIN:VEVENT',
      `UID:${uid}@edt.mathys.cc`,
      `DTSTAMP:${dateIcs(maintenant)}`,
      `DTSTART:${dateIcs(e.start_date)}`,
      `DTEND:${dateIcs(e.end_date)}`,
      `SUMMARY:${echapper(sansPeriode(nom))}`,
    );
    if (lieu) lignes.push(`LOCATION:${echapper(lieu)}`);
    if (details) lignes.push(`DESCRIPTION:${echapper(details)}`);
    lignes.push('END:VEVENT');
  }
  lignes.push('END:VCALENDAR');
  return lignes.map(plier).join('\r\n') + '\r\n';
}

// Identifiant stable sans reservation_id (cas jamais vu, par prudence).
function empreinteCourte(texte) {
  let h = 0;
  for (const c of texte) h = (Math.imul(h, 31) + c.codePointAt(0)) | 0;
  return (h >>> 0).toString(16);
}

// --- Mise à jour et service --------------------------------------------------------------------

const nbCours = (ics) => (ics.match(/^BEGIN:VEVENT/gm) ?? []).length;

export async function rafraichir(env, maintenant = Date.now()) {
  const ics = construireIcs(await lireAgenda(env, maintenant), maintenant);
  // Un agenda soudain vide alors qu'il y avait des cours = panne probable : on garde l'ancien.
  const ancien = await env.ICS.get('ics');
  if (nbCours(ics) === 0 && ancien && nbCours(ancien) > 0) throw new Error('agenda myGES vide, ancien .ics conservé');
  await env.ICS.put('ics', ics);
  return ics;
}

async function sonde(env, suffixe = '') {
  if (!env.HC_PING_URL) return;
  try {
    await fetch(env.HC_PING_URL + suffixe, { method: 'POST' });
  } catch {
    // La sonde ne doit jamais faire échouer la mise à jour.
  }
}

export default {
  async fetch(request, env) {
    if (request.method !== 'GET' && request.method !== 'HEAD') return nonTrouve();
    const { pathname } = new URL(request.url);
    const m = pathname.match(/^\/([A-Za-z0-9_-]{16,128})\.ics$/);
    if (!m || !env.FEED_TOKEN || !(await egalTempsConstant(m[1], env.FEED_TOKEN))) return nonTrouve();

    let ics = await env.ICS.get('ics');
    if (!ics) {
      try {
        ics = await rafraichir(env);
      } catch {
        return new Response('myGES indisponible, réessayer plus tard', { status: 503, headers: { 'Retry-After': '1800' } });
      }
    }
    return new Response(request.method === 'HEAD' ? null : ics, {
      headers: {
        'Content-Type': 'text/calendar; charset=utf-8',
        'Cache-Control': 'private, max-age=900',
        'X-Robots-Tag': 'noindex',
      },
    });
  },

  async scheduled(_event, env, ctx) {
    ctx.waitUntil(
      rafraichir(env).then(
        () => sonde(env),
        () => sonde(env, '/fail'),
      ),
    );
  },
};

// node --test cloudflare/myges-ics/test/ ; KV et réseau simulés, sans dépendance.
import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import worker, { construireIcs, estUnCours, jetonDepuisLocation, plier, rafraichir } from '../worker.js';

const JETON_FLUX = 'abcdefghijklmnop0123456789';
const MAINTENANT = Date.UTC(2026, 10, 11, 8, 0, 0);

const cours = (extra = {}) => ({
  reservation_id: 42,
  name: 'T1 - Réseaux, routage; avancé',
  type: 'Cours',
  modality: 'Présentiel',
  start_date: Date.UTC(2026, 10, 12, 8, 0, 0),
  end_date: Date.UTC(2026, 10, 12, 11, 30, 0),
  teacher: 'Prof Test',
  rooms: [{ name: 'Quai 12 - 502', campus: 'REIMS' }],
  ...extra,
});

function kv(init = {}) {
  const m = new Map(Object.entries(init));
  return { async get(k) { return m.get(k) ?? null; }, async put(k, v) { m.set(k, v); }, m };
}

const env = (extra = {}) => ({ MYGES_LOGIN: 'pnom', MYGES_PASSWORD: 'mdp', FEED_TOKEN: JETON_FLUX, ICS: kv(), ...extra });

// Simule Kordis : connexion 302 puis agenda.
let appels;
let agenda;
const fetchOrigine = globalThis.fetch;
beforeEach(() => {
  appels = [];
  agenda = { status: 200, corps: { result: [cours()] } };
  globalThis.fetch = async (url, init = {}) => {
    appels.push({ url: String(url), init });
    if (String(url).startsWith('https://authentication.kordis.fr/')) {
      return new Response(null, { status: 302, headers: { Location: 'comreseaugesskolae://oauth2redirect#access_token=ab+cd&token_type=bearer' } });
    }
    if (String(url).startsWith('https://api.kordis.fr/me/agenda')) {
      return new Response(JSON.stringify(agenda.corps), { status: agenda.status });
    }
    return new Response(null, { status: 200 });
  };
});
afterEach(() => { globalThis.fetch = fetchOrigine; });

test('jeton lu dans le fragment, sans décodage', () => {
  assert.equal(jetonDepuisLocation('x://y#token_type=bearer&access_token=a+b%2F&uid=1'), 'a+b%2F');
  assert.equal(jetonDepuisLocation('x://y?access_token=a'), null);
  assert.equal(jetonDepuisLocation(null), null);
});

test('seuls les cours (ou type absent) sont gardés', () => {
  assert.ok(estUnCours({ type: 'Cours' }));
  assert.ok(estUnCours({ type: ' cours ' }));
  assert.ok(estUnCours({}));
  assert.ok(!estUnCours({ type: 'Autre' }));
});

test('.ics : champs, échappement, préfixe de période retiré, UTC', () => {
  const ics = construireIcs([cours(), cours({ reservation_id: 7, type: 'Autre', name: 'Les midis de l’info' })], MAINTENANT);
  assert.match(ics, /^BEGIN:VCALENDAR\r\n/);
  assert.ok(ics.endsWith('END:VCALENDAR\r\n'));
  assert.equal((ics.match(/BEGIN:VEVENT/g) ?? []).length, 1);
  assert.match(ics, /UID:ges-42@edt\.mathys\.cc\r\n/);
  assert.match(ics, /DTSTART:20261112T080000Z\r\n/);
  assert.match(ics, /DTEND:20261112T113000Z\r\n/);
  assert.match(ics, /SUMMARY:Réseaux\\, routage\\; avancé\r\n/);
  assert.match(ics, /LOCATION:Quai 12 - 502 \(REIMS\)\r\n/);
  assert.match(ics, /DESCRIPTION:Prof Test\\nPrésentiel\r\n/);
  assert.ok(!ics.includes('midis'));
});

test('événement sans dates valides ignoré', () => {
  const ics = construireIcs([cours({ end_date: cours().start_date }), cours({ start_date: null })], MAINTENANT);
  assert.ok(!ics.includes('BEGIN:VEVENT'));
});

test('pliage à 75 octets sans couper un caractère UTF-8', () => {
  const ligne = 'SUMMARY:' + 'é'.repeat(100);
  const plie = plier(ligne);
  const enc = new TextEncoder();
  for (const morceau of plie.split('\r\n')) assert.ok(enc.encode(morceau).length <= 75);
  assert.equal(plie.split('\r\n').map((l, i) => (i ? l.slice(1) : l)).join(''), ligne);
});

test('connexion Basic, redirection non suivie, User-Agent envoyé', async () => {
  const e = env();
  await rafraichir(e, MAINTENANT);
  const auth = appels[0];
  assert.equal(auth.init.redirect, 'manual');
  assert.equal(auth.init.headers.Authorization, 'Basic ' + btoa('pnom:mdp'));
  assert.match(auth.init.headers['User-Agent'], /Mozilla/);
  assert.equal(appels[1].init.headers.Authorization, 'bearer ab+cd');
  assert.match(await e.ICS.get('ics'), /UID:ges-42/);
});

test('mauvais identifiants : erreur, ancien .ics intact', async () => {
  globalThis.fetch = async () => new Response(null, { status: 401 });
  const e = env({ ICS: kv({ ics: 'ANCIEN' }) });
  await assert.rejects(rafraichir(e, MAINTENANT), /HTTP 401/);
  assert.equal(await e.ICS.get('ics'), 'ANCIEN');
});

test('agenda soudain vide : ancien .ics conservé', async () => {
  const e = env();
  await rafraichir(e, MAINTENANT);
  const avant = await e.ICS.get('ics');
  agenda.corps = { result: [] };
  await assert.rejects(rafraichir(e, MAINTENANT), /vide/);
  assert.equal(await e.ICS.get('ics'), avant);
});

test('panne 503 rejouée puis abandonnée', async () => {
  agenda.status = 503;
  await assert.rejects(rafraichir(env(), MAINTENANT), /HTTP 503/);
  assert.equal(appels.filter((a) => a.url.includes('/me/agenda')).length, 3);
});

const get = (e, chemin, methode = 'GET') => worker.fetch(new Request('https://edt.mathys.cc' + chemin, { method: methode }), e);

test('GET avec le bon jeton : .ics servi depuis KV', async () => {
  const e = env({ ICS: kv({ ics: 'BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n' }) });
  const r = await get(e, `/${JETON_FLUX}.ics`);
  assert.equal(r.status, 200);
  assert.equal(r.headers.get('Content-Type'), 'text/calendar; charset=utf-8');
  assert.equal(await r.text(), 'BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n');
  assert.equal(appels.length, 0);
});

test('KV vide : premier .ics construit à la demande', async () => {
  const r = await get(env(), `/${JETON_FLUX}.ics`);
  assert.equal(r.status, 200);
  assert.match(await r.text(), /UID:ges-42/);
});

test('KV vide et myGES en panne : 503', async () => {
  agenda.status = 500;
  const r = await get(env(), `/${JETON_FLUX}.ics`);
  assert.equal(r.status, 503);
});

test('mauvais jeton, autre chemin, autre méthode : 404', async () => {
  const e = env({ ICS: kv({ ics: 'X' }) });
  assert.equal((await get(e, '/abcdefghijklmnop0123456780.ics')).status, 404);
  assert.equal((await get(e, '/')).status, 404);
  assert.equal((await get(e, `/${JETON_FLUX}.ics`, 'POST')).status, 404);
  assert.equal((await get(env({ FEED_TOKEN: undefined, ICS: kv({ ics: 'X' }) }), `/${JETON_FLUX}.ics`)).status, 404);
});

test('cron : sonde OK puis /fail en cas de panne', async () => {
  const e = env({ HC_PING_URL: 'https://hc.example/ping/uuid' });
  const attente = [];
  const ctx = { waitUntil: (p) => attente.push(p) };
  await worker.scheduled({}, e, ctx);
  await Promise.all(attente);
  assert.ok(appels.some((a) => a.url === 'https://hc.example/ping/uuid'));
  agenda.status = 502;
  appels = [];
  await worker.scheduled({}, e, ctx);
  await Promise.all(attente);
  assert.ok(appels.some((a) => a.url === 'https://hc.example/ping/uuid/fail'));
});

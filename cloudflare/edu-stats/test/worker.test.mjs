// node --test cloudflare/edu-stats/test/ ; D1 simulé avec node:sqlite (vrai SQL, en mémoire).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import worker, { jourParis, decaler, agreger, cleLimiteur, PLAFOND_CREATIONS_JOUR } from '../worker.js';

function creerEnv(extra = {}) {
  const sqlite = new DatabaseSync(':memory:');
  sqlite.exec(readFileSync(new URL('../schema.sql', import.meta.url), 'utf8'));
  const prep = (sql) => {
    let args = [];
    const o = {
      bind(...a) { args = a; return o; },
      async run() { sqlite.prepare(sql).run(...args); return { success: true }; },
      async first() { return sqlite.prepare(sql).get(...args) ?? null; },
      async all() { return { results: sqlite.prepare(sql).all(...args) }; },
    };
    return o;
  };
  const db = { prepare: prep, async batch(l) { for (const s of l) await s.run(); }, sqlite };
  return { DB: db, EDU_STATS_TOKEN: 'secret-de-test', ...extra };
}

const appeler = (env, methode, chemin, { corps, jeton } = {}) =>
  worker.fetch(new Request('https://edu.mathys.cc' + chemin, {
    method: methode,
    body: corps,
    headers: jeton ? { Authorization: 'Bearer ' + jeton } : {},
  }), env);

const signaler = (env, id, version = '0.9.0') =>
  appeler(env, 'POST', '/v1/signal', { corps: JSON.stringify({ id, version }) });

test('installation : 201, uuid v4, no-store, stockage en empreinte', async () => {
  const env = creerEnv();
  const r = await appeler(env, 'POST', '/v1/installation');
  assert.equal(r.status, 201);
  assert.equal(r.headers.get('Cache-Control'), 'no-store');
  const { id } = await r.json();
  assert.match(id, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  const lignes = env.DB.sqlite.prepare('SELECT * FROM installations').all();
  assert.equal(lignes.length, 1);
  assert.notEqual(lignes[0].empreinte, id);
  assert.equal(lignes[0].empreinte.length, 64);
  assert.equal(lignes[0].jour, jourParis());
});

test('installation : limite de débit => 429', async () => {
  const env = creerEnv({ LIMITER: { limit: async () => ({ success: false }) } });
  assert.equal((await appeler(env, 'POST', '/v1/installation')).status, 429);
  assert.equal(env.DB.sqlite.prepare('SELECT COUNT(*) n FROM installations').get().n, 0);
});

test('signal : 204 puis un seul compte par jour', async () => {
  const env = creerEnv();
  const { id } = await (await appeler(env, 'POST', '/v1/installation')).json();
  assert.equal((await signaler(env, id)).status, 204);
  assert.equal((await signaler(env, id, '0.9.1')).status, 204);
  assert.equal(env.DB.sqlite.prepare('SELECT COUNT(*) n FROM presences').get().n, 1);
});

test('signal : validations 400, 404, 413', async () => {
  const env = creerEnv();
  const bad = async (corps) => {
    const r = await appeler(env, 'POST', '/v1/signal', { corps });
    assert.equal(r.status, 400);
    assert.deepEqual(await r.json(), { erreur: 'requete' });
  };
  await bad('pas du json');
  await bad(JSON.stringify({ id: 'x', version: '0.9.0' }));
  await bad(JSON.stringify({ id: crypto.randomUUID(), version: '0.9' }));
  await bad(JSON.stringify({ id: crypto.randomUUID(), version: '1234.0.0' }));
  await bad(JSON.stringify({ version: '0.9.0' }));
  const r = await signaler(env, crypto.randomUUID());
  assert.equal(r.status, 404);
  assert.deepEqual(await r.json(), { erreur: 'inconnue' });
  const gros = await appeler(env, 'POST', '/v1/signal', { corps: 'x'.repeat(2000) });
  assert.equal(gros.status, 413);
});

test('stats : 401 sans ou avec mauvais jeton, 200 avec', async () => {
  const env = creerEnv();
  for (const jeton of [undefined, 'faux']) {
    const r = await appeler(env, 'GET', '/v1/stats', { jeton });
    assert.equal(r.status, 401);
    assert.deepEqual(await r.json(), { erreur: 'jeton' });
  }
  const r = await appeler(env, 'GET', '/v1/stats', { jeton: 'secret-de-test' });
  assert.equal(r.status, 200);
  const s = await r.json();
  assert.equal(s.installations, 0);
  assert.deepEqual(s.actifs, { jour: 0, semaine: 0, mois: 0 });
  assert.equal(s.jours.length, 30);
  assert.equal(s.jours[29].jour, jourParis());
  assert.deepEqual(s.versions, []);
});

test('stats : comptes jour/semaine/mois, versions, nouvelles', async () => {
  const env = creerEnv();
  const a = await (await appeler(env, 'POST', '/v1/installation')).json();
  const b = await (await appeler(env, 'POST', '/v1/installation')).json();
  await signaler(env, a.id, '0.9.0');
  await signaler(env, b.id, '0.8.0');
  const today = jourParis();
  const sq = env.DB.sqlite;
  const ea = sq.prepare('SELECT empreinte FROM installations').all()[0].empreinte;
  sq.prepare('INSERT INTO presences VALUES (?,?,?)').run(decaler(today, -3), ea, '0.9.0');
  sq.prepare('INSERT INTO presences VALUES (?,?,?)').run(decaler(today, -20), ea, '0.7.0');
  const s = await (await appeler(env, 'GET', '/v1/stats', { jeton: 'secret-de-test' })).json();
  assert.equal(s.installations, 2);
  assert.deepEqual(s.actifs, { jour: 2, semaine: 2, mois: 2 });
  assert.equal(s.jours[29].actifs, 2);
  assert.equal(s.jours[29].nouvelles, 2);
  assert.equal(s.jours[26].actifs, 1);
  assert.equal(s.jours[9].actifs, 1);
  assert.equal(s.jours[0].actifs, 0);
  assert.deepEqual(s.versions.map((v) => v.version).sort(), ['0.8.0', '0.9.0']);
});

test('cron : agrège puis supprime les présences de plus de 35 jours', async () => {
  const env = creerEnv();
  const sq = env.DB.sqlite;
  const today = jourParis();
  const vieux = decaler(today, -40);
  const recent = decaler(today, -5);
  sq.prepare('INSERT INTO installations VALUES (?,?)').run('e1', vieux);
  sq.prepare('INSERT INTO installations VALUES (?,?)').run('e2', vieux);
  sq.prepare('INSERT INTO presences VALUES (?,?,?)').run(vieux, 'e1', '0.9.0');
  sq.prepare('INSERT INTO presences VALUES (?,?,?)').run(vieux, 'e2', '0.9.0');
  sq.prepare('INSERT INTO presences VALUES (?,?,?)').run(recent, 'e1', '0.9.0');
  await agreger(env);
  assert.deepEqual(sq.prepare('SELECT * FROM jours_agreges').all().map((r) => ({ ...r })), [{ jour: vieux, actifs: 2, nouvelles: 2 }]);
  assert.equal(sq.prepare('SELECT COUNT(*) n FROM presences').get().n, 1);
  await agreger(env);
  assert.equal(sq.prepare('SELECT COUNT(*) n FROM presences').get().n, 1);
});

test('limiteur : IPv4 entière, IPv6 par préfixe /64, jamais l\'IP en clair', async () => {
  const j = '2026-11-13';
  const a = await cleLimiteur('203.0.113.7', 's', j);
  const b = await cleLimiteur('203.0.113.8', 's', j);
  assert.notEqual(a, b);
  const v6a = await cleLimiteur('2001:db8:1:2:aaaa:bbbb:cccc:dddd', 's', j);
  const v6b = await cleLimiteur('2001:0db8:0001:0002::1', 's', j);
  const v6c = await cleLimiteur('2001:db8:1:3::1', 's', j);
  assert.equal(v6a, v6b);
  assert.notEqual(v6a, v6c);
  assert.equal(await cleLimiteur('::ffff:203.0.113.7', 's', j), a);
  assert.notEqual(await cleLimiteur('203.0.113.7', 's', '2026-11-14'), a);
  assert.notEqual(await cleLimiteur('203.0.113.7', 'autre', j), a);
  for (const k of [a, v6a]) assert.match(k, /^[0-9a-f]{64}$/);
});

test('installation : la clé du limiteur est le préfixe /64 salé', async () => {
  const cles = [];
  const env = creerEnv({ LIMITER: { limit: async ({ key }) => { cles.push(key); return { success: true }; } } });
  const appelerIp = (ip) => worker.fetch(new Request('https://edu.mathys.cc/v1/installation', { method: 'POST', headers: { 'CF-Connecting-IP': ip } }), env);
  await appelerIp('2001:db8:1:2::1');
  await appelerIp('2001:db8:1:2:ffff::9');
  assert.equal(cles.length, 2);
  assert.equal(cles[0], cles[1]);
});

test('installation : plafond global quotidien => 429 sans stocker', async () => {
  const env = creerEnv();
  const sq = env.DB.sqlite;
  const ins = sq.prepare('INSERT INTO installations VALUES (?,?)');
  for (let i = 0; i < PLAFOND_CREATIONS_JOUR; i++) ins.run('e' + i, jourParis());
  const r = await appeler(env, 'POST', '/v1/installation');
  assert.equal(r.status, 429);
  assert.deepEqual(await r.json(), { erreur: 'limite' });
  assert.equal(sq.prepare('SELECT COUNT(*) n FROM installations').get().n, PLAFOND_CREATIONS_JOUR);
  sq.prepare('UPDATE installations SET jour = ?').run(decaler(jourParis(), -1));
  assert.equal((await appeler(env, 'POST', '/v1/installation')).status, 201);
});

test('cron : purge les installations sans présence depuis plus de 35 jours', async () => {
  const env = creerEnv();
  const sq = env.DB.sqlite;
  const today = jourParis();
  const vieux = decaler(today, -50);
  const ins = sq.prepare('INSERT INTO installations VALUES (?,?)');
  ins.run('mort', vieux);                 // jamais revenue, ancienne : purgée
  ins.run('mort2', vieux);                // dernière présence il y a 40 jours : purgée
  ins.run('vivante', vieux);              // présence récente : gardée
  ins.run('neuve', decaler(today, -2));   // neuve sans présence : gardée
  ins.run('limite', decaler(today, -35)); // pile 35 jours : gardée
  sq.prepare('INSERT INTO presences VALUES (?,?,?)').run(decaler(today, -40), 'mort2', '0.9.0');
  sq.prepare('INSERT INTO presences VALUES (?,?,?)').run(decaler(today, -3), 'vivante', '0.9.0');
  await agreger(env);
  const restantes = sq.prepare('SELECT empreinte FROM installations ORDER BY empreinte').all().map((r) => r.empreinte);
  assert.deepEqual(restantes, ['limite', 'neuve', 'vivante']);
});

test('corps : Content-Length > 1024 refusé sans lire le corps', async () => {
  const env = creerEnv();
  let lu = false;
  for (const chemin of ['/v1/signal', '/v1/installation']) {
    // highWaterMark 0 : aucune lecture anticipée, seul un reader du Worker déclencherait pull().
    const requete = new Request('https://edu.mathys.cc' + chemin, {
      method: 'POST',
      body: new ReadableStream({ pull(c) { lu = true; c.close(); } }, { highWaterMark: 0 }),
      duplex: 'half', headers: { 'Content-Length': '1025' },
    });
    lu = false;
    const r = await worker.fetch(requete, env);
    assert.equal(r.status, 413);
    assert.equal(lu, false);
  }
});

test('corps : lecture bornée sans Content-Length (flux de blocs)', async () => {
  const env = creerEnv();
  let blocs = 0;
  const flux = new ReadableStream({ pull(c) { blocs++; c.enqueue(new Uint8Array(600)); if (blocs >= 50) c.close(); } });
  const r = await worker.fetch(new Request('https://edu.mathys.cc/v1/signal', { method: 'POST', body: flux, duplex: 'half' }), env);
  assert.equal(r.status, 413);
  assert.ok(blocs <= 4, `blocs lus : ${blocs}`);
});

test('corps : exactement 1024 octets accepté (puis 400 car pas du JSON valide)', async () => {
  const env = creerEnv();
  const r = await appeler(env, 'POST', '/v1/signal', { corps: 'x'.repeat(1024) });
  assert.equal(r.status, 400);
});

test('signal : limiteur dédié => 429, sans accès D1', async () => {
  const env = creerEnv({ LIMITER_SIGNAL: { limit: async () => ({ success: false }) } });
  const { id } = await (await appeler(creerEnv(), 'POST', '/v1/installation')).json();
  const r = await signaler(env, id);
  assert.equal(r.status, 429);
  assert.deepEqual(await r.json(), { erreur: 'limite' });
  assert.equal(env.DB.sqlite.prepare('SELECT COUNT(*) n FROM presences').get().n, 0);
});

test('toutes les réponses portent X-Content-Type-Options: nosniff', async () => {
  const env = creerEnv();
  const { id } = await (await appeler(env, 'POST', '/v1/installation')).json();
  const reponses = [
    await appeler(env, 'POST', '/v1/installation'),
    await signaler(env, id),
    await appeler(env, 'POST', '/v1/signal', { corps: 'pas du json' }),
    await appeler(env, 'GET', '/v1/stats'),
    await appeler(env, 'GET', '/v1/stats', { jeton: 'secret-de-test' }),
    await appeler(env, 'GET', '/'),
  ];
  for (const r of reponses) assert.equal(r.headers.get('X-Content-Type-Options'), 'nosniff', String(r.status));
});

test('stats : presence_la_plus_ancienne (null sans présence, sinon la plus vieille date)', async () => {
  const env = creerEnv();
  const lire = async () => (await (await appeler(env, 'GET', '/v1/stats', { jeton: 'secret-de-test' })).json());
  assert.equal((await lire()).presence_la_plus_ancienne, null);
  const sq = env.DB.sqlite;
  const today = jourParis();
  sq.prepare('INSERT INTO presences VALUES (?,?,?)').run(decaler(today, -12), 'e1', '0.9.0');
  sq.prepare('INSERT INTO presences VALUES (?,?,?)').run(decaler(today, -2), 'e2', '0.9.0');
  const s = await lire();
  assert.equal(s.presence_la_plus_ancienne, decaler(today, -12));
  assert.equal(s.installations, 0);
});

test('stats : ne lit plus jours_agreges (toujours vide sur 30 jours)', async () => {
  const env = creerEnv();
  const requetes = [];
  const prepare = env.DB.prepare;
  env.DB.prepare = (sql) => { requetes.push(sql); return prepare(sql); };
  await appeler(env, 'GET', '/v1/stats', { jeton: 'secret-de-test' });
  assert.ok(requetes.length > 0);
  assert.ok(!requetes.some((q) => q.includes('jours_agreges')));
});

test('tout le reste : 404, sans CORS', async () => {
  const env = creerEnv();
  for (const [m, p] of [['GET', '/'], ['GET', '/v1/installation'], ['POST', '/v1/stats'], ['DELETE', '/v1/signal']]) {
    const r = await appeler(env, m, p);
    assert.equal(r.status, 404);
    assert.equal(r.headers.get('Access-Control-Allow-Origin'), null);
  }
});

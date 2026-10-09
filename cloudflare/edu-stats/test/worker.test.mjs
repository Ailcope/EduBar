// node --test cloudflare/edu-stats/test/ ; D1 simulé avec node:sqlite (vrai SQL, en mémoire).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import worker, { jourParis, decaler, agreger } from '../worker.js';

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

test('tout le reste : 404, sans CORS', async () => {
  const env = creerEnv();
  for (const [m, p] of [['GET', '/'], ['GET', '/v1/installation'], ['POST', '/v1/stats'], ['DELETE', '/v1/signal']]) {
    const r = await appeler(env, m, p);
    assert.equal(r.status, 404);
    assert.equal(r.headers.get('Access-Control-Allow-Origin'), null);
  }
});

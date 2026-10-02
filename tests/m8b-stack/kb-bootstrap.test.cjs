'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const kb = require('../../charts/m8b-stack/files/scripts/kb-bootstrap.cjs');
function fixture(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'm8b-kb-test-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const env = { ...process.env, M8B_DATA_DIR: dir, AI_PROVIDER: 'vllm',
    AI_EMBEDDING_MODEL: 'test-embedding', AI_EMBEDDING_BASE_URL: 'http://unused.invalid/v1',
    M8B_KB_BOOTSTRAP_MODE: 'if-missing', M8B_KB_EMPTY_POLICY: 'fail',
    M8B_KB_TIMEOUT_SECONDS: '120', M8B_KB_SEED_CONFIGURED: 'false',
    AI_API_KEY: 'FAKE-SECRET-NOT-FOR-LOGS' };
  delete env.KNOWLEDGE_BASE_DIR;
  const root = path.join(dir, 'knowledge'), docs = path.join(root, 'docs');
  fs.mkdirSync(docs, { recursive: true });
  const index = path.join(root, 'index.json');
  const indexer = path.join(dir, 'fake-indexer.cjs');
  fs.writeFileSync(indexer, `const fs=require('node:fs'),path=require('node:path');
const root=process.env.KNOWLEDGE_BASE_DIR||path.join(process.env.M8B_DATA_DIR,'knowledge');
const docs=path.join(root,'docs');fs.mkdirSync(docs,{recursive:true});
if(fs.readdirSync(docs).filter(x=>/\.md$/i.test(x)).length===0)fs.writeFileSync(path.join(docs,'metricshub-official-test.md'),'# Official test corpus');
fs.writeFileSync(path.join(root,'index.json'),JSON.stringify({version:1,chunks:[{text:'test only',embedding:[1,0]}]}));`);
  return { dir, root, docs, env, index, indexer, opts: { indexer, cwd: dir } };
}
test('missing documents request automatic official-corpus initialization', t => {
  const f=fixture(t);const plan=kb.plan(f.env);assert.equal(plan.action,'index');assert.equal(plan.documents,0);assert.match(plan.reason,/official corpus/);
});
test('empty first run provisions documents and an index through the M8B indexer', t => {
  const f=fixture(t);const got=kb.run(f.env,f.opts);assert.equal(got.action,'indexed');assert.equal(got.documents,1);assert.equal(fs.existsSync(f.index),true);
});
test('read-only plan requests an index and never modifies files', t => {
  const f=fixture(t);fs.writeFileSync(path.join(f.docs,'a.md'),'# A');assert.equal(kb.plan(f.env).action,'index');assert.deepEqual(fs.readdirSync(f.root),['docs']);
});
test('legacy index is preserved byte-for-byte, no adoption marker fabricated', t => {
  const f=fixture(t);const bytes='{"chunks":[{"embedding":[0.2,0.8]}]}';fs.writeFileSync(f.index,bytes);
  const got=kb.run(f.env,f.opts);assert.equal(got.action,'preserve');assert.equal(got.tracked,false);
  assert.equal(fs.readFileSync(f.index,'utf8'),bytes);assert.equal(fs.existsSync(path.join(f.root,'.stack-kb-state.json')),false);
});
test('invalid existing JSON requires an explicit force', t => {
  const f=fixture(t);fs.writeFileSync(f.index,'not-json');assert.throws(()=>kb.plan(f.env),/not valid JSON/);
});
test('empty chunks are not accepted as usable index', t => {
  const f=fixture(t);fs.writeFileSync(f.index,'{"chunks":[]}');assert.throws(()=>kb.plan(f.env),/zero chunks/);
});
test('real Node child execution creates index, stores state and removes lock', t => {
  const f=fixture(t);fs.writeFileSync(path.join(f.docs,'a.md'),'# A');const result=kb.run(f.env,f.opts);
  assert.equal(result.action,'indexed');assert.equal(result.documents,1);assert.equal(kb.plan(f.env).action,'preserve');
  assert.equal(fs.existsSync(path.join(f.root,'.stack-kb.lock')),false);
  assert.equal(fs.readFileSync(path.join(f.root,'.stack-kb-state.json'),'utf8').includes('FAKE-SECRET'),false);
});
test('changed embedding configuration requires explicit rebuild', t => {
  const f=fixture(t);fs.writeFileSync(path.join(f.docs,'a.md'),'# A');kb.run(f.env,f.opts);
  f.env.AI_EMBEDDING_MODEL='other';assert.throws(()=>kb.plan(f.env),/configuration changed/);
  f.env.M8B_KB_BOOTSTRAP_MODE='always';assert.equal(kb.plan(f.env).action,'index');
});
test('null/unset and explicit empty prefixes remain distinguishable', t => {
  const f=fixture(t);delete f.env.AI_EMBEDDING_QUERY_PREFIX;const a=kb.settings(f.env).hash;
  f.env.AI_EMBEDDING_QUERY_PREFIX='';assert.notEqual(a,kb.settings(f.env).hash);
});
test('forced full rebuild backs up previous bytes', t => {
  const f=fixture(t);fs.writeFileSync(path.join(f.docs,'a.md'),'# A');const original='{"chunks":[{"old":true}]}';fs.writeFileSync(f.index,original);
  f.env.M8B_KB_BOOTSTRAP_MODE='always';const got=kb.run(f.env,f.opts);
  assert.equal(fs.readFileSync(got.backup,'utf8'),original);assert.notEqual(fs.readFileSync(f.index,'utf8'),original);
});
test('failed rebuild restores previous index', t => {
  const f=fixture(t);fs.writeFileSync(path.join(f.docs,'a.md'),'# A');const original='{"chunks":[{"old":true}]}';fs.writeFileSync(f.index,original);
  f.env.M8B_KB_BOOTSTRAP_MODE='always';fs.writeFileSync(f.indexer,"require('node:fs').writeFileSync(process.env.M8B_DATA_DIR+'/knowledge/index.json','broken');process.exit(9);");
  assert.throws(()=>kb.run(f.env,f.opts),/exit=9/);assert.equal(fs.readFileSync(f.index,'utf8'),original);
});
test('a false-positive indexer success without index fails', t => {
  const f=fixture(t);fs.writeFileSync(path.join(f.docs,'a.md'),'# A');fs.writeFileSync(f.indexer,'process.exit(0);');
  assert.throws(()=>kb.run(f.env,f.opts),/not created/);assert.equal(fs.existsSync(path.join(f.root,'.stack-kb-state.json')),false);
});
test('indexer timeout is surfaced without pretending success', t => {
  const f=fixture(t);fs.writeFileSync(path.join(f.docs,'a.md'),'# A');
  assert.throws(()=>kb.run(f.env,{...f.opts,spawn:()=>({error:{code:'ETIMEDOUT'}})}),/ETIMEDOUT/);
});
test('stale lock is never silently removed by another run', t => {
  const f=fixture(t);fs.writeFileSync(path.join(f.docs,'a.md'),'# A');const lock=path.join(f.root,'.stack-kb.lock');fs.mkdirSync(lock);
  assert.throws(()=>kb.run(f.env,f.opts),/lock exists/);assert.equal(fs.existsSync(lock),true);
});
test('seed documents are copied into PVC before indexing', t => {
  const f=fixture(t);const seed=path.join(f.dir,'seed');fs.mkdirSync(seed);fs.writeFileSync(path.join(seed,'seed.md'),'# Seed');f.env.M8B_KB_SEED_CONFIGURED='true';
  assert.equal(kb.run(f.env,{...f.opts,seedDir:seed}).action,'indexed');assert.equal(fs.readFileSync(path.join(f.docs,'seed.md'),'utf8'),'# Seed');
});
test('seed cannot overwrite an existing document', t => {
  const f=fixture(t);const seed=path.join(f.dir,'seed');fs.mkdirSync(seed);fs.writeFileSync(path.join(seed,'a.md'),'replacement');fs.writeFileSync(path.join(f.docs,'a.md'),'original');f.env.M8B_KB_SEED_CONFIGURED='true';
  assert.throws(()=>kb.run(f.env,{...f.opts,seedDir:seed}),/overwrite/);assert.equal(fs.readFileSync(path.join(f.docs,'a.md'),'utf8'),'original');
});
test('custom data and knowledge directory stay on the configured volume', t => {
  const f=fixture(t);f.env.KNOWLEDGE_BASE_DIR=path.join(f.dir,'my-kb');assert.equal(kb.settings(f.env).root,f.env.KNOWLEDGE_BASE_DIR);
  f.env.KNOWLEDGE_BASE_DIR='/outside';assert.throws(()=>kb.settings(f.env),/inside/);
});
test('symlinks in document tree are rejected', t => {
  const f=fixture(t);fs.symlinkSync('/etc/passwd',path.join(f.docs,'link.md'));assert.throws(()=>kb.plan(f.env),/Symlink/);
});

test('forced rebuild refuses an index symlink', t => {
  const f=fixture(t);fs.writeFileSync(path.join(f.docs,'a.md'),'# A');fs.symlinkSync('/etc/passwd',f.index);f.env.M8B_KB_BOOTSTRAP_MODE='always';
  assert.throws(()=>kb.plan(f.env),/regular file/);
});

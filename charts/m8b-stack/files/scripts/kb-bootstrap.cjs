'use strict';
/* KB maintenance only. Run after all bot Pods have terminated.
 * Uses the indexer shipped in the M8B image; it does NOT implement a RAG format.
 * No Kubernetes API access and no secret values are logged by this wrapper.
 */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');

function settings(env = process.env) {
  const data = path.resolve(env.M8B_DATA_DIR || '/var/lib/m8b');
  const root = path.resolve(env.KNOWLEDGE_BASE_DIR || path.join(data, 'knowledge'));
  if (!root.startsWith(data + path.sep)) throw new Error('KB directory must be inside M8B_DATA_DIR');
  if (!env.AI_EMBEDDING_MODEL || !env.AI_EMBEDDING_BASE_URL) {
    throw new Error('Explicit AI_EMBEDDING_MODEL and AI_EMBEDDING_BASE_URL are required');
  }
  if (env.AI_PROVIDER !== 'vllm' && env.AI_PROVIDER !== 'openai-compatible' && env.AI_PROVIDER !== 'ollama') {
    throw new Error('This bootstrap is for a local self-hosted KB, not hosted vector stores');
  }
  const mode = env.M8B_KB_BOOTSTRAP_MODE || 'if-missing';
  const emptyPolicy = env.M8B_KB_EMPTY_POLICY || 'fail';
  if (!['if-missing', 'always'].includes(mode)) throw new Error('Invalid bootstrap mode');
  if (!['fail', 'skip'].includes(emptyPolicy)) throw new Error('Invalid empty policy');
  const timeout = Number(env.M8B_KB_TIMEOUT_SECONDS || 3600);
  if (!Number.isInteger(timeout) || timeout < 120 || timeout > 86400) throw new Error('Invalid indexing timeout');
  const keys = ['AI_PROVIDER', 'AI_EMBEDDING_BASE_URL', 'AI_EMBEDDING_MODEL',
    'AI_EMBEDDING_QUERY_PREFIX', 'AI_EMBEDDING_DOCUMENT_PREFIX',
    'AI_EMBEDDING_QUERY_INPUT_TYPE', 'AI_EMBEDDING_DOCUMENT_INPUT_TYPE'];
  const signature = Object.fromEntries(keys.map(k => [k, env[k] === undefined ? null : env[k]]));
  // API keys are deliberately excluded from both the signature and stored metadata.
  const hash = crypto.createHash('sha256').update(JSON.stringify(signature)).digest('hex');
  return { data, root, docs: path.join(root, 'docs'), index: path.join(root, 'index.json'),
    state: path.join(root, '.stack-kb-state.json'), lock: path.join(root, '.stack-kb.lock'),
    mode, emptyPolicy, timeout, hash, seed: env.M8B_KB_SEED_CONFIGURED === 'true' };
}
function exists(file) {
  try { fs.lstatSync(file); return true; } catch (e) { if (e.code === 'ENOENT') return false; throw e; }
}
function documents(dir) {
  if (!exists(dir)) return [];
  const out = [];
  function visit(current) {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const file = path.join(current, entry.name);
      if (entry.isSymbolicLink()) throw new Error('Symlink in KB docs is not supported: ' + entry.name);
      if (entry.isDirectory()) visit(file);
      else if (entry.isFile() && /\.md$/i.test(entry.name)) out.push(file);
    }
  }
  visit(dir);
  return out;
}
function inspectIndex(file) {
  if (!exists(file)) return { exists: false, bytes: 0 };
  const stat = fs.lstatSync(file);
  if (!stat.isFile()) throw new Error('Index is not a regular file');
  if (stat.size === 0) throw new Error('Index is empty; review and use --force to rebuild');
  let value;
  try { value = JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (_) { throw new Error('Index is not valid JSON; review and use --force to rebuild'); }
  if (!value || typeof value !== 'object' || Object.keys(value).length === 0) {
    throw new Error('Index has no data; review and use --force to rebuild');
  }
  // Only a sanity check. The actual versioned index format is owned by M8B.
  if (Array.isArray(value.chunks) && value.chunks.length === 0) throw new Error('Index has zero chunks');
  return { exists: true, bytes: stat.size };
}
function plan(env = process.env) {
  const cfg = settings(env);
  const files = documents(cfg.docs);
  let index;
  try { index = inspectIndex(cfg.index); }
  catch (error) {
    if (cfg.mode !== 'always' || (exists(cfg.index) && !fs.lstatSync(cfg.index).isFile())) throw error;
    index = { exists: exists(cfg.index), bytes: 0, invalid: true };
  }
  if (index.exists && cfg.mode === 'if-missing') {
    let tracked = false;
    if (exists(cfg.state)) {
      const state = JSON.parse(fs.readFileSync(cfg.state, 'utf8'));
      tracked = true;
      if (state.configHash !== cfg.hash) throw new Error('Embedding configuration changed since bootstrap; review and run kb-init --force');
    }
    return { action: 'preserve', documents: files.length, indexBytes: index.bytes,
      tracked, reason: tracked ? 'Existing index retained; no rebuild requested' : 'Existing untracked index retained; retrieval compatibility must be validated in M8B' };
  }
  return { action: 'index', documents: files.length, indexBytes: index.bytes,
    reason: cfg.mode === 'always' ? 'Explicit full rebuild' :
      (files.length === 0 ? 'No index present; M8B indexer will initialize the official corpus' : 'No index present') };
}
function copySeed(cfg, seedDir) {
  if (!cfg.seed) return;
  if (!exists(seedDir)) throw new Error('Configured seed ConfigMap is not mounted');
  for (const name of fs.readdirSync(seedDir)) {
    if (!/^[A-Za-z0-9_.-]+\.md$/i.test(name)) continue;
    const source = path.join(seedDir, name), dest = path.join(cfg.docs, name);
    // ConfigMap projection uses symlinks. Reading them is intentional, writing through one is not.
    if (!fs.statSync(source).isFile()) continue;
    if (exists(dest)) {
      if (!fs.lstatSync(dest).isFile() || !fs.readFileSync(dest).equals(fs.readFileSync(source))) {
        throw new Error('Seed would overwrite an existing document: ' + name);
      }
    } else fs.copyFileSync(source, dest, fs.constants.COPYFILE_EXCL);
  }
}
function atomicJson(file, value) {
  const tmp = file + '.tmp-' + process.pid;
  fs.writeFileSync(tmp, JSON.stringify(value, null, 2) + '\n', { mode: 0o660, flag: 'wx' });
  fs.renameSync(tmp, file);
}
function run(env = process.env, options = {}) {
  const cfg = settings(env);
  let decision = plan(env);
  if (decision.action !== 'index') { console.log('[KB bootstrap]', JSON.stringify(decision)); return decision; }
  fs.mkdirSync(cfg.docs, { recursive: true, mode: 0o2770 });
  if (!fs.realpathSync(cfg.docs).startsWith(fs.realpathSync(cfg.data) + path.sep)) throw new Error('KB resolves outside the persistent data directory');
  try { fs.mkdirSync(cfg.lock, { mode: 0o770 }); }
  catch (e) { if (e.code === 'EEXIST') throw new Error('KB lock exists; inspect other indexers/Jobs before removing ' + cfg.lock); throw e; }
  let backup = null, indexExisted = exists(cfg.index), changed = false;
  try {
    atomicJson(path.join(cfg.lock, 'owner.json'), { pid: process.pid, startedAt: new Date().toISOString() });
    // Recheck after the lock: another completed maintenance run may have created the index.
    decision = plan(env);
    if (decision.action !== 'index') { console.log('[KB bootstrap]', JSON.stringify(decision)); return decision; }
    indexExisted = exists(cfg.index);
    copySeed(cfg, options.seedDir || '/kb-seed');
    if (documents(cfg.docs).length === 0) {
      console.log('[KB bootstrap] No Markdown documents are present yet; the M8B indexer will initialize the official corpus.');
    }
    const stamp = new Date().toISOString().replace(/[:.]/g, '-') + '-' + process.pid;
    if (indexExisted) {
      backup = path.join(cfg.root, 'index.pre-bootstrap-' + stamp + '.json');
      fs.copyFileSync(cfg.index, backup, fs.constants.COPYFILE_EXCL);
      console.log('[KB bootstrap] Previous index backed up; no documents are removed.');
    }
    const indexer = options.indexer || '/app/scripts/index-knowledge.js';
    if (!fs.existsSync(indexer)) throw new Error('M8B indexer is absent from the image: ' + indexer);
    console.log('[KB bootstrap] Starting the M8B indexer. Bot Pods must remain stopped.');
    const child = (options.spawn || spawnSync)(process.execPath, [indexer], {
      env, cwd: options.cwd || '/app', stdio: 'inherit',
      timeout: (cfg.timeout - 15) * 1000, killSignal: 'SIGKILL'
    });
    changed = true;
    if (child.error) throw new Error('Indexer failed or timed out: ' + child.error.code);
    if (child.status !== 0) throw new Error('Indexer failed: exit=' + child.status + ', signal=' + (child.signal || 'none'));
    const index = inspectIndex(cfg.index);
    if (!index.exists) throw new Error('Indexer returned success but index.json was not created');
    const count = documents(cfg.docs).length;
    if (count === 0) throw new Error('Indexer created an index but no Markdown documents; official KB initialization is incomplete');
    atomicJson(cfg.state, { version: 1, configHash: cfg.hash, documents: count,
      indexBytes: index.bytes, completedAt: new Date().toISOString() });
    const result = { action: 'indexed', documents: count, indexBytes: index.bytes, backup };
    console.log('[KB bootstrap]', JSON.stringify(result));
    console.log('[KB bootstrap] Start a NEW bot Pod to load this index.');
    return result;
  } catch (error) {
    if (changed && backup) {
      const restore = cfg.index + '.restore-' + process.pid;
      fs.copyFileSync(backup, restore, fs.constants.COPYFILE_EXCL);
      fs.renameSync(restore, cfg.index);
      console.error('[KB bootstrap] Failed rebuild: previous index restored. Bot must remain stopped for review.');
    } else if (changed && !indexExisted && exists(cfg.index)) {
      fs.renameSync(cfg.index, cfg.index + '.failed-' + Date.now());
    }
    throw error;
  } finally {
    fs.rmSync(cfg.lock, { recursive: true, force: true });
  }
}
module.exports = { settings, documents, inspectIndex, plan, run };
if (require.main === module) {
  try {
    const command = process.argv[2] || 'status';
    if (command === 'status') console.log(JSON.stringify(plan()));
    else if (command === 'run') run();
    else throw new Error('Usage: kb-bootstrap.cjs status|run');
  } catch (error) { console.error('[KB bootstrap] ERROR:', error.message); process.exitCode = 1; }
}

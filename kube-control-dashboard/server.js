import http from 'node:http';
import { spawn } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const PUBLIC_DIR = path.join(__dirname, 'public');

const HOST = process.env.HOST || '127.0.0.1';
const PORT = Number(process.env.PORT || 8787);
const WRITE_ENABLED = String(process.env.DASHBOARD_WRITE_ENABLED || 'false').toLowerCase() === 'true';
const MAX_MANIFEST_BYTES = Number(process.env.MAX_MANIFEST_BYTES || 524288);
const MAX_JSON_BYTES = Math.max(MAX_MANIFEST_BYTES + 64 * 1024, 1024 * 1024);

const mime = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
};

function headers(extra = {}) {
  return {
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
    'X-Frame-Options': 'DENY',
    'Cache-Control': 'no-store',
    ...extra,
  };
}

function send(res, status, body, contentType = 'application/json; charset=utf-8') {
  const payload = contentType.startsWith('application/json') && typeof body !== 'string'
    ? JSON.stringify(body)
    : String(body ?? '');
  res.writeHead(status, headers({ 'Content-Type': contentType, 'Content-Length': Buffer.byteLength(payload) }));
  res.end(payload);
}

function sendJson(res, status, body) { send(res, status, body); }
function sendText(res, status, body) { send(res, status, body, 'text/plain; charset=utf-8'); }

async function readJson(req) {
  const chunks = [];
  let total = 0;
  for await (const chunk of req) {
    total += chunk.length;
    if (total > MAX_JSON_BYTES) throw new HttpError(413, 'Request body is too large');
    chunks.push(chunk);
  }
  if (!chunks.length) return {};
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { throw new HttpError(400, 'Invalid JSON body'); }
}

class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

function assertSimpleName(value, label, { allowAll = false } = {}) {
  if (allowAll && value === 'all') return value;
  if (typeof value !== 'string' || !/^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$/i.test(value)) {
    throw new HttpError(400, `Invalid ${label}`);
  }
  return value;
}

function parsePositiveInt(value, label, min = 0, max = 10000) {
  const n = Number(value);
  if (!Number.isInteger(n) || n < min || n > max) throw new HttpError(400, `Invalid ${label}`);
  return n;
}

function run(bin, args, { stdin, timeoutMs = 20000 } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(bin, args, { env: process.env, stdio: ['pipe', 'pipe', 'pipe'], shell: false });
    let stdout = '';
    let stderr = '';
    let killed = false;
    const timer = setTimeout(() => { killed = true; child.kill('SIGTERM'); }, timeoutMs);

    child.stdout.on('data', (d) => { stdout += d.toString(); });
    child.stderr.on('data', (d) => { stderr += d.toString(); });
    child.on('error', (err) => { clearTimeout(timer); reject(err); });
    child.on('close', (code) => {
      clearTimeout(timer);
      if (killed) return reject(new Error(`${bin} timed out`));
      if (code !== 0) {
        const err = new Error([stderr.trim(), stdout.trim()].filter(Boolean).join('\n') || `${bin} exited with code ${code}`);
        err.code = code; err.stdout = stdout; err.stderr = stderr;
        return reject(err);
      }
      resolve({ stdout, stderr });
    });

    if (stdin != null) child.stdin.write(stdin);
    child.stdin.end();
  });
}

async function kubectl(args, opts) { return run('kubectl', args, opts); }
async function kubectlJson(args, opts) {
  const { stdout } = await kubectl([...args, '-o', 'json'], opts);
  return JSON.parse(stdout || '{}');
}
function nsArgs(namespace) { return namespace === 'all' ? ['-A'] : ['-n', assertSimpleName(namespace, 'namespace')]; }
function requireWrite() { if (!WRITE_ENABLED) throw new HttpError(403, 'Write actions are disabled. Start with DASHBOARD_WRITE_ENABLED=true to enable them.'); }

async function handleApi(req, res, url) {
  const pathname = url.pathname;
  const method = req.method || 'GET';

  if (method === 'GET' && pathname === '/api/health') {
    let kubectlAvailable = false, context = null;
    try {
      await kubectl(['version', '--client=true', '-o', 'json'], { timeoutMs: 5000 });
      kubectlAvailable = true;
      context = (await kubectl(['config', 'current-context'], { timeoutMs: 5000 })).stdout.trim();
    } catch {}
    return sendJson(res, 200, { ok: true, writeEnabled: WRITE_ENABLED, context, kubectlAvailable });
  }

  if (method === 'GET' && pathname === '/api/context') {
    const [ctx, contexts] = await Promise.all([
      kubectl(['config', 'current-context']),
      kubectl(['config', 'get-contexts', '-o', 'name']),
    ]);
    return sendJson(res, 200, {
      currentContext: ctx.stdout.trim(),
      contexts: contexts.stdout.split(/\r?\n/).map(v => v.trim()).filter(Boolean),
      writeEnabled: WRITE_ENABLED,
    });
  }

  if (method === 'POST' && pathname === '/api/context') {
    const body = await readJson(req);
    const context = String(body.context || '').trim();
    if (!context || context.startsWith('-') || /[\r\n\0]/.test(context)) throw new HttpError(400, 'Invalid context');
    const available = (await kubectl(['config', 'get-contexts', '-o', 'name'])).stdout.split(/\r?\n/).map(v => v.trim()).filter(Boolean);
    if (!available.includes(context)) throw new HttpError(400, 'Unknown kubeconfig context');
    const { stdout } = await kubectl(['config', 'use-context', context]);
    return sendJson(res, 200, { ok: true, output: stdout.trim(), currentContext: context });
  }

  if (method === 'GET' && pathname === '/api/version') {
    const { stdout } = await kubectl(['version', '-o', 'json']);
    return send(res, 200, stdout, 'application/json; charset=utf-8');
  }
  if (method === 'GET' && pathname === '/api/namespaces') return sendJson(res, 200, await kubectlJson(['get', 'namespaces']));
  if (method === 'GET' && pathname === '/api/deployments') return sendJson(res, 200, await kubectlJson(['get', 'deployments', ...nsArgs(url.searchParams.get('namespace') || 'all')]));
  if (method === 'GET' && pathname === '/api/pods') return sendJson(res, 200, await kubectlJson(['get', 'pods', ...nsArgs(url.searchParams.get('namespace') || 'all')]));
  if (method === 'GET' && pathname === '/api/services') return sendJson(res, 200, await kubectlJson(['get', 'services', ...nsArgs(url.searchParams.get('namespace') || 'all')]));
  if (method === 'GET' && pathname === '/api/nodes') return sendJson(res, 200, await kubectlJson(['get', 'nodes']));
  if (method === 'GET' && pathname === '/api/events') return sendJson(res, 200, await kubectlJson(['get', 'events', ...nsArgs(url.searchParams.get('namespace') || 'all'), '--sort-by=.lastTimestamp']));

  if (method === 'GET' && pathname === '/api/logs') {
    const namespace = assertSimpleName(url.searchParams.get('namespace') || 'default', 'namespace');
    const pod = assertSimpleName(url.searchParams.get('pod') || '', 'pod');
    const tail = parsePositiveInt(url.searchParams.get('tail') || 200, 'tail', 1, 5000);
    const args = ['logs', '-n', namespace, pod, `--tail=${tail}`, '--timestamps=true'];
    const container = url.searchParams.get('container');
    if (container) args.push('-c', assertSimpleName(container, 'container'));
    if (url.searchParams.get('previous') === 'true') args.push('--previous');
    return sendText(res, 200, (await kubectl(args, { timeoutMs: 30000 })).stdout);
  }

  if (method === 'GET' && pathname === '/api/helm/version') {
    const { stdout } = await run('helm', ['version', '--short'], { timeoutMs: 5000 });
    return sendJson(res, 200, { version: stdout.trim() });
  }
  if (method === 'GET' && pathname === '/api/helm/releases') {
    const namespace = url.searchParams.get('namespace') || 'all';
    const args = ['list', '--output', 'json'];
    namespace === 'all' ? args.push('--all-namespaces') : args.push('--namespace', assertSimpleName(namespace, 'namespace'));
    const { stdout } = await run('helm', args, { timeoutMs: 15000 });
    return sendJson(res, 200, JSON.parse(stdout || '[]'));
  }

  if (method === 'POST' && pathname === '/api/actions/rollout-status') {
    const body = await readJson(req);
    const namespace = assertSimpleName(String(body.namespace || 'default'), 'namespace');
    const deployment = assertSimpleName(String(body.deployment || ''), 'deployment');
    const { stdout } = await kubectl(['rollout', 'status', `deployment/${deployment}`, '-n', namespace, '--timeout=30s'], { timeoutMs: 35000 });
    return sendJson(res, 200, { ok: true, output: stdout.trim() });
  }

  if (method === 'POST' && pathname === '/api/actions/scale') {
    requireWrite(); const body = await readJson(req);
    const namespace = assertSimpleName(String(body.namespace || 'default'), 'namespace');
    const deployment = assertSimpleName(String(body.deployment || ''), 'deployment');
    const replicas = parsePositiveInt(body.replicas, 'replicas', 0, 500);
    const { stdout } = await kubectl(['scale', 'deployment', deployment, '-n', namespace, `--replicas=${replicas}`]);
    return sendJson(res, 200, { ok: true, output: stdout.trim() });
  }

  if (method === 'POST' && pathname === '/api/actions/restart') {
    requireWrite(); const body = await readJson(req);
    const namespace = assertSimpleName(String(body.namespace || 'default'), 'namespace');
    const deployment = assertSimpleName(String(body.deployment || ''), 'deployment');
    const { stdout } = await kubectl(['rollout', 'restart', `deployment/${deployment}`, '-n', namespace]);
    return sendJson(res, 200, { ok: true, output: stdout.trim() });
  }

  if (method === 'POST' && pathname === '/api/actions/delete-pod') {
    requireWrite(); const body = await readJson(req);
    const namespace = assertSimpleName(String(body.namespace || 'default'), 'namespace');
    const pod = assertSimpleName(String(body.pod || ''), 'pod');
    const { stdout } = await kubectl(['delete', 'pod', pod, '-n', namespace, '--wait=false']);
    return sendJson(res, 200, { ok: true, output: stdout.trim() });
  }

  if (method === 'POST' && pathname === '/api/actions/set-image') {
    requireWrite(); const body = await readJson(req);
    const namespace = assertSimpleName(String(body.namespace || 'default'), 'namespace');
    const deployment = assertSimpleName(String(body.deployment || ''), 'deployment');
    const container = assertSimpleName(String(body.container || ''), 'container');
    const image = String(body.image || '').trim();
    if (!image || image.length > 500 || /[\r\n\0]/.test(image)) throw new HttpError(400, 'Invalid image');
    const { stdout } = await kubectl(['set', 'image', `deployment/${deployment}`, `${container}=${image}`, '-n', namespace]);
    return sendJson(res, 200, { ok: true, output: stdout.trim() });
  }

  if (method === 'POST' && (pathname === '/api/actions/apply' || pathname === '/api/actions/diff')) {
    const body = await readJson(req);
    const namespace = assertSimpleName(String(body.namespace || 'default'), 'namespace');
    const manifest = String(body.manifest || '');
    if (!manifest.trim()) throw new HttpError(400, 'Manifest is empty');
    if (Buffer.byteLength(manifest, 'utf8') > MAX_MANIFEST_BYTES) throw new HttpError(413, 'Manifest is too large');

    if (pathname.endsWith('/apply')) {
      requireWrite();
      const { stdout, stderr } = await kubectl(['apply', '-n', namespace, '-f', '-'], { stdin: manifest, timeoutMs: 45000 });
      return sendJson(res, 200, { ok: true, output: [stdout.trim(), stderr.trim()].filter(Boolean).join('\n') });
    }

    try {
      const { stdout, stderr } = await kubectl(['diff', '-n', namespace, '-f', '-'], { stdin: manifest, timeoutMs: 45000 });
      return sendJson(res, 200, { ok: true, changed: false, output: [stdout.trim(), stderr.trim()].filter(Boolean).join('\n') || 'No differences.' });
    } catch (err) {
      if (err.code === 1) {
        const text = [err.stdout?.trim(), err.stderr?.trim()].filter(Boolean).join('\n') || 'Differences found.';
        return sendJson(res, 200, { ok: true, changed: true, output: text });
      }
      throw err;
    }
  }

  if (method === 'GET' && pathname === '/api/overview') {
    const scoped = nsArgs(url.searchParams.get('namespace') || 'all');
    const [version, deployments, pods, services, nodes, events, livez, readyz] = await Promise.all([
      kubectl(['version', '-o', 'json']).then(r => JSON.parse(r.stdout)),
      kubectlJson(['get', 'deployments', ...scoped]),
      kubectlJson(['get', 'pods', ...scoped]),
      kubectlJson(['get', 'services', ...scoped]),
      kubectlJson(['get', 'nodes']),
      kubectlJson(['get', 'events', ...scoped, '--sort-by=.lastTimestamp']).catch(() => ({ items: [] })),
      kubectl(['get', '--raw=/livez'], { timeoutMs: 5000 }).then(r => r.stdout.trim()).catch(err => `unavailable: ${err.message}`),
      kubectl(['get', '--raw=/readyz?verbose'], { timeoutMs: 5000 }).then(r => r.stdout.trim()).catch(err => `unavailable: ${err.message}`),
    ]);
    return sendJson(res, 200, { version, deployments, pods, services, nodes, events, controlPlane: { livez, readyz }, writeEnabled: WRITE_ENABLED });
  }

  throw new HttpError(404, 'API route not found');
}

async function serveStatic(req, res, url) {
  let rel = decodeURIComponent(url.pathname);
  if (rel === '/') rel = '/index.html';
  const safe = path.normalize(rel).replace(/^([.][.][/\\])+/, '');
  let file = path.join(PUBLIC_DIR, safe);
  if (!file.startsWith(PUBLIC_DIR)) throw new HttpError(403, 'Forbidden');

  try {
    const data = await readFile(file);
    const type = mime[path.extname(file).toLowerCase()] || 'application/octet-stream';
    res.writeHead(200, headers({ 'Content-Type': type, 'Content-Length': data.length, 'Cache-Control': path.extname(file) === '.html' ? 'no-store' : 'public, max-age=300' }));
    res.end(data);
  } catch (err) {
    if (err.code !== 'ENOENT') throw err;
    const data = await readFile(path.join(PUBLIC_DIR, 'index.html'));
    res.writeHead(200, headers({ 'Content-Type': 'text/html; charset=utf-8', 'Content-Length': data.length }));
    res.end(data);
  }
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url || '/', `http://${req.headers.host || `${HOST}:${PORT}`}`);
    if (url.pathname.startsWith('/api/')) await handleApi(req, res, url);
    else await serveStatic(req, res, url);
  } catch (err) {
    const status = err instanceof HttpError ? err.status : 500;
    sendJson(res, status, { error: err.message || String(err) });
  }
});

server.listen(PORT, HOST, () => {
  console.log(`Kube Control Dashboard: http://${HOST}:${PORT}`);
  console.log(`Write actions: ${WRITE_ENABLED ? 'ENABLED' : 'disabled'}`);
});

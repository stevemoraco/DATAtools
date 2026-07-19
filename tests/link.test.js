const assert = require('assert');
const fs = require('fs');
const http = require('http');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const cli = path.resolve(__dirname, '..', 'index.js');
const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'data-remote-link-test-'));

function runCli(args, env) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [cli, ...args], {
      env: { ...process.env, ...env },
      stdio: ['ignore', 'pipe', 'pipe']
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.on('error', reject);
    child.on('close', (status) => resolve({ status, stdout, stderr }));
  });
}

function mockServer(handler) {
  const server = http.createServer(handler);
  return new Promise((resolve, reject) => {
    server.on('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      resolve({ server, origin: `http://127.0.0.1:${address.port}` });
    });
  });
}

function close(server) {
  return new Promise((resolve) => server.close(resolve));
}

async function successCase() {
  const code = 'ABCDEFGH';
  const token = 'server-token-value-never-print';
  let requestBody;
  const { server, origin } = await mockServer((req, res) => {
    assert.strictEqual(req.method, 'POST');
    assert.strictEqual(req.url, '/api/link-code/consume');
    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => {
      requestBody = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        token,
        tokenType: 'Bearer',
        scope: 'data-remote:linked',
        userId: 'user-123',
        expiresAt: '2030-01-01T00:00:00.000Z'
      }));
    });
  });

  const poolPath = path.join(tempRoot, 'success', 'auth-profiles.json');
  try {
    const result = await runCli(['link', code], {
      ENABLE_LINK_CODE_FLOW: '1',
      DATA_REMOTE_API_BASE_URL: origin,
      DATA_REMOTE_AUTH_POOL_PATH: poolPath
    });
    assert.strictEqual(result.status, 0, result.stderr);
    assert.match(result.stdout, /credential pool linked/);
    assert.ok(!result.stdout.includes(code));
    assert.ok(!result.stdout.includes(token));
    assert.ok(!result.stderr.includes(code));
    assert.ok(!result.stderr.includes(token));
    assert.strictEqual(requestBody.code, code);
    assert.match(requestBody.poolFingerprint, /^[a-f0-9]{64}$/);

    const pool = JSON.parse(fs.readFileSync(poolPath, 'utf8'));
    const profile = Object.values(pool.profiles)[0];
    assert.strictEqual(profile.credential.token, token);
    assert.strictEqual(profile.credential.scope, 'data-remote:linked');
    assert.strictEqual(profile.poolFingerprint, requestBody.poolFingerprint);
    assert.strictEqual(fs.statSync(poolPath).mode & 0o777, 0o600);
  } finally {
    await close(server);
  }
}

async function invalidCase() {
  const code = '23456789';
  const { server, origin } = await mockServer((_req, res) => {
    res.writeHead(400, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Link code is invalid, expired, or already used' }));
  });

  const poolPath = path.join(tempRoot, 'invalid', 'auth-profiles.json');
  try {
    const result = await runCli(['link', code], {
      ENABLE_LINK_CODE_FLOW: '1',
      DATA_REMOTE_API_BASE_URL: origin,
      DATA_REMOTE_AUTH_POOL_PATH: poolPath
    });
    assert.strictEqual(result.status, 1);
    assert.match(result.stderr, /invalid, expired, or already used/);
    assert.ok(!result.stdout.includes(code));
    assert.ok(!result.stderr.includes(code));
    const pool = JSON.parse(fs.readFileSync(poolPath, 'utf8'));
    assert.deepStrictEqual(pool.profiles, {});
  } finally {
    await close(server);
  }
}

async function disabledCase() {
  const env = {
    DATA_REMOTE_AUTH_POOL_PATH: path.join(tempRoot, 'disabled', 'auth-profiles.json')
  };
  delete env.ENABLE_LINK_CODE_FLOW;
  const inherited = process.env.ENABLE_LINK_CODE_FLOW;
  delete process.env.ENABLE_LINK_CODE_FLOW;
  try {
    const result = await runCli(['link', 'ABCDEFGH'], env);
    assert.strictEqual(result.status, 1);
    assert.match(result.stderr, /disabled/);
  } finally {
    if (inherited !== undefined) process.env.ENABLE_LINK_CODE_FLOW = inherited;
  }
}

(async () => {
  try {
    await successCase();
    await invalidCase();
    await disabledCase();
    console.log('PASS link command stores scoped credential and redacts secrets');
    console.log('PASS link command reports invalid or expired codes');
    console.log('PASS link command is feature-flagged off by default');
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
})().catch((err) => {
  console.error(err.stack || err.message);
  process.exitCode = 1;
});

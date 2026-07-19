const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

const REPLIT_WORKSPACE = '/home/runner/workspace';

function defaultPoolPath() {
  if (process.env.DATA_REMOTE_AUTH_POOL_PATH) {
    return path.resolve(process.env.DATA_REMOTE_AUTH_POOL_PATH);
  }
  if (fs.existsSync(REPLIT_WORKSPACE)) {
    return path.join(REPLIT_WORKSPACE, '.replit-tools', 'auth-profiles.json');
  }
  return path.join(os.homedir(), '.data-remote', 'auth-profiles.json');
}

function readPool(poolPath = defaultPoolPath()) {
  if (!fs.existsSync(poolPath)) {
    return { version: 1, profiles: {} };
  }

  const parsed = JSON.parse(fs.readFileSync(poolPath, 'utf8'));
  if (!parsed || parsed.version !== 1 || typeof parsed.profiles !== 'object') {
    throw new Error('The local auth-profile pool has an unsupported format');
  }
  return parsed;
}

function writePool(pool, poolPath = defaultPoolPath()) {
  const directory = path.dirname(poolPath);
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });

  const temporary = `${poolPath}.${process.pid}.${crypto.randomBytes(6).toString('hex')}.tmp`;
  try {
    fs.writeFileSync(temporary, `${JSON.stringify(pool, null, 2)}\n`, {
      encoding: 'utf8',
      mode: 0o600
    });
    fs.renameSync(temporary, poolPath);
    fs.chmodSync(poolPath, 0o600);
  } finally {
    if (fs.existsSync(temporary)) fs.unlinkSync(temporary);
  }
}

function poolFingerprint(poolId) {
  return crypto
    .createHash('sha256')
    .update(`data-remote-pool-v1\n${os.hostname()}\n${poolId}`)
    .digest('hex');
}

function getOrCreatePoolIdentity(poolPath = defaultPoolPath()) {
  const pool = readPool(poolPath);
  if (!pool.poolId) {
    pool.poolId = crypto.randomUUID();
    writePool(pool, poolPath);
  }
  return {
    poolId: pool.poolId,
    poolFingerprint: poolFingerprint(pool.poolId),
    poolPath
  };
}

function writeProfile(name, profile, poolPath = defaultPoolPath()) {
  const pool = readPool(poolPath);
  pool.profiles[name] = profile;
  writePool(pool, poolPath);
}

function storeLinkedCredential(link, options = {}) {
  const poolPath = options.poolPath || defaultPoolPath();
  const pool = readPool(poolPath);
  if (!pool.poolId || poolFingerprint(pool.poolId) !== link.poolFingerprint) {
    throw new Error('The local auth-profile pool identity changed during linking');
  }

  const profileName = new URL(link.origin).hostname;
  writeProfile(profileName, {
    provider: profileName,
    type: 'linked-session',
    origin: link.origin,
    poolFingerprint: link.poolFingerprint,
    credential: {
      token: link.token,
      tokenType: link.tokenType,
      scope: link.scope,
      expiresAt: link.expiresAt
    },
    userId: link.userId,
    linkedAt: new Date().toISOString()
  }, poolPath);
}

module.exports = {
  defaultPoolPath,
  getOrCreatePoolIdentity,
  readPool,
  storeLinkedCredential,
  writeProfile
};

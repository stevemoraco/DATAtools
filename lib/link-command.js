const http = require('http');
const https = require('https');
const { getOrCreatePoolIdentity, storeLinkedCredential } = require('./auth-manager');

const DEFAULT_ORIGIN = 'https://hi.lol';

class LinkCodeError extends Error {
  constructor(message) {
    super(message);
    this.name = 'LinkCodeError';
  }
}

function postJson(url, payload) {
  return new Promise((resolve, reject) => {
    const body = Buffer.from(JSON.stringify(payload));
    const transport = url.protocol === 'https:' ? https : http;
    const request = transport.request(url, {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        'Content-Length': body.length
      }
    }, (response) => {
      const chunks = [];
      let size = 0;
      response.on('data', (chunk) => {
        size += chunk.length;
        if (size > 1024 * 1024) {
          request.destroy(new Error('Link service response was too large'));
          return;
        }
        chunks.push(chunk);
      });
      response.on('end', () => {
        const raw = Buffer.concat(chunks).toString('utf8');
        let json = {};
        try {
          json = raw ? JSON.parse(raw) : {};
        } catch {
          reject(new Error('Link service returned an invalid response'));
          return;
        }
        resolve({ status: response.statusCode || 500, json });
      });
    });

    request.setTimeout(10_000, () => request.destroy(new Error('Link service timed out')));
    request.on('error', reject);
    request.end(body);
  });
}

function statusError(status) {
  if (status === 400 || status === 410) {
    return 'Link code is invalid, expired, or already used.';
  }
  if (status === 404) {
    return 'Link-code flow is not enabled on the server.';
  }
  if (status === 429) {
    return 'Too many link attempts. Wait a minute and try again.';
  }
  return 'The link service rejected the request.';
}

async function linkLocalPool(args, options = {}) {
  if (process.env.ENABLE_LINK_CODE_FLOW !== '1') {
    throw new LinkCodeError('Link-code flow is disabled. Set ENABLE_LINK_CODE_FLOW=1 to enable it.');
  }

  if (args.length !== 1 || !/^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{8}$/i.test(args[0])) {
    throw new LinkCodeError('Enter the 8-character link code shown by hi.lol.');
  }

  const code = args[0].toUpperCase();
  const origin = process.env.DATA_REMOTE_API_BASE_URL || DEFAULT_ORIGIN;
  let consumeUrl;
  try {
    consumeUrl = new URL('/api/link-code/consume', origin);
  } catch {
    throw new LinkCodeError('DATA_REMOTE_API_BASE_URL must be a valid HTTP or HTTPS URL.');
  }
  if (!['http:', 'https:'].includes(consumeUrl.protocol)) {
    throw new LinkCodeError('DATA_REMOTE_API_BASE_URL must use HTTP or HTTPS.');
  }

  const identity = getOrCreatePoolIdentity(options.poolPath);
  let response;
  try {
    response = await postJson(consumeUrl, {
      code,
      poolFingerprint: identity.poolFingerprint
    });
  } catch (err) {
    throw new LinkCodeError(`Could not reach the link service: ${err.message}`);
  }

  if (response.status < 200 || response.status >= 300) {
    throw new LinkCodeError(statusError(response.status));
  }

  const linked = response.json;
  if (
    typeof linked.token !== 'string' || linked.token.length < 16 ||
    linked.tokenType !== 'Bearer' || linked.scope !== 'data-remote:linked' ||
    typeof linked.userId !== 'string' || typeof linked.expiresAt !== 'string'
  ) {
    throw new LinkCodeError('Link service returned an incomplete credential.');
  }

  storeLinkedCredential({
    origin: new URL(origin).origin,
    poolFingerprint: identity.poolFingerprint,
    token: linked.token,
    tokenType: linked.tokenType,
    scope: linked.scope,
    userId: linked.userId,
    expiresAt: linked.expiresAt
  }, { poolPath: identity.poolPath });

  return { origin: new URL(origin).hostname };
}

module.exports = { LinkCodeError, linkLocalPool, postJson };

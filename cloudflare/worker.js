// ============================================================================
//  FRNTZN H3L1OS - Cloudflare Worker (hybrid setup)
//
//  Hosts on:  api.heliosprima.com
//  Scripts live on GitHub raw (versioned tags). This Worker is API-only.
//
//  Endpoints:
//    GET  /v1/health                -> liveness
//    POST /v1/license/check         -> tier validation with machine binding
//    POST /v1/telemetry/event       -> opt-in event sink (anonymous)
//    GET  /v1/version               -> latest version manifest
//
//  KV bindings (created via wrangler.toml):
//    LICENSES   - key -> {tier, machines:[hash], created}
//    TELEMETRY  - 30-day TTL event log
//
//  Secrets (set via `wrangler secret put`):
//    HMAC_SECRET   - signs license responses (presence-checked by client)
//
//  Free tier: 100k req/day, 1k KV writes/day. v1 traffic fits easily.
// ============================================================================

const MAX_MACHINES_PER_KEY = 3;
const LICENSE_VALID_DAYS   = 14;
const KEY_FORMAT           = /^[A-Z0-9-]{8,64}$/;
const HASH_FORMAT          = /^[a-f0-9]{8,128}$/;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders() });
    }

    try {
      if (url.pathname === '/v1/health' && request.method === 'GET') {
        return jsonResponse({ ok: true, ts: new Date().toISOString() });
      }
      if (url.pathname === '/v1/license/check' && request.method === 'POST') {
        return await handleLicenseCheck(request, env);
      }
      if (url.pathname === '/v1/telemetry/event' && request.method === 'POST') {
        return await handleTelemetry(request, env);
      }
      if (url.pathname === '/v1/version' && request.method === 'GET') {
        return handleVersion();
      }
      return jsonResponse({ error: 'not found' }, 404);
    } catch (err) {
      console.error('worker error', err.message, err.stack);
      return jsonResponse({ error: 'internal' }, 500);
    }
  }
};


// ---------------------------------------------------------------------------
//  License check - the gate
// ---------------------------------------------------------------------------
//  Flow:
//    1. Validate input format (key + machine_hash)
//    2. If no key OR malformed -> return Light, no logging beyond format error
//    3. Look up key in KV
//    4. Not found -> return Light
//    5. Found:
//       a. Check if this machine_hash is already registered to this key
//       b. If not, count machines. If under cap, register. If over, return Light.
//       c. Return stored tier + HMAC signature + expiry
//
//  The HMAC isn't cryptographically verifiable by the client (secret stays
//  server-side). Its purpose is tamper-evidence: a forged cache will be
//  missing a properly-formatted signature, and re-validation will fail.
//
//  Anti-piracy posture: honor system + machine binding. Not enterprise DRM.
//  At $29-49/year, sophisticated cracking isn't the customer.
// ---------------------------------------------------------------------------
async function handleLicenseCheck(request, env) {
  let body = {};
  try { body = await request.json(); } catch {}

  const key          = String(body.key || '').trim();
  const machineHash  = String(body.machine_hash || '').trim();
  const clientVer    = String(body.v || '').slice(0, 16);

  const issuedAt  = new Date().toISOString();
  const expiresAt = new Date(Date.now() + LICENSE_VALID_DAYS * 86400000).toISOString();

  // No key OR no machine hash -> fail open to Light
  if (!key || !machineHash) {
    return await respondTier('Light', machineHash, issuedAt, expiresAt, env, 'no_key');
  }

  // Format validation - if malformed, treat as no key (don't leak whether key exists)
  if (!KEY_FORMAT.test(key) || !HASH_FORMAT.test(machineHash)) {
    console.log('license.check.malformed', JSON.stringify({ key_len: key.length, hash_len: machineHash.length }));
    return await respondTier('Light', machineHash, issuedAt, expiresAt, env, 'malformed');
  }

  // No KV bound = stub mode, everyone is Light
  if (!env.LICENSES) {
    return await respondTier('Light', machineHash, issuedAt, expiresAt, env, 'no_kv');
  }

  // KV lookup
  const stored = await env.LICENSES.get(key, { type: 'json' });
  if (!stored || !stored.tier) {
    console.log('license.check.unknown_key', JSON.stringify({ key_prefix: key.slice(0, 4) }));
    return await respondTier('Light', machineHash, issuedAt, expiresAt, env, 'unknown_key');
  }

  // Machine binding
  const machines = Array.isArray(stored.machines) ? stored.machines : [];
  const alreadyRegistered = machines.includes(machineHash);

  if (!alreadyRegistered) {
    if (machines.length >= MAX_MACHINES_PER_KEY) {
      console.log('license.check.machine_cap', JSON.stringify({
        key_prefix: key.slice(0, 4),
        machine_count: machines.length
      }));
      // Don't reveal that the key is real - just downgrade silently
      return await respondTier('Light', machineHash, issuedAt, expiresAt, env, 'machine_cap');
    }
    machines.push(machineHash);
    await env.LICENSES.put(key, JSON.stringify({
      tier: stored.tier,
      machines,
      created: stored.created || issuedAt,
      updated: issuedAt
    }));
    console.log('license.check.new_machine', JSON.stringify({
      key_prefix: key.slice(0, 4),
      machine_count: machines.length,
      tier: stored.tier
    }));
  } else {
    console.log('license.check.returning_machine', JSON.stringify({
      key_prefix: key.slice(0, 4),
      tier: stored.tier
    }));
  }

  return await respondTier(stored.tier, machineHash, issuedAt, expiresAt, env, 'ok');
}


async function respondTier(tier, machineHash, issuedAt, expiresAt, env, reason) {
  const signature = await sign(`${tier}|${machineHash}|${expiresAt}`, env);
  return jsonResponse({
    tier,
    machine_hash: machineHash,
    issued_at: issuedAt,
    expires_at: expiresAt,
    signature,
    reason
  });
}


async function sign(message, env) {
  // If no HMAC_SECRET is configured, return a deterministic dummy signature.
  // The client only checks the signature is present + correct length, not
  // cryptographically valid (the secret can't live in open-source code).
  const secret = env.HMAC_SECRET || 'frntzn-h3l1os-stub-secret-do-not-use-in-prod';
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(sig)).map(b => b.toString(16).padStart(2, '0')).join('');
}


// ---------------------------------------------------------------------------
//  Telemetry (opt-in only)
// ---------------------------------------------------------------------------
//  Strict allowlist of fields. Drops anything else silently.
//  No IPs, no hostnames, no usernames, no PII.
// ---------------------------------------------------------------------------
const KNOWN_EVENTS = new Set([
  'app.start', 'app.exit',
  'scan.complete',
  'fix.applied', 'fix.failed',
  'workflow.complete', 'workflow.failed',
  'bundle.exported',
  'escalation.sent'
]);

async function handleTelemetry(request, env) {
  let body = {};
  try { body = await request.json(); } catch { return jsonResponse({ error: 'bad json' }, 400); }

  const safe = {
    ts:      new Date().toISOString(),
    version: String(body.version || '').slice(0, 16),
    os:      String(body.os || '').slice(0, 32),
    event:   String(body.event || '').slice(0, 64),
    scan_id: String(body.scan_id || '').slice(0, 36),
    success: typeof body.success === 'boolean' ? body.success : null
  };

  if (!KNOWN_EVENTS.has(safe.event)) {
    return jsonResponse({ error: 'unknown event' }, 400);
  }

  console.log('telemetry', JSON.stringify(safe));

  if (env.TELEMETRY) {
    const id = crypto.randomUUID();
    await env.TELEMETRY.put(`evt:${safe.ts}:${id}`, JSON.stringify(safe), {
      expirationTtl: 60 * 60 * 24 * 30
    });
  }

  return jsonResponse({ ok: true });
}


// ---------------------------------------------------------------------------
//  Version manifest
// ---------------------------------------------------------------------------
function handleVersion() {
  return jsonResponse({
    latest: '1.0.0',
    released: '2026-05-13',
    windows_url: 'https://raw.githubusercontent.com/PH30N1X-PR1Me/frntzn-h3l1os/v1.0.0/src/windows/h3l1os.ps1',
    mac_url:     'https://raw.githubusercontent.com/PH30N1X-PR1Me/frntzn-h3l1os/v1.0.0/src/mac/h3l1os.sh',
    changelog:   'https://github.com/PH30N1X-PR1Me/frntzn-h3l1os/releases',
    min_supported: '1.0.0'
  });
}


// ---------------------------------------------------------------------------
//  Helpers
// ---------------------------------------------------------------------------
function corsHeaders() {
  return {
    'Access-Control-Allow-Origin':  '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, User-Agent',
    'Access-Control-Max-Age':       '86400'
  };
}

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type':  'application/json',
      'Cache-Control': 'no-store',
      ...corsHeaders()
    }
  });
}

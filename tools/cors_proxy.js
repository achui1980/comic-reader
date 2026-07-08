// Simple CORS proxy for Flutter web development.
// Run with: node cors_proxy.js
//
// This proxies all requests and adds CORS headers so the Flutter web app
// can make cross-origin requests to manga source APIs.
//
// Supports X-Proxy-* headers: the Flutter app moves browser-forbidden headers
// (User-Agent, Referer) to X-Proxy-User-Agent / X-Proxy-Referer, and this
// proxy restores them before forwarding.
//
// Supports dynamic proxy configuration via /__proxy_config endpoint.

const http = require('http');
const https = require('https');
const url = require('url');
const { spawn } = require('child_process');

const PORT = 9090;

// ---- Optional curl-impersonate integration (opt-in, per-host) ----
// Some sites (e.g. manga18.club) sit behind Cloudflare's TLS/JA3 fingerprint
// check. Node's https.request uses OpenSSL, whose JA3 is flagged as a bot and
// gets a 403. curl-impersonate replays a real Chrome TLS/HTTP2 fingerprint and
// passes the check.
//
// This is fully opt-in and zero-impact when disabled:
//   - CURL_IMPERSONATE_HOSTS: comma-separated exact hostnames to route through
//     curl-impersonate. Empty/unset => feature completely off (behaves 100%
//     like before). Matching is EXACT hostname only (e.g. "manga18.club"),
//     so subdomains like "cdn.manga18.club" are NOT affected and keep using
//     the fast native Node path.
//   - CURL_IMPERSONATE_BIN: wrapper binary name/path. Default "curl_chrome136".
//     (Note: curl_chrome124/131 currently get 403 from manga18's CF; 116/136/
//     142/146 pass. 136 is a safe default.)
//
// Example: CURL_IMPERSONATE_HOSTS=manga18.club node tools/cors_proxy.js
const IMPERSONATE_HOSTS = (process.env.CURL_IMPERSONATE_HOSTS || '')
  .split(',')
  .map((s) => s.trim().toLowerCase())
  .filter(Boolean);
const IMPERSONATE_BIN = process.env.CURL_IMPERSONATE_BIN || 'curl_chrome136';

// Headers that curl-impersonate manages itself as part of the browser
// fingerprint. We must NOT override these, or the fingerprint breaks.
const IMPERSONATE_MANAGED_HEADERS = new Set([
  'user-agent',
  'accept',
  'accept-encoding',
  'sec-ch-ua',
  'sec-ch-ua-mobile',
  'sec-ch-ua-platform',
  'sec-fetch-dest',
  'sec-fetch-mode',
  'sec-fetch-site',
  'sec-fetch-user',
  'upgrade-insecure-requests',
  'host',
  'connection',
  'content-length',
]);

function shouldImpersonate(hostname) {
  const h = (hostname || '').toLowerCase();
  // Exact match only (option A): main site goes through impersonate, image CDN
  // subdomains keep the fast native path.
  return IMPERSONATE_HOSTS.includes(h);
}

// Upstream proxy support: reads HTTPS_PROXY / HTTP_PROXY from env
let currentProxyUrl = process.env.HTTPS_PROXY || process.env.HTTP_PROXY || process.env.https_proxy || process.env.http_proxy || '';

let proxyAgent = null;

// Stored auth tokens for specific hosts (set dynamically via API)
const hostTokens = {};  // e.g. { 'picacomic.com': 'token_value' }

function createProxyAgent(proxyUrl) {
  if (!proxyUrl) {
    proxyAgent = null;
    return;
  }
  try {
    const { HttpsProxyAgent } = require('https-proxy-agent');
    proxyAgent = new HttpsProxyAgent(proxyUrl);
    console.log(`[proxy] Using upstream proxy: ${proxyUrl}`);
  } catch (e) {
    console.log(`[proxy] Warning: https-proxy-agent not installed. Run: npm install https-proxy-agent`);
    proxyAgent = null;
  }
}

// Initialize with env var
createProxyAgent(currentProxyUrl);

function buildCorsHeaders(req) {
  return {
    'Access-Control-Allow-Origin': req.headers.origin || '*',
    'Access-Control-Allow-Methods': req.headers['access-control-request-method'] || 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': req.headers['access-control-request-headers'] || 'Content-Type',
    'Access-Control-Max-Age': '86400',
  };
}

const server = http.createServer((req, res) => {
  // Handle preflight
  if (req.method === 'OPTIONS') {
    res.writeHead(204, buildCorsHeaders(req));
    res.end();
    return;
  }

  // ---- Dynamic proxy config API ----
  if (req.url === '/__proxy_config') {
    if (req.method === 'GET') {
      res.writeHead(200, {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      });
      res.end(JSON.stringify({ proxy: currentProxyUrl }));
      return;
    }
    if (req.method === 'POST') {
      let body = '';
      req.on('data', chunk => { body += chunk; });
      req.on('end', () => {
        try {
          const data = JSON.parse(body);
          const newProxy = (data.proxy || '').trim();
          currentProxyUrl = newProxy;
          createProxyAgent(newProxy);
          console.log(`[proxy] Proxy updated to: ${newProxy || '(none - direct)'}`);
          res.writeHead(200, {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          });
          res.end(JSON.stringify({ proxy: currentProxyUrl, status: 'ok' }));
        } catch (e) {
          res.writeHead(400, {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          });
          res.end(JSON.stringify({ error: 'Invalid JSON' }));
        }
      });
      return;
    }
  }

  // /__host_token - store auth tokens for specific hosts (used for PICA CDN)
  if (req.url === '/__host_token') {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }
    if (req.method === 'GET') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(hostTokens));
      return;
    }
    if (req.method === 'POST') {
      let body = '';
      req.on('data', chunk => { body += chunk; });
      req.on('end', () => {
        try {
          const data = JSON.parse(body);
          // { host: "picacomic.com", token: "xxx", header: "Authorization" }
          const host = (data.host || '').trim();
          const token = (data.token || '').trim();
          const header = (data.header || 'Authorization').trim();
          if (host && token) {
            hostTokens[host] = { token, header };
            console.log(`[token] Stored token for ${host} (header: ${header})`);
          } else if (host && !token) {
            delete hostTokens[host];
            console.log(`[token] Cleared token for ${host}`);
          }
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ status: 'ok', tokens: Object.keys(hostTokens) }));
        } catch (e) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Invalid JSON' }));
        }
      });
      return;
    }
  }

  // Extract target URL from the path (everything after /)
  const targetUrl = req.url.slice(1);
  if (!targetUrl || (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://'))) {
    res.writeHead(400, { 'Content-Type': 'text/plain', 'Access-Control-Allow-Origin': '*' });
    res.end('Usage: http://localhost:' + PORT + '/https://target-url.com/path');
    return;
  }

  const initialParsed = url.parse(targetUrl);

  // Forward headers, replacing host and restoring X-Proxy-* headers
  const headers = { ...req.headers };
  delete headers.host;
  delete headers.origin;
  delete headers.referer;

  // Restore X-Proxy-User-Agent as User-Agent
  if (headers['x-proxy-user-agent']) {
    headers['user-agent'] = headers['x-proxy-user-agent'];
    delete headers['x-proxy-user-agent'];
  }

  // Restore X-Proxy-Referer as Referer
  if (headers['x-proxy-referer']) {
    headers['referer'] = headers['x-proxy-referer'];
    delete headers['x-proxy-referer'];
  }

  // Restore X-Proxy-Cookie as Cookie
  if (headers['x-proxy-cookie']) {
    headers['cookie'] = headers['x-proxy-cookie'];
    delete headers['x-proxy-cookie'];
  }

  // Auto-add Referer for known CDN hosts that require it
  if (!headers['referer']) {
    const host = initialParsed.hostname || '';
    if (host.endsWith('.hamreus.com')) {
      headers['referer'] = 'https://m.manhuagui.com';
    } else if (host.includes('mangacopy') || host.includes('mangafunc') || host.includes('mangafunb')) {
      headers['referer'] = 'https://www.mangacopy.com';
    } else if (host.includes('jmapiproxy') || host.includes('jmapinodeudzn')) {
      headers['referer'] = 'https://www.cdngwc.cc';
    } else if (host.includes('e-hentai') || host.includes('ehgt') || host.includes('.hath.network')) {
      headers['referer'] = 'https://e-hentai.org';
    } else if (host.includes('zrocdn.xyz')) {
      headers['referer'] = 'https://nhentai.to';
    } else if (host.includes('picacomic.com')) {
      headers['referer'] = 'https://picacomic.com';
    } else if (host.includes('hitomi.la') || host.includes('gold-usergeneratedcontent.net')) {
      headers['referer'] = 'https://hitomi.la/';
    } else if (host.includes('zaimanhua.com')) {
      headers['referer'] = 'https://www.zaimanhua.com/';
    } else if (host.includes('jcomic.net')) {
      headers['referer'] = 'https://jcomic.net';
    } else if (host.includes('manhuaren.com') || host.includes('cdndm5.com') || host.includes('dm5.com')) {
      headers['referer'] = 'https://www.manhuaren.com/';
    } else if (host.includes('pstatic.net') || host.includes('webtoons.com')) {
      headers['referer'] = 'https://www.webtoons.com/';
    }
  }

  // Auto-inject access cookie for jcomic image CDN (Cloudflare-protected).
  // The web <img> element cannot forward custom headers, so the browser never
  // sends X-Proxy-Cookie. images.jcomic.net only requires the fixed cookie
  // "jcomic_access=verified_user" (issued by the main site) plus a jcomic.net
  // Referer, so we inject the cookie here when it is missing.
  {
    const host = initialParsed.hostname || '';
    if (host.includes('images.jcomic.net')) {
      const accessCookie = 'jcomic_access=verified_user';
      if (!headers['cookie']) {
        headers['cookie'] = accessCookie;
      } else if (!headers['cookie'].includes('jcomic_access')) {
        headers['cookie'] = `${accessCookie}; ${headers['cookie']}`;
      }
    }
  }

  // Remove other X-Proxy-* headers
  for (const key of Object.keys(headers)) {
    if (key.startsWith('x-proxy-')) {
      delete headers[key];
    }
  }

  // Auto-inject stored auth tokens for matching hosts
  const targetHost = (initialParsed.hostname || '');
  for (const [pattern, info] of Object.entries(hostTokens)) {
    if (targetHost.includes(pattern)) {
      headers[info.header.toLowerCase()] = info.token;
      break;
    }
  }

  // Make request with redirect following
  function doRequest(targetUrl, headers, maxRedirects) {
    if (maxRedirects <= 0) {
      res.writeHead(502, { 'Content-Type': 'text/plain', 'Access-Control-Allow-Origin': '*' });
      res.end('Too many redirects');
      return;
    }

    const parsed = url.parse(targetUrl);
    const client = parsed.protocol === 'https:' ? https : http;
    headers.host = parsed.host;

    // Route matching hosts through curl-impersonate (opt-in, per-host).
    if (shouldImpersonate(parsed.hostname)) {
      doImpersonatedRequest(targetUrl, headers, res, req);
      return;
    }

    // Bypass upstream proxy for hosts that don't need it
    // v4api.zaimanhua.com can be accessed directly; images.zaimanhua.com still needs proxy
    const hostname = parsed.hostname || '';
    const bypassProxy = hostname === 'v4api.zaimanhua.com' || hostname === 'www.zaimanhua.com';
    const effectiveAgent = bypassProxy ? undefined : (proxyAgent || undefined);

    const proxyReq = client.request(
      {
        hostname: parsed.hostname,
        port: parsed.port,
        path: parsed.path,
        method: req.method,
        headers: headers,
        agent: effectiveAgent,
        timeout: 30000, // 30s timeout for upstream connection
      },
      (proxyRes) => {
        // Follow redirects server-side (301, 302, 303, 307, 308)
        if ([301, 302, 303, 307, 308].includes(proxyRes.statusCode) && proxyRes.headers.location) {
          let redirectUrl = proxyRes.headers.location;
          // Handle relative redirects
          if (redirectUrl.startsWith('/')) {
            redirectUrl = `${parsed.protocol}//${parsed.host}${redirectUrl}`;
          }
          // Consume the response body to free the socket
          proxyRes.resume();
          doRequest(redirectUrl, headers, maxRedirects - 1);
          return;
        }

        // Add CORS headers to response
        const responseHeaders = { ...proxyRes.headers };
        responseHeaders['access-control-allow-origin'] = '*';
        responseHeaders['access-control-allow-methods'] = 'GET, POST, PUT, DELETE, OPTIONS';
        responseHeaders['access-control-allow-headers'] = '*';
        responseHeaders['access-control-expose-headers'] = '*';
        // Remove any Location header to prevent browser from following redirects
        delete responseHeaders['location'];

        res.writeHead(proxyRes.statusCode, responseHeaders);
        proxyRes.pipe(res);
      }
    );

    proxyReq.on('error', (err) => {
      console.error('Proxy error:', err.message, '→', targetUrl);
      if (!res.headersSent) {
        res.writeHead(502, {
          'Content-Type': 'text/plain',
          'Access-Control-Allow-Origin': '*',
        });
        res.end('Proxy error: ' + err.message);
      }
    });

    proxyReq.on('timeout', () => {
      console.error('Proxy timeout (30s):', targetUrl);
      proxyReq.destroy();
      if (!res.headersSent) {
        res.writeHead(504, {
          'Content-Type': 'text/plain',
          'Access-Control-Allow-Origin': '*',
        });
        res.end('Proxy timeout: upstream did not respond within 30s');
      }
    });

    req.pipe(proxyReq);
  }

  // Perform the request via curl-impersonate to spoof a real browser TLS/JA3
  // fingerprint (needed for Cloudflare-fingerprint-protected hosts).
  // `headers` is already the final header set (X-Proxy-* already restored).
  function doImpersonatedRequest(targetUrl, headers, res, req) {
    const args = ['-s', '--compressed', '-L', '--max-redirs', '5', '-i'];

    // Only append headers curl-impersonate does not manage itself. Notably we
    // keep Referer and Cookie (needed for CF/cf_clearance) but let the wrapper
    // own User-Agent / Accept / Sec-* so the fingerprint stays consistent.
    for (const [key, value] of Object.entries(headers)) {
      const k = key.toLowerCase();
      if (IMPERSONATE_MANAGED_HEADERS.has(k)) continue;
      if (value === undefined || value === null) continue;
      args.push('-H', `${key}: ${value}`);
    }

    const method = (req.method || 'GET').toUpperCase();
    const sendsBody = method !== 'GET' && method !== 'HEAD';
    if (method === 'HEAD') {
      args.push('-I');
    } else if (method !== 'GET') {
      args.push('-X', method);
    }
    if (sendsBody) {
      // Read request body from stdin.
      args.push('--data-binary', '@-');
    }

    args.push(targetUrl);

    const child = spawn(IMPERSONATE_BIN, args);

    const chunks = [];
    let settled = false;

    const killTimer = setTimeout(() => {
      if (!settled) {
        console.error('[impersonate] timeout (30s):', targetUrl);
        try { child.kill('SIGKILL'); } catch (_) {}
      }
    }, 30000);

    child.stdout.on('data', (d) => chunks.push(d));
    child.stderr.on('data', (d) => {
      // curl-impersonate writes progress/errors here; log for debugging.
      process.stderr.write(`[impersonate:${IMPERSONATE_BIN}] ${d}`);
    });

    child.on('error', (err) => {
      settled = true;
      clearTimeout(killTimer);
      console.error('[impersonate] spawn error:', err.message, '→', targetUrl);
      if (!res.headersSent) {
        const hint = err.code === 'ENOENT'
          ? `curl-impersonate binary "${IMPERSONATE_BIN}" not found. Install: brew install lexiforest/tap/curl-impersonate (or set CURL_IMPERSONATE_BIN).`
          : err.message;
        res.writeHead(502, {
          'Content-Type': 'text/plain',
          'Access-Control-Allow-Origin': '*',
        });
        res.end('Impersonate proxy error: ' + hint);
      }
    });

    child.on('close', (code) => {
      if (settled) return;
      settled = true;
      clearTimeout(killTimer);

      const raw = Buffer.concat(chunks);
      if (raw.length === 0) {
        if (!res.headersSent) {
          res.writeHead(502, {
            'Content-Type': 'text/plain',
            'Access-Control-Allow-Origin': '*',
          });
          res.end(`Impersonate proxy: empty response (exit ${code})`);
        }
        return;
      }

      // With -L (follow redirects) and -i, curl emits the headers of EACH
      // response in sequence. Split off successive header blocks and keep the
      // final one (the real response after redirects).
      let offset = 0;
      let statusCode = 200;
      let contentType = 'application/octet-stream';
      const passthroughHeaders = {};

      while (true) {
        const sep = raw.indexOf('\r\n\r\n', offset);
        if (sep === -1) break;
        const headerText = raw.slice(offset, sep).toString('latin1');
        const lines = headerText.split('\r\n');
        const statusLine = lines[0] || '';
        const m = statusLine.match(/^HTTP\/[\d.]+\s+(\d{3})/);
        if (!m) break; // not a header block; stop

        const thisStatus = parseInt(m[1], 10);
        const thisHeaders = {};
        for (let i = 1; i < lines.length; i++) {
          const idx = lines[i].indexOf(':');
          if (idx === -1) continue;
          const hk = lines[i].slice(0, idx).trim().toLowerCase();
          const hv = lines[i].slice(idx + 1).trim();
          thisHeaders[hk] = hv;
        }

        offset = sep + 4;

        // If this is a redirect/interim (1xx/3xx with Location, or curl's
        // "HTTP/1.1 100 Continue" / proxy CONNECT 200), keep scanning for the
        // next header block that begins right after.
        const isRedirect = thisStatus >= 300 && thisStatus < 400 && thisHeaders['location'];
        const isInterim = thisStatus === 100;
        const isConnect = thisStatus === 200 && (statusLine.includes('Connection established') || thisHeaders['proxy-agent']);

        statusCode = thisStatus;
        contentType = thisHeaders['content-type'] || contentType;
        // Preserve a few useful passthrough headers from the final block.
        for (const k of ['content-type', 'content-disposition', 'cache-control', 'etag', 'last-modified']) {
          if (thisHeaders[k]) passthroughHeaders[k] = thisHeaders[k];
        }

        if (isRedirect || isInterim || isConnect) {
          // keep scanning; the next block is the followed response
          continue;
        }
        break; // final response reached; body starts at `offset`
      }

      const body = raw.slice(offset);

      const responseHeaders = {
        ...passthroughHeaders,
        'content-type': contentType,
        'access-control-allow-origin': '*',
        'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'access-control-allow-headers': '*',
        'access-control-expose-headers': '*',
      };

      if (!res.headersSent) {
        res.writeHead(statusCode, responseHeaders);
        res.end(body);
      }
    });

    if (sendsBody) {
      req.pipe(child.stdin);
    } else {
      // No body to send; close stdin so curl doesn't wait.
      try { child.stdin.end(); } catch (_) {}
    }
  }

  doRequest(targetUrl, headers, 5);
});

server.listen(PORT, () => {
  console.log(`CORS proxy running at http://localhost:${PORT}`);
  console.log('');
  console.log('  Proxy requests:  http://localhost:' + PORT + '/https://api.example.com/...');
  console.log('  Get proxy config: GET  http://localhost:' + PORT + '/__proxy_config');
  console.log('  Set proxy config: POST http://localhost:' + PORT + '/__proxy_config');
  console.log('                    Body: {"proxy": "http://127.0.0.1:2222"}');
  console.log('');
  if (currentProxyUrl) {
    console.log(`  Upstream proxy: ${currentProxyUrl}`);
  } else {
    console.log('  Upstream proxy: (none - direct connection)');
  }
});

// Increase max connections to prevent queueing
server.maxConnections = 200;

// Short keep-alive timeout so idle connections are freed quickly for new requests
server.keepAliveTimeout = 5000; // 5s

// Also increase the global agent max sockets for outgoing requests
https.globalAgent.maxSockets = 50;
http.globalAgent.maxSockets = 50;

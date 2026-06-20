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

const PORT = 9090;

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

    const proxyReq = client.request(
      {
        hostname: parsed.hostname,
        port: parsed.port,
        path: parsed.path,
        method: req.method,
        headers: headers,
        agent: proxyAgent || undefined,
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

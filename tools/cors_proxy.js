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

const server = http.createServer((req, res) => {
  // Handle preflight
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': '*',
      'Access-Control-Max-Age': '86400',
    });
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
    }
  }

  // Remove other X-Proxy-* headers
  for (const key of Object.keys(headers)) {
    if (key.startsWith('x-proxy-')) {
      delete headers[key];
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
      res.writeHead(502, {
        'Content-Type': 'text/plain',
        'Access-Control-Allow-Origin': '*',
      });
      res.end('Proxy error: ' + err.message);
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

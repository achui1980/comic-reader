// Simple CORS proxy for Flutter web development.
// Run with: node cors_proxy.js
//
// This proxies all requests and adds CORS headers so the Flutter web app
// can make cross-origin requests to manga source APIs.
//
// Supports X-Proxy-* headers: the Flutter app moves browser-forbidden headers
// (User-Agent, Referer) to X-Proxy-User-Agent / X-Proxy-Referer, and this
// proxy restores them before forwarding.

const http = require('http');
const https = require('https');
const url = require('url');

const PORT = 9090;

// Upstream proxy support: reads HTTPS_PROXY / HTTP_PROXY from env
const UPSTREAM_PROXY = process.env.HTTPS_PROXY || process.env.HTTP_PROXY || process.env.https_proxy || process.env.http_proxy;

let proxyAgent = null;
if (UPSTREAM_PROXY) {
  try {
    // Use Node's built-in undici ProxyAgent if available (Node 18+)
    // Otherwise fall back to https-proxy-agent if installed
    const { HttpsProxyAgent } = require('https-proxy-agent');
    proxyAgent = new HttpsProxyAgent(UPSTREAM_PROXY);
    console.log(`Using upstream proxy: ${UPSTREAM_PROXY}`);
  } catch (e) {
    console.log(`Warning: HTTPS_PROXY set to ${UPSTREAM_PROXY} but https-proxy-agent not installed.`);
    console.log('Run: npm install https-proxy-agent');
    console.log('Proceeding without upstream proxy...');
  }
}

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

  // Extract target URL from the path (everything after /)
  const targetUrl = req.url.slice(1);
  if (!targetUrl || (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://'))) {
    res.writeHead(400, { 'Content-Type': 'text/plain' });
    res.end('Usage: http://localhost:' + PORT + '/https://target-url.com/path');
    return;
  }

  const parsed = url.parse(targetUrl);
  const client = parsed.protocol === 'https:' ? https : http;

  // Forward headers, replacing host and restoring X-Proxy-* headers
  const headers = { ...req.headers };
  delete headers.host;
  delete headers.origin;
  delete headers.referer;
  headers.host = parsed.host;

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

  // Auto-add Referer for known CDN hosts that require it
  if (!headers['referer']) {
    const host = parsed.hostname || '';
    if (host.endsWith('.hamreus.com')) {
      headers['referer'] = 'https://m.manhuagui.com';
    } else if (host.includes('mangacopy') || host.includes('mangafunc') || host.includes('mangafunb')) {
      headers['referer'] = 'https://www.mangacopy.com';
    }
  }

  // Remove other X-Proxy-* headers
  for (const key of Object.keys(headers)) {
    if (key.startsWith('x-proxy-')) {
      delete headers[key];
    }
  }

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
      // Add CORS headers to response
      const responseHeaders = { ...proxyRes.headers };
      responseHeaders['access-control-allow-origin'] = '*';
      responseHeaders['access-control-allow-methods'] = 'GET, POST, PUT, DELETE, OPTIONS';
      responseHeaders['access-control-allow-headers'] = '*';
      responseHeaders['access-control-expose-headers'] = '*';

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
});

server.listen(PORT, () => {
  console.log(`CORS proxy running at http://localhost:${PORT}`);
  console.log('Usage: http://localhost:' + PORT + '/https://api.mangacopy.com/...');
  console.log('');
  console.log('Supports X-Proxy-User-Agent / X-Proxy-Referer header restoration');
  console.log('Run your Flutter web app with: flutter run -d chrome');
});

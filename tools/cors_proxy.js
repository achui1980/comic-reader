// Simple CORS proxy for Flutter web development.
// Run with: node cors_proxy.js
//
// This proxies all requests and adds CORS headers so the Flutter web app
// can make cross-origin requests to manga source APIs.

const http = require('http');
const https = require('https');
const url = require('url');

const PORT = 9090;

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

  // Forward headers, replacing host
  const headers = { ...req.headers };
  delete headers.host;
  delete headers.origin;
  delete headers.referer;
  headers.host = parsed.host;

  const proxyReq = client.request(
    {
      hostname: parsed.hostname,
      port: parsed.port,
      path: parsed.path,
      method: req.method,
      headers: headers,
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
  console.log('Run your Flutter web app with: flutter run -d chrome');
});

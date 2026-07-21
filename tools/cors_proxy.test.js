const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { spawn } = require('node:child_process');
const path = require('node:path');

const proxyScript = path.join(__dirname, 'cors_proxy.js');
let serverProcess;

function request(method, targetPath, headers = {}, body = '') {
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        hostname: '127.0.0.1',
        port: 9090,
        path: targetPath,
        method,
        headers,
      },
      (res) => {
        let data = '';
        res.setEncoding('utf8');
        res.on('data', (chunk) => {
          data += chunk;
        });
        res.on('end', () => {
          resolve({ statusCode: res.statusCode, headers: res.headers, body: data });
        });
      },
    );
    req.on('error', reject);
    if (body) {
      req.write(body);
    }
    req.end();
  });
}

async function waitForServer() {
  for (let i = 0; i < 20; i += 1) {
    try {
      const response = await request('GET', '/__proxy_config');
      if (response.statusCode === 200) {
        return;
      }
    } catch (_) {
      // Retry until the child process is ready.
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('CORS proxy did not start in time');
}

test.before(async () => {
  // Strip any inherited HTTP(S)_PROXY env vars so the proxy under test
  // always makes direct upstream connections during the test run,
  // regardless of the host environment's proxy configuration.
  const env = { ...process.env };
  delete env.HTTPS_PROXY;
  delete env.HTTP_PROXY;
  delete env.https_proxy;
  delete env.http_proxy;

  serverProcess = spawn(process.execPath, [proxyScript], {
    cwd: __dirname,
    stdio: 'ignore',
    env,
  });
  await waitForServer();
});

test.after(() => {
  if (serverProcess) {
    serverProcess.kill();
  }
});

test('preflight for proxy config explicitly allows content-type header', async () => {
  const response = await request('OPTIONS', '/__proxy_config', {
    Origin: 'http://localhost:1234',
    'Access-Control-Request-Method': 'POST',
    'Access-Control-Request-Headers': 'content-type',
  });

  assert.equal(response.statusCode, 204);
  assert.equal(response.headers['access-control-allow-origin'], 'http://localhost:1234');
  assert.match(response.headers['access-control-allow-headers'] || '', /content-type/i);
});

test('truncated upstream response is reported as an error, not forwarded as a 200', async () => {
  // Simulate a flaky upstream CDN: declares Content-Length: 10000 but the
  // connection is destroyed after only a few bytes. A naive `pipe()` would
  // let this through to the browser as a "successful" 200 with a truncated
  // body (e.g. a JPEG that fails to decode). The proxy must detect the
  // incomplete transfer and respond with an error instead.
  const upstream = http.createServer((req, res) => {
    res.writeHead(200, { 'Content-Type': 'image/jpeg', 'Content-Length': '10000' });
    res.write(Buffer.from('not a complete jpeg'));
    // Close the connection gracefully (FIN, not RST) without calling
    // res.end(), simulating a mid-transfer reset from the upstream CDN.
    // A hard `socket.destroy()` triggers Node's request-level 'error'
    // event ("socket hang up"), which the proxy already handles; ending
    // the socket instead exercises the response-stream completeness
    // check (proxyRes 'close' without 'end'), which is the scenario a
    // naive `pipe()` would silently forward as a "successful" 200.
    res.socket.end();
  });

  await new Promise((resolve) => upstream.listen(0, '127.0.0.1', resolve));
  const upstreamPort = upstream.address().port;

  try {
    const response = await request('GET', `/http://127.0.0.1:${upstreamPort}/broken.jpg`);
    assert.equal(response.statusCode, 502);
    assert.match(
      response.body,
      /truncated|closed before response completed|socket hang up|upstream response error/i,
    );
  } finally {
    upstream.close();
  }
});

test('complete upstream response with matching Content-Length is forwarded as-is', async () => {
  const payload = 'a'.repeat(500);
  const upstream = http.createServer((req, res) => {
    res.writeHead(200, {
      'Content-Type': 'text/plain',
      'Content-Length': String(Buffer.byteLength(payload)),
    });
    res.end(payload);
  });

  await new Promise((resolve) => upstream.listen(0, '127.0.0.1', resolve));
  const upstreamPort = upstream.address().port;

  try {
    const response = await request('GET', `/http://127.0.0.1:${upstreamPort}/ok.txt`);
    assert.equal(response.statusCode, 200);
    assert.equal(response.body, payload);
  } finally {
    upstream.close();
  }
});

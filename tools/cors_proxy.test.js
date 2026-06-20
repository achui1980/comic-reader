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
  serverProcess = spawn(process.execPath, [proxyScript], {
    cwd: __dirname,
    stdio: 'ignore',
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

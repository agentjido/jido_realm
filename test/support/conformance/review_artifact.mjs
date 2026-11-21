import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const [executable, artifact] = process.argv.slice(2);
const profile = await mkdtemp(join(tmpdir(), 'realm-browser-'));
const browser = spawn(executable, [
  '--headless', '--no-first-run', '--disable-background-networking',
  '--remote-debugging-port=0', `--user-data-dir=${profile}`, 'about:blank'
]);
const stopped = once(browser, 'close');
stopped.catch(() => {});
const deadline = setTimeout(() => browser.kill('SIGKILL'), 12_000);
let socket;

try {
  const unauthorized = new URL(artifact);
  unauthorized.pathname = '/unknown/index.html';
  assert.equal((await fetch(unauthorized)).status, 404);
  const outside = new URL('private.txt', artifact);
  assert.equal((await fetch(outside)).status, 404);

  const address = await new Promise((resolve, reject) => {
    let output = '';
    browser.stderr.on('data', (chunk) => {
      output += chunk;
      const match = output.match(/DevTools listening on ws:\/\/([^/]+)\//);
      if (match) resolve(match[1]);
    });
    browser.once('error', reject);
    browser.once('close', () => reject(new Error(output)));
  });

  const targets = await (await fetch(`http://${address}/json/list`)).json();
  socket = new WebSocket(targets.find((target) => target.type === 'page').webSocketDebuggerUrl);
  await once(socket, 'open');

  let next = 0;
  function call(method, params = {}) {
    const id = ++next;
    return new Promise((resolve, reject) => {
      const onClose = () => reject(new Error(`Browser closed during ${method}`));
      const reply = ({ data }) => {
        const message = JSON.parse(data);
        if (message.id !== id) return;
        socket.removeEventListener('message', reply);
        socket.removeEventListener('close', onClose);
        if (message.error) reject(new Error(message.error.message));
        else resolve(message.result);
      };
      socket.addEventListener('message', reply);
      socket.addEventListener('close', onClose, { once: true });
      socket.send(JSON.stringify({ id, method, params }));
    });
  }

  async function evaluate(expression) {
    const { result, exceptionDetails } = await call('Runtime.evaluate', { expression, returnByValue: true });
    assert.equal(exceptionDetails, undefined);
    return result.value;
  }

  assert.equal((await call('Page.navigate', { url: artifact })).errorText, undefined);
  for (let attempt = 0; attempt < 100; attempt++) {
    if (await evaluate('document.body?.dataset.origin !== undefined')) break;
    await delay(25);
  }
  assert.equal(await evaluate('document.body.dataset.origin'), 'null');
  assert.equal(await evaluate(`(() => {
    try { return document.cookie; } catch (error) { return error.name; }
  })()`), 'SecurityError');
  assert.equal(await evaluate('getComputedStyle(document.querySelector("#total")).color'), 'rgb(12, 34, 56)');
  assert.equal(await evaluate('document.querySelector("#total").textContent'), 'Hidden');
  await evaluate('document.querySelector("#show").click()');
  assert.equal(await evaluate('document.querySelector("#total").textContent'), 'Total: 42');
  console.log('artifact loaded, styled, and interactive');
} finally {
  socket?.close();
  browser.kill();
  await stopped.catch(() => {});
  clearTimeout(deadline);
  await rm(profile, { recursive: true, force: true });
}

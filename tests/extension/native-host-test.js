import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import net from "node:net";
import crypto from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
const binary = process.env.ISLAND_NATIVE_HOST;
assert.ok(binary, "ISLAND_NATIVE_HOST is required");
const origin = "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/";
const writeLength = (buffer, value) => os.endianness() === "LE" ? buffer.writeUInt32LE(value) : buffer.writeUInt32BE(value);
const readLength = buffer => os.endianness() === "LE" ? buffer.readUInt32LE() : buffer.readUInt32BE();
const rawFrame = json => { const header = Buffer.alloc(4); writeLength(header, json.length); return Buffer.concat([header, json]); };
const frame = value => rawFrame(Buffer.from(JSON.stringify(value)));
async function until(predicate) {
  const deadline = Date.now() + 2500;
  while (!predicate()) { if (Date.now() >= deadline) throw Error("transport deadline"); await new Promise(resolve => setTimeout(resolve, 10)); }
}
async function fixture(t, { handshake = true, caller = origin, listen = true, configMode = 0o600 } = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "island-native-test-"));
  const runtime = path.join(directory, "runtime"), config = path.join(directory, "config");
  fs.mkdirSync(runtime, { mode: 0o700 }); fs.mkdirSync(config); fs.mkdirSync(path.join(config, "nookisle"));
  const address = "unix:path=isolated-native-test", hash = crypto.createHash("sha256").update(address).digest("hex").slice(0, 16);
  const privateDir = path.join(runtime, "nookisle-" + hash); fs.mkdirSync(privateDir, { mode: 0o700 });
  const socketPath = path.join(privateDir, "browser.sock");
  fs.writeFileSync(path.join(config, "nookisle/native-host.json"), JSON.stringify({ allowedOrigin: origin }), { mode: configMode });
  fs.writeFileSync(path.join(privateDir, "browser.json"), JSON.stringify({ protocolVersion: 1, socket: socketPath, secret: "a-private-fixture-secret" }), { mode: 0o600 });
  const received = [], frames = []; let socket = null, socketInput = "", nativeInput = Buffer.alloc(0), stderr = "";
  const server = net.createServer(peer => {
    socket = peer; peer.on("error", () => {});
    peer.on("data", data => {
      socketInput += data;
      while (socketInput.includes("\n")) {
        const end = socketInput.indexOf("\n"), message = JSON.parse(socketInput.slice(0, end)); socketInput = socketInput.slice(end + 1); received.push(message);
        if (message.type === "bridgeAuth" && handshake) peer.write(JSON.stringify({ protocolVersion: 1, type: "bridgeHello", bridgeSession: "fixture-session", busEpoch: "fixture-bus" }) + "\n");
      }
    });
  });
  if (listen) await new Promise((resolve, reject) => { server.once("error", reject); server.listen(socketPath, resolve); });
  const child = spawn(binary, [caller], { env: { ...process.env, XDG_RUNTIME_DIR: runtime, XDG_CONFIG_HOME: config, DBUS_SESSION_BUS_ADDRESS: address }, stdio: ["pipe", "pipe", "pipe"] });
  const exited = new Promise(resolve => child.once("exit", (code, signal) => resolve({ code, signal })));
  child.stdin.on("error", () => {});
  child.stderr.on("data", data => { stderr += data; });
  child.stdout.on("data", data => {
    nativeInput = Buffer.concat([nativeInput, data]);
    while (nativeInput.length >= 4 && nativeInput.length >= readLength(nativeInput) + 4) {
      const length = readLength(nativeInput); frames.push(JSON.parse(nativeInput.subarray(4, length + 4))); nativeInput = nativeInput.subarray(length + 4);
    }
  });
  t.after(async () => {
    if (child.exitCode === null && child.signalCode === null) child.kill("SIGTERM");
    await exited; socket?.destroy();
    if (server.listening) await new Promise(resolve => server.close(resolve));
    fs.rmSync(directory, { recursive: true });
    assert.equal(stderr, "", "native host must not log protocol or metadata");
  });
  return { child, exited, received, frames, get socket() { return socket; }, directory };
}
test("native framing authenticates, handles split input, and exits on clean Chrome EOF", async t => {
  const f = await fixture(t); await until(() => f.frames.length === 1);
  assert.equal(f.received[0].type, "bridgeAuth"); assert.equal(f.received[0].secret, "a-private-fixture-secret");
  const message = { protocolVersion: 1, type: "browserGone", bridgeSession: "fixture-session", tabId: 3, documentId: "doc" }, bytes = frame(message);
  f.child.stdin.write(bytes.subarray(0, 2)); f.child.stdin.write(bytes.subarray(2, 7)); f.child.stdin.write(bytes.subarray(7));
  await until(() => f.received.length === 2); assert.deepEqual(f.received[1], message);
  f.socket.write('{"protocolVersion":1,"type":"browserCommand","requestId":"test"}\n');
  await until(() => f.frames.length === 2); assert.equal(f.frames[1].requestId, "test");
  f.child.stdin.end(); assert.equal((await f.exited).code, 0);
});
test("oversized Chrome frame is rejected before allocating its advertised payload", async t => {
  const f = await fixture(t); await until(() => f.frames.length === 1);
  const header = Buffer.alloc(4); writeLength(header, 65537); f.child.stdin.write(header);
  assert.equal((await f.exited).code, 1); assert.equal(f.received.length, 1);
});
test("partial native message at EOF is rejected without forwarding", async t => {
  const f = await fixture(t); await until(() => f.frames.length === 1);
  f.child.stdin.end(frame({ type: "unfinished" }).subarray(0, 7)); assert.equal((await f.exited).code, 1);
  assert.equal(f.received.length, 1);
});
test("socket loss terminates the Chrome-owned host; it does not spawn or reconnect a helper", async t => {
  const f = await fixture(t); await until(() => f.frames.length === 1); f.socket.destroy();
  assert.equal((await f.exited).code, 1);
});
test("wrong extension origin is rejected before socket authentication", async t => {
  const f = await fixture(t, { caller: "chrome-extension://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/" });
  assert.equal((await f.exited).code, 1); assert.equal(f.received.length, 0);
});
test("nonprivate origin config is rejected", async t => {
  const f = await fixture(t, { configMode: 0o644 });
  assert.equal((await f.exited).code, 1); assert.equal(f.received.length, 0);
});
test("missing helper socket exits rather than waiting forever on synchronous connect failure", async t => {
  const f = await fixture(t, { listen: false }); assert.equal((await f.exited).code, 1);
});
test("socket input larger than one bounded frame is rejected", async t => {
  const f = await fixture(t); await until(() => f.frames.length === 1);
  f.socket.write("x".repeat(65536)); assert.equal((await f.exited).code, 1);
});
test("native parser rejects malformed, nonobject, trailing, invalid UTF-8 and deeply nested input", async t => {
  const cases = [Buffer.from("[]"), Buffer.from("{invalid}"), Buffer.from('{}{}'), Buffer.from("{'a':1}"),
    Buffer.from('{"a":1.}'), Buffer.from('{"value":NaN}'),
    Buffer.from('{"value":Infinity}'), Buffer.from('{"value":1e999}'), Buffer.from('{"value":' + '['.repeat(40) + '0' + ']'.repeat(40) + '}'),
    Buffer.from('{"nested":[{"value":NaN}]}'), Buffer.from('{"nested":{"values":[Infinity]}}'),
    Buffer.concat([Buffer.from('{"nested":[{"value":"'), Buffer.from([0xc0, 0xaf]), Buffer.from('"}]}')]),
    Buffer.concat([Buffer.from('{"value":"'), Buffer.from([0xed, 0xa0, 0x80]), Buffer.from('"}')]),
    Buffer.concat([Buffer.from('{"value":"'), Buffer.from([0xf4, 0x90, 0x80, 0x80]), Buffer.from('"}')]),
    Buffer.concat([Buffer.from('{"value":"'), Buffer.from([0xf8, 0x88, 0x80, 0x80, 0x80]), Buffer.from('"}')])];
  for (let i = 0; i < cases.length; ++i) for (const direction of ["chrome", "socket"]) await t.test(`invalid ${direction} frame ${i}`, { timeout: 1500 }, async subtest => {
    const f = await fixture(subtest); await until(() => f.frames.length === 1);
    if (direction === "chrome") f.child.stdin.write(rawFrame(cases[i]));
    else f.socket.write(Buffer.concat([cases[i], Buffer.from("\n")]));
    assert.equal((await f.exited).code, 1);
    assert.equal(f.received.length, 1);
    assert.equal(f.frames.length, 1);
  });
});
test("split UTF-8 input round-trips without changing string data or coalesced message order", async t => {
  const f = await fixture(t); await until(() => f.frames.length === 1);
  const message = { type: "fixture", value: "Âm nhạc 🎵", nested: { supported: true } }, bytes = frame(message);
  for (const byte of bytes) f.child.stdin.write(Buffer.from([byte]));
  f.child.stdin.write(Buffer.concat([frame({ sequence: 1 }), frame({ sequence: 2 })]));
  await until(() => f.received.length === 4);
  assert.deepEqual(f.received[1], message); assert.equal(f.received[2].sequence, 1); assert.equal(f.received[3].sequence, 2);
});
test("unauthenticated startup deadline closes a silent helper", async t => {
  const f = await fixture(t, { handshake: false }); const started = performance.now();
  assert.equal((await f.exited).code, 1);
  assert.ok(performance.now() - started >= 2500); assert.ok(performance.now() - started < 4500);
});
test("socket output backpressure is bounded instead of accumulating Chrome messages", async t => {
  const f = await fixture(t); await until(() => f.frames.length === 1); f.socket.pause();
  const message = frame({ type: "fixture", data: "x".repeat(8000) });
  f.child.stdin.write(Buffer.concat(Array.from({ length: 256 }, () => message)));
  assert.equal((await f.exited).code, 1);
});
test("Chrome output backpressure is bounded instead of accumulating socket messages", async t => {
  const f = await fixture(t); await until(() => f.frames.length === 1); f.child.stdout.pause();
  const message = JSON.stringify({ type: "fixture", data: "x".repeat(8000) }) + "\n";
  f.socket.write(message.repeat(256)); assert.equal((await f.exited).code, 1);
});
test("manifest generation stages exact-origin registration without overwriting existing files", async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "island-manifest-test-"));
  t.after(() => fs.rmSync(directory, { recursive: true }));
  const args = [new URL("../../bridge/write-native-manifests.py", import.meta.url).pathname, "--extension-id", "a".repeat(32), "--binary", binary, "--output-dir", path.join(directory, "stage")];
  assert.equal(spawnSync("python3", args).status, 0);
  const manifest = JSON.parse(fs.readFileSync(path.join(directory, "stage/io.github.bavanchun.nookisle.json")));
  assert.deepEqual(manifest.allowed_origins, [origin]); assert.equal(manifest.path, fs.realpathSync(binary));
  assert.equal(fs.statSync(path.join(directory, "stage/native-host.json")).mode & 0o777, 0o600);
  assert.notEqual(spawnSync("python3", args).status, 0);
});

#!/usr/bin/env python3
"""A local stand-in for LRCLIB's /api/get, for tst-lyrics.qml.

Binds 127.0.0.1 on a free port and writes it as `var port = N` to
<build>/lyrics-fixture/port.js, which the test imports. Each /api/<route>
request is counted (and its query logged to requests.log) before it is
answered; GET /__requests returns the count and is not itself counted, so the
test can prove that a cache hit or a disabled source sent nothing. It never
touches the real network.
"""
import http.server
import json
import pathlib
import sys
import threading
import time

SYNCED = "\n".join([
    "[ar:Fixture Artist]",
    "[ti:Fixture Song]",
    "[offset:+500]",
    "[00:01.00]First line",
    "[00:03.50][00:09.00]Chorus line",
    "[00:05.25]",
    "[00:07.000]Third line",
    "[00:11.5]Last line",
])

BODIES = {
    "/api/get": {"id": 1, "trackName": "Fixture Song", "artistName": "Fixture Artist",
                 "albumName": "Fixture Album", "duration": 200.0, "instrumental": False,
                 "plainLyrics": "First line\nChorus line", "syncedLyrics": SYNCED},
    "/api/instrumental": {"id": 2, "trackName": "Interlude", "instrumental": True,
                          "plainLyrics": None, "syncedLyrics": None},
    "/api/plain": {"id": 3, "trackName": "Untimed", "instrumental": False,
                   "plainLyrics": "Words without timing", "syncedLyrics": None},
}


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    count = 0
    lock = threading.Lock()
    log_path = None

    def log_message(self, *args):
        pass

    def send_text(self, status, text, content_type="text/plain"):
        data = text.encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path, _, query = self.path.partition("?")
        if path == "/__requests":
            with Handler.lock:
                count = Handler.count
            self.send_text(200, str(count))
            return
        if not path.startswith("/api/"):
            self.send_text(404, "unknown route")
            return
        with Handler.lock:
            Handler.count += 1
            with open(Handler.log_path, "a") as log:
                log.write(f"{path}?{query}\n")
        try:
            self.answer(path)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def answer(self, path):
        if path in BODIES:
            self.send_text(200, json.dumps(BODIES[path]), "application/json")
        elif path == "/api/missing":
            self.send_text(404, json.dumps({"code": 404, "name": "TrackNotFound"}), "application/json")
        elif path == "/api/garbage":
            self.send_text(200, "not json")
        elif path == "/api/big-declared":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", "300000")
            self.end_headers()
            self.wfile.write(b"{" + b" " * 299998 + b"}")
        elif path == "/api/big-chunked":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            chunk = b" " * 16384
            for _ in range(300 * 1024 // len(chunk)):
                self.wfile.write(b"%x\r\n%s\r\n" % (len(chunk), chunk))
                self.wfile.flush()
            self.wfile.write(b"0\r\n\r\n")
        elif path == "/api/big-multibyte":
            # 100,000 three-byte characters: under the cap in UTF-16 units,
            # about 300 KB on the wire, and no declared length.
            body = json.dumps({"syncedLyrics": "[00:01.00]" + "\u30a2" * 100000},
                              ensure_ascii=False).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            for start in range(0, len(body), 16384):
                chunk = body[start:start + 16384]
                self.wfile.write(b"%x\r\n%s\r\n" % (len(chunk), chunk))
            self.wfile.write(b"0\r\n\r\n")
            self.wfile.flush()
        elif path == "/api/slow":
            time.sleep(30)
            self.send_text(200, json.dumps(BODIES["/api/get"]), "application/json")
        else:
            self.send_text(404, "unknown route")


def main():
    directory = pathlib.Path(sys.argv[1])
    directory.mkdir(parents=True, exist_ok=True)
    Handler.log_path = directory / "requests.log"
    Handler.log_path.write_text("")
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    staging = directory / "port.js.tmp"
    staging.write_text(f"var port = {server.server_address[1]}\n")
    staging.replace(directory / "port.js")
    server.serve_forever()


if __name__ == "__main__":
    main()

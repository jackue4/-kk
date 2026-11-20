"""把导出的网页版目录用 HTTP 发出去（只听本机 127.0.0.1，配合隧道把它映射到公网）。
比 `python -m http.server` 多做一件事：.wasm / .pck / .js / .html 按 gzip 压缩后再发（压一次、缓存在内存里），
手机经隧道下载时从约 50 MB 降到约 20 MB。
用法：python serve_web.py <导出目录> [端口，默认 8766]
"""
import gzip
import os
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.abspath(sys.argv[1])
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8766
PACK = (".wasm", ".pck", ".js", ".html")
_cache = {}


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)

    def end_headers(self):
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def do_GET(self):
        path = self.translate_path(self.path.split("?")[0])
        if os.path.isdir(path):
            path = os.path.join(path, "index.html")
        if not (path.endswith(PACK) and os.path.isfile(path) and "gzip" in self.headers.get("Accept-Encoding", "")):
            return super().do_GET()
        key = (path, os.path.getmtime(path))
        if key not in _cache:
            with open(path, "rb") as f:
                _cache[key] = gzip.compress(f.read(), 6)
        body = _cache[key]
        self.send_response(200)
        self.send_header("Content-Type", self.guess_type(path))
        self.send_header("Content-Encoding", "gzip")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))


if __name__ == "__main__":
    print("serving", ROOT, "on http://127.0.0.1:%d" % PORT, flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()

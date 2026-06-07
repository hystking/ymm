#!/usr/bin/env python3
"""Local preview server for the ymm player — no AWS, no deploy.

Serves the static site from ./site, but transparently maps requests for
/music/* onto the repo's ./music directory (where your mp3s actually live).
On S3/CloudFront the site assets and the music share one bucket root; this
recreates that layout locally so the player behaves identically.

HTTP Range requests are supported, so the seek bar works while a track is
still streaming.

Usage (normally invoked via scripts/serve.sh):
    serve.py <site_dir> <music_dir> [port]
"""
import os
import sys
import urllib.parse
from functools import partial
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

MUSIC_PREFIX = "/music/"


class Handler(SimpleHTTPRequestHandler):
    """Serves site_dir, but routes /music/* to music_dir, with Range support."""

    music_dir = None  # set by the partial() below

    def translate_path(self, path):
        decoded = urllib.parse.unquote(urllib.parse.urlparse(path).path)
        if decoded == "/music" or decoded.startswith(MUSIC_PREFIX):
            rel = decoded[len(MUSIC_PREFIX):] if decoded.startswith(MUSIC_PREFIX) else ""
            # Normalise and refuse to climb out of the music directory.
            rel = os.path.normpath(rel).lstrip("/\\")
            if rel == ".." or rel.startswith(".." + os.sep):
                rel = ""
            return os.path.join(self.music_dir, rel)
        return super().translate_path(path)

    def _cache_headers(self, path):
        # playlist.json changes constantly during editing; never cache it.
        if os.path.basename(path) == "playlist.json":
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")

    def do_GET(self):
        path = self.translate_path(self.path)
        if os.path.isdir(path):
            return super().do_GET()  # directory listing / index.html lookup
        if not os.path.isfile(path):
            self.send_error(HTTPStatus.NOT_FOUND, "File not found")
            return

        size = os.path.getsize(path)
        ctype = self.guess_type(path)
        range_header = self.headers.get("Range", "")

        try:
            with open(path, "rb") as f:
                if range_header.startswith("bytes="):
                    start, end = self._parse_range(range_header, size)
                    if start is None:
                        self.send_response(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
                        self.send_header("Content-Range", f"bytes */{size}")
                        self.end_headers()
                        return
                    length = end - start + 1
                    self.send_response(HTTPStatus.PARTIAL_CONTENT)
                    self.send_header("Content-Type", ctype)
                    self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
                    self.send_header("Accept-Ranges", "bytes")
                    self.send_header("Content-Length", str(length))
                    self._cache_headers(path)
                    self.end_headers()
                    f.seek(start)
                    self._copy_n(f, length)
                else:
                    self.send_response(HTTPStatus.OK)
                    self.send_header("Content-Type", ctype)
                    self.send_header("Content-Length", str(size))
                    self.send_header("Accept-Ranges", "bytes")
                    self._cache_headers(path)
                    self.end_headers()
                    self._copy_n(f, size)
        except (BrokenPipeError, ConnectionResetError):
            # Browser seeked/closed mid-stream — perfectly normal, stay quiet.
            pass

    @staticmethod
    def _parse_range(header, size):
        """Return (start, end) inclusive for a single 'bytes=' range, or (None, None)."""
        try:
            spec = header[len("bytes="):].split(",", 1)[0].strip()
            start_s, end_s = spec.split("-", 1)
            if start_s == "":  # suffix range: bytes=-500 (last N bytes)
                length = int(end_s)
                if length <= 0:
                    return None, None
                start = max(0, size - length)
                end = size - 1
            else:
                start = int(start_s)
                end = int(end_s) if end_s else size - 1
        except ValueError:
            return None, None
        if start >= size or start < 0:
            return None, None
        return start, min(end, size - 1)

    def _copy_n(self, f, length, bufsize=64 * 1024):
        remaining = length
        while remaining > 0:
            chunk = f.read(min(bufsize, remaining))
            if not chunk:
                break
            self.wfile.write(chunk)
            remaining -= len(chunk)


def main():
    if len(sys.argv) < 3:
        print("usage: serve.py <site_dir> <music_dir> [port]", file=sys.stderr)
        sys.exit(2)
    site_dir = sys.argv[1]
    music_dir = sys.argv[2]
    port = int(sys.argv[3]) if len(sys.argv) > 3 else 8000

    handler = partial(Handler, directory=site_dir)
    # Bake the music dir onto the handler class used by partial.
    Handler.music_dir = music_dir

    with ThreadingHTTPServer(("127.0.0.1", port), handler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nStopped.")


if __name__ == "__main__":
    main()

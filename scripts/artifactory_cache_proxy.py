#!/usr/bin/env python3
"""
Tiny local HTTP->HTTPS bridge so ccache's built-in HTTP remote-storage
backend (which only speaks plain HTTP, see `man ccache`) can use an
Artifactory repo as a shared pre-built object cache.

Every build machine — including a slow, air-gapped-adjacent Windows dev box —
runs one of these alongside its compiler. ccache talks plain HTTP to
127.0.0.1; this process re-issues the request over HTTPS to Artifactory with
the access token attached, so the token never has to appear in the ccache
process environment or its logs.

Usage: artifactory_cache_proxy.py <listen_port> <artifactory_base_url> <repo_key> <bearer_token>
"""
import http.server
import os
import posixpath
import ssl
import sys
import urllib.parse
import urllib.request
import urllib.error


def _build_ssl_context():
    """Python's bundled OpenSSL doesn't read the OS trust store, so on a
    machine behind a TLS-inspecting corporate proxy (common on enterprise
    laptops) it won't trust a middlebox-issued cert even though curl/jf CLI
    do via the system keychain. Two documented escape hatches for that case;
    default is a normal verifying context."""
    if os.environ.get("CACHE_PROXY_INSECURE") == "1":
        sys.stderr.write(
            "[cache-proxy] WARNING: CACHE_PROXY_INSECURE=1 — TLS certificate "
            "verification is DISABLED. Only use this to work around a "
            "trusted corporate TLS-inspecting proxy.\n"
        )
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        return ctx

    ca_bundle = os.environ.get("CACHE_PROXY_CA_BUNDLE")
    if ca_bundle:
        return ssl.create_default_context(cafile=ca_bundle)

    return ssl.create_default_context()


class CacheProxyHandler(http.server.BaseHTTPRequestHandler):
    def _forward(self, method):
        # ccache only ever requests keys it generated itself, but this proxy
        # still shouldn't blindly splice untrusted path segments into the
        # upstream URL — normalize first so "../" can't escape the repo the
        # proxy was launched for.
        raw_path = urllib.parse.urlsplit(self.path).path
        safe_path = posixpath.normpath(raw_path)
        if not safe_path.startswith("/"):
            safe_path = "/" + safe_path

        url = f"{UPSTREAM_BASE}{safe_path}"
        body = None
        if method == "PUT":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length)

        req = urllib.request.Request(url, data=body, method=method)
        req.add_header("Authorization", f"Bearer {TOKEN}")

        try:
            with urllib.request.urlopen(req, timeout=30, context=SSL_CONTEXT) as resp:
                self.send_response(resp.status)
                for header in ("Content-Length", "Content-Type"):
                    if resp.headers.get(header):
                        self.send_header(header, resp.headers[header])
                self.end_headers()
                if method != "HEAD":
                    self.wfile.write(resp.read())
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self.end_headers()
        except urllib.error.URLError as e:
            self.send_response(502)
            self.end_headers()
            self.wfile.write(str(e).encode())

    def do_GET(self):
        self._forward("GET")

    def do_HEAD(self):
        self._forward("HEAD")

    def do_PUT(self):
        self._forward("PUT")

    def do_DELETE(self):
        self._forward("DELETE")

    def log_message(self, fmt, *args):
        sys.stderr.write("[cache-proxy] " + (fmt % args) + "\n")


if __name__ == "__main__":
    PORT = int(sys.argv[1])
    artifactory_url = sys.argv[2].rstrip("/")
    repo_key = sys.argv[3]
    TOKEN = sys.argv[4]
    UPSTREAM_BASE = f"{artifactory_url}/{repo_key}"
    SSL_CONTEXT = _build_ssl_context()

    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), CacheProxyHandler)
    print(f"[cache-proxy] listening on 127.0.0.1:{PORT} -> {UPSTREAM_BASE}", file=sys.stderr)
    server.serve_forever()

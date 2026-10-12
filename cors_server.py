#!/usr/bin/env python3
# CORS / Cross-Origin-Resource-Policy para servidor estatico Python.
# Uso:  python cors_server.py [puerto]   (por defecto 8000)
import http.server
import socketserver
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8000

HEADERS = {
    'Cross-Origin-Resource-Policy': 'cross-origin',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET,HEAD,POST,PUT,PATCH,DELETE,OPTIONS',
    'Access-Control-Allow-Headers': '*',
    'Access-Control-Expose-Headers': '*',
}


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        for key, value in HEADERS.items():
            self.send_header(key, value)
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()


socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(('0.0.0.0', PORT), Handler) as httpd:
    print('Serving on http://0.0.0.0:%d' % PORT)
    httpd.serve_forever()

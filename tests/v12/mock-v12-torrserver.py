from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
import time
import threading
import sys
delay = float(sys.argv[2]) if len(sys.argv)>2 else 6

sample = Path(sys.argv[3]) if len(sys.argv)>3 else Path(__file__).parent / 'sample.mp4'
started = None
lock = threading.Lock()
hash_value = '0123456789abcdef0123456789abcdef01234567'

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))))
        elapsed = max(0, time.monotonic() - started) if started else 0
        body = {'hash': hash_value, 'title': 'Проверка буфера', 'stat': 2 if started else 1,
                'preload_size': 64 * 1048576, 'preloaded_bytes': int(min(1, elapsed / delay) * 64 * 1048576),
                'download_speed': 4 * 1048576, 'active_peers': 7,
                'file_stats': [{'id': 1, 'path': 'Тестовое видео.mp4', 'length': sample.stat().st_size}]}
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        global started
        if not self.path.startswith('/stream/'):
            self.send_error(404)
            return
        with lock:
            if started is None:
                started = time.monotonic()
        time.sleep(max(0, delay - (time.monotonic() - started)))
        data = sample.read_bytes()
        self.send_response(200)
        self.send_header('Content-Type', 'video/mp4')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except (ConnectionAbortedError, ConnectionResetError, BrokenPipeError):
            pass

port = int(sys.argv[1]) if len(sys.argv)>1 else 18177
ThreadingHTTPServer(('127.0.0.1', port), Handler).serve_forever()

"""Owned loopback TCP forwarder: real HTTP/WebSocket bytes, no mocked responses."""
import ipaddress
import select
import socket
import socketserver
import threading
from urllib.parse import urlsplit

def upstream(origin):
    url = urlsplit(origin)
    if url.scheme != 'http' or url.port != 3000 or url.path not in ['', '/'] or url.username or url.password or url.query or url.fragment:
        raise RuntimeError('Only the verified internal image HTTP endpoint is permitted')
    address = ipaddress.ip_address(url.hostname)
    if address.version != 4 or not address.is_private or address.is_loopback or address.is_link_local:
        raise RuntimeError('Private owned Docker IPv4 is required')
    return str(address), 3000

class LoopbackImage:
    def __init__(self, origin):
        self.target = upstream(origin)
        self.stop = threading.Event()
        self.server = None
        self.thread = None

    def __enter__(self):
        owner = self
        class Handler(socketserver.BaseRequestHandler):
            def handle(self):
                with socket.create_connection(owner.target, timeout=10) as remote:
                    while not owner.stop.is_set():
                        ready, _, _ = select.select([self.request, remote], [], [], 0.5)
                        for source in ready:
                            data = source.recv(65536)
                            if not data:
                                return
                            (remote if source is self.request else self.request).sendall(data)
        class Server(socketserver.ThreadingTCPServer):
            allow_reuse_address = False
            daemon_threads = True
        # Refuse an occupied port; never terminate another process to obtain it.
        self.server = Server(('127.0.0.1', 3000), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, name='owned-image-browser-forwarder', daemon=True)
        self.thread.start()
        return 'http://127.0.0.1:3000'

    def __exit__(self, *_):
        self.stop.set()
        if self.server:
            self.server.shutdown()
            self.server.server_close()
        if self.thread:
            self.thread.join(timeout=5)

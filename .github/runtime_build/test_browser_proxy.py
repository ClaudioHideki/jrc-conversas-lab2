import unittest
from unittest.mock import patch
import browser_proxy

class BrowserProxyTest(unittest.TestCase):
    def test_accepts_private_image_endpoint(self):
        self.assertEqual(browser_proxy.upstream('http://172.18.0.3:3000'), ('172.18.0.3', 3000))

    def test_rejects_public_or_metadata_endpoints(self):
        for origin in ['http://8.8.8.8:3000', 'http://169.254.169.254:3000', 'http://127.0.0.1:3000']:
            with self.subTest(origin=origin), self.assertRaises(RuntimeError):
                browser_proxy.upstream(origin)

    def test_rejects_credentials_and_routing_changes(self):
        for origin in ['http://user:pass@172.18.0.3:3000', 'https://172.18.0.3:3000',
                       'http://172.18.0.3:80', 'http://172.18.0.3:3000/other', 'http://172.18.0.3:3000/?proxy=external']:
            with self.subTest(origin=origin), self.assertRaises(RuntimeError):
                browser_proxy.upstream(origin)

    def test_binds_only_loopback_and_uses_fixed_owned_origin(self):
        with patch('browser_proxy.socketserver.ThreadingTCPServer.__init__', return_value=None) as bind, \
             patch('browser_proxy.socketserver.ThreadingTCPServer.serve_forever'), \
             patch('browser_proxy.socketserver.ThreadingTCPServer.shutdown'), \
             patch('browser_proxy.socketserver.ThreadingTCPServer.server_close'):
            with browser_proxy.LoopbackImage('http://172.18.0.3:3000') as origin:
                self.assertEqual(origin, 'http://127.0.0.1:3000')
            self.assertEqual(bind.call_args.args[0], ('127.0.0.1', 3000))

if __name__ == '__main__':
    unittest.main()

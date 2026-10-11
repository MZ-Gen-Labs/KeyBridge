import importlib.util
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / 'Resources/keybridge_mcp.py'
spec = importlib.util.spec_from_file_location('keybridge_mcp', SCRIPT)
mcp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mcp)

class MCPTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / 'catalog.json'
        self.raw = {'version': 1, 'generatedAt': datetime.now(timezone.utc).isoformat(),
                    'keys': [{'id': 'key-1', 'name': 'Google AI Studio', 'service': 'Gemini',
                              'variable': 'GOOGLE_AI_S_KEY', 'environment': '本番', 'tags': ['TTS'],
                              'expired': False, 'matchesAppliedValue': True,
                              'value': 'DO_NOT_LEAK', 'notes': 'PRIVATE_MEMO', 'url': 'PRIVATE_URL'}],
                    'sets': [{'id': 'set-1', 'name': 'Normal', 'entryIDs': ['key-1', 'deleted'], 'selectedForMac': True}],
                    'token': 'DO_NOT_LEAK_TOKEN'}
        self.write()
        self.server = mcp.Server(self.path)
    def tearDown(self):
        self.temp.cleanup()
    def write(self):
        self.path.write_text(json.dumps(self.raw))
    def request(self, method, params=None):
        return self.server.handle({'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': params or {}})
    def initialize(self):
        self.request('initialize', {'protocolVersion': '2025-11-25', 'capabilities': {}, 'clientInfo': {'name': 'test', 'version': '1'}})
        self.server.handle({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
    def test_handshake_and_read_only_tools(self):
        self.initialize()
        tools = self.request('tools/list')['result']['tools']
        self.assertEqual(len(tools), 3)
        self.assertTrue(all(tool['annotations']['readOnlyHint'] for tool in tools))
    def test_requires_initialize(self):
        self.assertIn('error', self.request('tools/list'))
    def test_filters_custom_name_and_no_secret_reflection(self):
        self.initialize()
        result = self.request('tools/call', {'name': 'keybridge_list_keys', 'arguments': {'query': 'tts'}})['result']
        self.assertEqual(result['structuredContent']['keys'][0]['variable'], 'GOOGLE_AI_S_KEY')
        for secret in ('DO_NOT_LEAK', 'PRIVATE_MEMO', 'PRIVATE_URL'):
            self.assertNotIn(secret, json.dumps(result))
    def test_set_missing_reference(self):
        result = self.server.call('keybridge_list_sets', {})
        self.assertTrue(result['sets'][0]['keys'][1]['missing'])
    def test_usage_uses_actual_name_and_all_languages(self):
        for language in ('python', 'javascript', 'shell'):
            result = self.server.call('keybridge_get_usage', {'key_id': 'key-1', 'language': language})
            self.assertIn('GOOGLE_AI_S_KEY', result['code'])
            self.assertNotIn('DO_NOT_LEAK', json.dumps(result))
    def test_expired_metadata_is_rejected(self):
        self.raw['generatedAt'] = (datetime.now(timezone.utc) - timedelta(minutes=4)).isoformat()
        self.write()
        with self.assertRaises(mcp.CatalogError):
            self.server.catalog()
    def test_disable_removes_access(self):
        self.path.unlink()
        with self.assertRaises(mcp.CatalogError):
            self.server.catalog()
    def test_bad_arguments_and_code_injection(self):
        for args in ({'key_id': 'key-1', 'language': 'ruby'}, {'key_id': 'missing'}, {'query': 12}, {'include_values': True}):
            with self.assertRaises(mcp.CatalogError):
                self.server.call('keybridge_get_usage' if 'key_id' in args else 'keybridge_list_keys', args)
        self.raw['keys'][0]['variable'] = 'A\"); steal(); //'
        self.write()
        with self.assertRaises(mcp.CatalogError):
            self.server.catalog()
    def test_real_stdio_process_parse_error_and_lifecycle(self):
        messages = [
            '{bad json}',
            json.dumps({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {'protocolVersion': '2025-11-25', 'capabilities': {}, 'clientInfo': {'name': 'test', 'version': '1'}}}),
            json.dumps({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
            json.dumps({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/call', 'params': {'name': 'keybridge_get_usage', 'arguments': {'key_id': 'key-1'}}}),
            json.dumps({'jsonrpc': '2.0', 'id': 3, 'method': 'unknown'})]
        run = subprocess.run(['/usr/bin/python3', str(SCRIPT), '--catalog', str(self.path)], input='\n'.join(messages)+'\n', text=True, capture_output=True, timeout=10)
        self.assertEqual(run.returncode, 0, run.stderr)
        replies = [json.loads(line) for line in run.stdout.splitlines()]
        self.assertEqual(len(replies), 4)
        self.assertEqual(replies[0]['error']['code'], -32700)
        self.assertIn('GOOGLE_AI_S_KEY', replies[2]['result']['content'][0]['text'])
        self.assertNotIn('DO_NOT_LEAK', run.stdout)
        self.assertEqual(replies[3]['error']['code'], -32601)

if __name__ == '__main__':
    unittest.main()

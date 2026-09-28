import importlib.util
from pathlib import Path
import unittest

class AppTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec=importlib.util.spec_from_file_location('sample_app',Path(__file__).resolve().parents[1]/'phase2/app/app.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        cls.client=module.app.test_client()

    def test_root(self):
        response=self.client.get('/')
        self.assertEqual(response.status_code,200)
        self.assertEqual(response.json['application'],'webhook-dashboard')

    def test_probes(self):
        for path in ['/readyz','/healthz']:
            self.assertEqual(self.client.get(path).status_code,200)

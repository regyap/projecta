from pathlib import Path
import unittest
import yaml
ROOT=Path(__file__).resolve().parents[1]

class ConfigurationTests(unittest.TestCase):
    def test_manifest_wiring_and_baseline(self):
        docs={p.stem:yaml.safe_load(p.read_text()) for p in (ROOT/'phase2/openshift').glob('*.yaml')}
        dep=docs['deployment']['spec']; pod=dep['template']['spec'];container=pod['containers'][0]
        self.assertEqual(dep['selector']['matchLabels'],docs['service']['spec']['selector'])
        self.assertEqual(docs['service']['spec']['ports'][0]['targetPort'],container['ports'][0]['name'])
        self.assertFalse(pod['automountServiceAccountToken'])
        self.assertTrue(container['securityContext']['readOnlyRootFilesystem'])
        self.assertFalse(container['securityContext']['allowPrivilegeEscalation'])
        self.assertEqual(container['volumeMounts'][0]['mountPath'],'/tmp')

    def test_deployer_cannot_create_or_read_secrets(self):
        role=list(yaml.safe_load_all((ROOT/'gitlab/deployer-rbac.yaml').read_text()))[1]
        for rule in role['rules']:
            self.assertNotIn('secrets',rule['resources'])
            self.assertNotIn('create',rule['verbs'])
            self.assertNotIn('*',rule['verbs'])
            self.assertTrue(rule['resourceNames'])

    def test_gitlab_jobs_use_scalar_commands(self):
        pipeline=yaml.safe_load((ROOT/'phase2/.gitlab-ci.yml').read_text())
        for name,job in pipeline.items():
            if not isinstance(job,dict):continue
            for phase in ['script','before_script','after_script']:
                for command in job.get(phase,[]):self.assertIsInstance(command,str,(name,command))
        self.assertEqual(yaml.safe_load((ROOT/'.gitlab-ci.yml').read_text())['include'][0]['local'],'phase2/.gitlab-ci.yml')

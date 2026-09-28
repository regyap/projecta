import importlib.util
import json
import os
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parents[1]

class MediaTests(unittest.TestCase):
    def setUp(self):
        self.s3, self.rek, self.geo = MagicMock(), MagicMock(), MagicMock()
        clients = {'s3': self.s3, 'rekognition': self.rek, 'geo-places': self.geo}
        fake = types.ModuleType('boto3')
        fake.client = lambda name: clients[name]
        self.env = patch.dict(os.environ, {'MEDIA_BUCKET': 'test-bucket', 'ENABLE_GEOLOCATION': 'false'})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.modules = patch.dict(sys.modules, {'boto3': fake})
        self.modules.start()
        self.addCleanup(self.modules.stop)
        spec = importlib.util.spec_from_file_location('media_handler', ROOT/'services/media/handler.py')
        self.m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.m)
        self.s3.head_object.return_value = {'ContentLength': 1024, 'ContentType': 'image/jpeg', 'Metadata': {}}
        self.rek.detect_labels.return_value = {'Labels': [{'Name': 'Tree', 'Confidence': 95}]}
        self.geo.reverse_geocode.return_value = {'ResultItems': [{'Address': {'Country': {'Code2': 'SG'}, 'Locality': 'Singapore', 'Label': 'private address'}}]}
        self.record = {'s3': {'bucket': {'name': 'test-bucket'}, 'object': {'key': 'input/test+image.jpg', 'versionId': 'version-1'}}}

    def event(self):
        return {'Records': [{'messageId': 'message-1', 'body': json.dumps({'Records': [self.record]})}]}

    def test_success_uses_exact_version_and_no_geo(self):
        self.assertEqual(self.m.handler(self.event(), None), {'batchItemFailures': []})
        self.s3.head_object.assert_called_once_with(Bucket='test-bucket', Key='input/test image.jpg', VersionId='version-1')
        self.assertEqual(self.rek.detect_labels.call_args.kwargs['Image']['S3Object']['Version'], 'version-1')
        self.geo.reverse_geocode.assert_not_called()
        self.assertTrue(self.s3.put_object.call_args.kwargs['Key'].startswith('results/'))

    def test_retry_is_reported(self):
        self.rek.detect_labels.side_effect = RuntimeError('transient')
        self.assertEqual(self.m.handler(self.event(), None)['batchItemFailures'], [{'itemIdentifier':'message-1'}])
        self.s3.put_object.assert_not_called()

    def test_duplicate_result_key_is_stable(self):
        self.m.handler(self.event(), None); self.m.handler(self.event(), None)
        self.assertEqual(self.s3.put_object.call_args_list[0].kwargs['Key'], self.s3.put_object.call_args_list[1].kwargs['Key'])

    def test_wrong_bucket_and_output_prefix_are_rejected(self):
        for bucket,key in [('other','input/a.jpg'),('test-bucket','results/a.jpg')]:
            self.record['s3']['bucket']['name']=bucket;self.record['s3']['object']['key']=key
            self.assertTrue(self.m.handler(self.event(), None)['batchItemFailures'])
        self.rek.detect_labels.assert_not_called()

    def test_version_is_required(self):
        del self.record['s3']['object']['versionId']
        self.assertTrue(self.m.handler(self.event(), None)['batchItemFailures'])

    def test_oversized_input(self):
        self.s3.head_object.return_value['ContentLength']=6*1024*1024
        self.assertTrue(self.m.handler(self.event(), None)['batchItemFailures'])
        self.rek.detect_labels.assert_not_called()

    def test_consent_required(self):
        os.environ['ENABLE_GEOLOCATION']='true'
        self.s3.head_object.return_value['Metadata']={'latitude':'1.3','longitude':'103.8'}
        self.m.handler(self.event(), None)
        self.geo.reverse_geocode.assert_not_called()

    def test_geolocation_is_coarse_and_coordinate_order_correct(self):
        os.environ['ENABLE_GEOLOCATION']='true'
        self.s3.head_object.return_value['Metadata']={'location-consent':'true','latitude':'1.3','longitude':'103.8'}
        self.assertEqual(self.m.handler(self.event(),None)['batchItemFailures'], [])
        self.geo.reverse_geocode.assert_called_once_with(QueryPosition=[103.8,1.3],MaxResults=1,IntendedUse='Storage')
        output=json.loads(self.s3.put_object.call_args.kwargs['Body'])
        self.assertEqual(output['location'],{'country':'SG','locality':'Singapore'})
        self.assertNotIn('private address',json.dumps(output))

    def test_invalid_coordinates(self):
        for lat in ['nan','inf','91','bad']:
            with self.assertRaises(ValueError):self.m.coordinates({'location-consent':'true','latitude':lat,'longitude':'103.8'})

    def test_s3_test_event(self):
        event={'Records':[{'messageId':'test','body':json.dumps({'Event':'s3:TestEvent'})}]}
        self.assertEqual(self.m.handler(event,None)['batchItemFailures'],[])
        self.rek.detect_labels.assert_not_called()

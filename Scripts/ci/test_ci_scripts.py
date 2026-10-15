"""Unit tests for the CI helpers: python3 -m unittest discover -s Scripts/ci -p 'test_*.py'"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import altsource  # noqa: E402
import select_xcode  # noqa: E402

BRANDING = json.loads((Path(__file__).parents[2] / '.github/altsource.json').read_text())


def build(n, bid='io.github.me.studio', msg='Fix export\n\nbody'):
    return {'schemaVersion': 1, 'name': 'Studio', 'bundleIdentifier': bid, 'version': '0.1.0',
            'buildVersion': str(n), 'minOSVersion': '18.0', 'size': 1000 + n, 'sha256': 'ab' * 32,
            'tag': f'build-{n}', 'downloadURL': f'https://github.com/me/studio/releases/download/build-{n}/StudioCreativeSuite.ipa',
            'date': f'2026-10-{10 + n:02d}T10:00:00+00:00', 'commit': 'abcdef1234', 'commitMessage': msg,
            'appPermissions': {'entitlements': ['com.apple.developer.kernel.increased-memory-limit'], 'privacy': {}}}


class AltSourceTests(unittest.TestCase):
    def test_versions_newest_first_numeric(self):
        with tempfile.TemporaryDirectory() as d:
            for n in (9, 10, 2):
                (Path(d) / f'build-{n}').mkdir()
                (Path(d) / f'build-{n}' / 'build-info.json').write_text(json.dumps(build(n)))
            builds = altsource.load_builds(d)
        self.assertEqual([b['buildVersion'] for b in builds], ['10', '9', '2'])
        src = altsource.make_source('me/studio', builds, BRANDING, 'https://x/icon.png')
        app = src['apps'][0]
        self.assertEqual([v['buildVersion'] for v in app['versions']], ['10', '9', '2'])
        self.assertEqual(app['versions'][0]['downloadURL'], build(10)['downloadURL'])
        self.assertEqual(app['appPermissions']['entitlements'], ['com.apple.developer.kernel.increased-memory-limit'])
        self.assertEqual(src['identifier'], 'io.github.me.studio')
        self.assertEqual(src['news'][0]['identifier'], 'build-10')
        self.assertTrue(app['versions'][0]['localizedDescription'].startswith('Fix export'))

    def test_empty_feed_is_valid(self):
        src = altsource.make_source('me/studio', [], BRANDING, 'https://x/icon.png')
        self.assertEqual(src['apps'], [])

    def test_other_bundle_ids_excluded(self):
        builds = [build(3, bid='new.id'), build(2, bid='old.id')]
        versions = altsource.make_source('me/studio', builds, BRANDING, 'i')['apps'][0]['versions']
        self.assertEqual([v['buildVersion'] for v in versions], ['3'])

    def test_rejects_unpublished_build(self):
        with tempfile.TemporaryDirectory() as d:
            b = build(1)
            b['downloadURL'] = ''
            (Path(d) / 'build-info.json').write_text(json.dumps(b))
            with self.assertRaises(SystemExit):
                altsource.load_builds(d)


class XcodeTests(unittest.TestCase):
    def apps(self, d, *names):
        for n in names:
            (Path(d) / n / 'Contents/Developer').mkdir(parents=True)
        return select_xcode.candidates(Path(d))

    def test_newest_beta_wins(self):
        with tempfile.TemporaryDirectory() as d:
            apps = self.apps(d, 'Xcode_27.0.app', 'Xcode_27.1_beta.app', 'Xcode_27.1_beta_3.app', 'Xcode_26.4_beta.app')
            chosen, beta = select_xcode.choose(apps, False)
        self.assertEqual((chosen.name, beta), ('Xcode_27.1_beta_3.app', True))

    def test_no_beta_fails_unless_allowed(self):
        with tempfile.TemporaryDirectory() as d:
            apps = self.apps(d, 'Xcode_27.0.app', 'Xcode_26.4.app')
            self.assertEqual(select_xcode.choose(apps, False), (None, False))
            chosen, beta = select_xcode.choose(apps, True)
        self.assertEqual((chosen.name, beta), ('Xcode_27.0.app', False))


if __name__ == '__main__':
    unittest.main()

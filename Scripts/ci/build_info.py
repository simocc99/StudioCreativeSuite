"""Describe a built .ipa for the AltSource: values are read from the package, never invented.

Entitlements come from the app's signature (ad-hoc in CI), privacy strings from Info.plist,
so the AltSource permissions match what SideStore/AltStore find in the .ipa.
"""
import argparse
import datetime
import hashlib
import json
import os
import plistlib
import subprocess
from pathlib import Path

# Keys the signing tool owns; sources do not list them.
IMPLICIT = {'application-identifier', 'com.apple.developer.team-identifier', 'get-task-allow', 'keychain-access-groups'}


def entitlements(app):
    out = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)], capture_output=True).stdout
    if not out.strip():
        return []
    return sorted(set(plistlib.loads(out)) - IMPLICIT)


def privacy(app):
    result = {}
    for plist in [app / 'Info.plist', *sorted(app.glob('PlugIns/*.appex/Info.plist'))]:
        data = plistlib.loads(plist.read_bytes())
        result.update({k: v for k, v in data.items() if k.endswith('UsageDescription')})
    return result


def describe(app, ipa, repo, tag, ents, env=os.environ):
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
    sha = env.get('GITHUB_SHA', '')
    return {
        'schemaVersion': 1,
        'name': info.get('CFBundleDisplayName') or info['CFBundleName'],
        'bundleIdentifier': info['CFBundleIdentifier'],
        'version': str(info['CFBundleShortVersionString']),
        'buildVersion': str(info['CFBundleVersion']),
        'minOSVersion': info['MinimumOSVersion'],
        'size': ipa.stat().st_size,
        'sha256': digest,
        'tag': tag,
        'downloadURL': f'https://github.com/{repo}/releases/download/{tag}/{ipa.name}' if repo else '',
        'date': datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat(),
        'commit': sha,
        'commitMessage': env.get('STUDIO_COMMIT_MESSAGE', ''),
        'xcode': info.get('DTXcodeBuild', ''),
        'sdk': info.get('DTSDKName', ''),
        'appPermissions': {'entitlements': ents, 'privacy': privacy(app)},
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--app', required=True)
    p.add_argument('--ipa', required=True)
    p.add_argument('--repo', default='')
    p.add_argument('--tag', required=True)
    p.add_argument('--output', required=True)
    a = p.parse_args()
    app = Path(a.app)
    result = describe(app, Path(a.ipa), a.repo, a.tag, entitlements(app))
    Path(a.output).write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({k: result[k] for k in ('bundleIdentifier', 'version', 'buildVersion', 'size')}))


if __name__ == '__main__':
    main()

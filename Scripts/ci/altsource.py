"""Build the AltSource (AltStore Classic / SideStore apps.json) from the published builds.

The feed is regenerated from scratch every time from the build-info.json of each kept
release, so it never drifts from what is actually downloadable: a deleted release simply
disappears from the feed on the next run.

  altsource.py --repo owner/repo --builds DIR --branding .github/altsource.json \
               --icon App/.../AppIcon.png --output work/source
DIR holds one build-info.json per release (any layout, searched recursively).
"""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

SOURCE_TAG = 'source'
MAX_NEWS = 10


def load_builds(folder):
    builds = []
    for path in Path(folder).rglob('build-info.json'):
        info = json.loads(path.read_text())
        if info.get('schemaVersion') != 1 or not info.get('downloadURL'):
            raise SystemExit(f'{path}: not a published build')
        builds.append(info)
    # newest first; buildVersion is the CI run number
    builds.sort(key=lambda b: int(b['buildVersion']), reverse=True)
    return builds


def notes_for(build):
    message = (build.get('commitMessage') or '').strip()
    commit = (build.get('commit') or '')[:7]
    first = message.splitlines()[0] if message else 'Build automatica'
    return f'{first}\n\nBuild {build["buildVersion"]}' + (f', commit {commit}' if commit else '')


def make_source(repo, builds, branding, icon_url):
    owner = repo.split('/')[0]
    website = f'https://github.com/{repo}'
    source = {
        **branding['source'],
        'identifier': f'io.github.{owner.lower()}.{repo.split("/")[1].lower()}',
        'website': website,
        'iconURL': icon_url,
        'apps': [],
        'news': [],
    }
    if not builds:
        return source
    latest = builds[0]
    versions = [{
        'version': b['version'],
        'buildVersion': b['buildVersion'],
        'date': b['date'],
        'localizedDescription': notes_for(b),
        'downloadURL': b['downloadURL'],
        'size': b['size'],
        'sha256': b['sha256'],
        'minOSVersion': b['minOSVersion'],
    } for b in builds if b['bundleIdentifier'] == latest['bundleIdentifier']]
    source['apps'].append({
        **branding['app'],
        'bundleIdentifier': latest['bundleIdentifier'],
        'developerName': owner,
        'iconURL': icon_url,
        'screenshots': [],
        'appPermissions': latest['appPermissions'],
        'versions': versions,
    })
    source['news'] = [{
        'title': f'{branding["app"]["name"]} build {b["buildVersion"]}',
        'identifier': f'build-{b["buildVersion"]}',
        'caption': notes_for(b).splitlines()[0],
        'date': b['date'],
        'tintColor': branding['app']['tintColor'],
        'url': f'{website}/releases/tag/{b["tag"]}',
        'appID': b['bundleIdentifier'],
        'notify': False,
    } for b in builds[:MAX_NEWS]]
    return source


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--repo', required=True)
    p.add_argument('--builds', required=True)
    p.add_argument('--branding', required=True)
    p.add_argument('--icon', required=True)
    p.add_argument('--output', required=True)
    a = p.parse_args()
    out = Path(a.output)
    out.mkdir(parents=True, exist_ok=True)
    icon = Path(a.icon)
    # content-addressed name: clients cache icons aggressively
    icon_name = f'icon-{hashlib.sha256(icon.read_bytes()).hexdigest()[:12]}.png'
    shutil.copyfile(icon, out / icon_name)
    icon_url = f'https://github.com/{a.repo}/releases/download/{SOURCE_TAG}/{icon_name}'
    source = make_source(a.repo, load_builds(a.builds), json.loads(Path(a.branding).read_text()), icon_url)
    (out / 'apps.json').write_text(json.dumps(source, indent=2, ensure_ascii=False) + '\n')
    versions = source['apps'][0]['versions'] if source['apps'] else []
    print(f'apps.json: {len(versions)} build(s), latest {versions[0]["buildVersion"] if versions else "none"}')


if __name__ == '__main__':
    main()

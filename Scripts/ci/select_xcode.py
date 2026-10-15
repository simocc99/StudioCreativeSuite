"""Pick the newest installed Xcode beta and print DEVELOPER_DIR=… lines for $GITHUB_ENV.

Never falls back to a stable Xcode silently: with no beta installed it fails, unless
XCODE_ALLOW_STABLE=true, in which case it picks the newest Xcode and says so.
"""
import os
import re
import sys
from pathlib import Path


def version_key(path):
    return tuple(int(n) for n in re.findall(r'\d+', path.name))


def candidates(root=Path('/Applications')):
    return [p for p in root.glob('Xcode*.app') if not p.is_symlink() and (p / 'Contents/Developer').is_dir()]


def choose(apps, allow_stable):
    betas = [p for p in apps if 'beta' in p.name.lower()]
    if betas:
        return max(betas, key=version_key), True
    if allow_stable and apps:
        return max(apps, key=version_key), False
    return None, False


def main():
    allow_stable = os.environ.get('XCODE_ALLOW_STABLE', '').lower() == 'true'
    apps = candidates()
    print('Installed Xcode: ' + ', '.join(sorted(p.name for p in apps)), file=sys.stderr)
    chosen, is_beta = choose(apps, allow_stable)
    if chosen is None:
        raise SystemExit('No Xcode beta installed on this runner (set the XCODE_ALLOW_STABLE variable to true to accept a stable Xcode)')
    if not is_beta:
        print(f'::warning::No Xcode beta on this runner; using stable {chosen.name}', file=sys.stderr)
    print(f'DEVELOPER_DIR={chosen}/Contents/Developer')
    print(f'XCODE_CACHE_ID={chosen.name}')


if __name__ == '__main__':
    main()

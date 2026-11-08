#!/usr/bin/env python3
"""Exercise release policy with isolated packaging tools, not real signing or Notes."""
from pathlib import Path
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

PROJECT = Path(__file__).resolve().parents[1]


class ReleasePackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='wordnest-release-tests-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ('scripts', 'config', 'Assets/Branding', 'docs', 'bin'):
            (self.root / name).mkdir(parents=True)
        shutil.copyfile(PROJECT / 'scripts/release.sh', self.root / 'scripts/release.sh')
        shutil.copyfile(PROJECT / 'config/product.env', self.root / 'config/product.env')
        for name in ('LICENSE', 'NOTICE', 'PRIVACY.md', 'THIRD-PARTY-NOTICES.md',
                     'Assets/Branding/LICENSE', 'docs/INSTALL.md', 'docs/INSTALL.zh-CN.md'):
            (self.root / name).write_text('Fixture document: ' + name + '\n')
        (self.root / 'config/source-files.txt').write_text('config/product.env\nscripts/release.sh\n')
        (self.root / 'scripts/export-source.sh').write_text('#!/bin/bash\nexit 0\n')
        (self.root / 'scripts/build.sh').write_text('''#!/bin/bash
set -eu
test "$WORDNEST_BUILD_MODE" = preview
test "$SUBTITLE_LOOKUP_SIGNING_IDENTITY" = -
mkdir -p "$SUBTITLE_LOOKUP_APP_DIR/Contents"
printf fixture > "$SUBTITLE_LOOKUP_APP_DIR/Contents/fixture"
if test "${FIXTURE_CHANGE_SOURCE:-no}" = yes; then
  printf '\\n# Fixture mutation\\n' >> "$(dirname "$0")/../config/product.env"
fi
''')
        self.tool('ditto', '''import sys, zipfile
from pathlib import Path
source, destination = map(Path, sys.argv[-2:])
with zipfile.ZipFile(destination, 'w') as archive:
    for item in source.rglob('*'):
        if item.is_file() and not item.is_symlink():
            archive.write(item, item.relative_to(source).as_posix())
''')
        self.tool('hdiutil', '''import sys
from pathlib import Path
if sys.argv[1] == 'create':
    Path(sys.argv[-1]).write_bytes(b'Fixture disk image, not a mountable DMG')
elif sys.argv[1] != 'verify':
    raise SystemExit(90)
''')
        for command in ('xcrun', 'codesign', 'spctl'):
            self.tool(command, "raise SystemExit('Signing/notarization tool must not run in unsigned fixture')\n")
        self.env = dict(os.environ, PATH=str(self.root / 'bin') + os.pathsep + os.environ['PATH'],
                        SUBTITLE_LOOKUP_SIGNING_IDENTITY='Developer ID Application: Unused Fixture',
                        WORDNEST_NOTARY_PROFILE='MustNotBeUsed')
        self.env.pop('WORDNEST_RELEASE_DIR', None)
        (self.root / '.gitignore').write_text('work/\n')
        self.run_git('init', '-q')
        self.run_git('add', '.')
        self.run_git('-c', 'user.name=WordNest Fixture', '-c', 'user.email=fixture@example.invalid',
                     'commit', '-qm', 'Isolated packaging fixture')

    def tool(self, name, code):
        file = self.root / 'bin' / name
        file.write_text('#!' + sys.executable + '\n' + code)
        file.chmod(0o755)

    def run_git(self, *args):
        return subprocess.run(['git', *args], cwd=self.root, check=True,
                              capture_output=True, text=True)

    def package(self, *args, **overrides):
        return subprocess.run(['/bin/bash', 'scripts/release.sh', *args], cwd=self.root,
                              env=dict(self.env, **overrides), capture_output=True, text=True)

    def test_public_unsigned_labels_payload_metadata_and_checksums(self):
        result = self.package('--unsigned')
        self.assertEqual(result.returncode, 0, result.stderr)
        directory = self.root / 'work/releases'
        base = 'WordNest-26.1.0-build1-macos-arm64-unnotarized'
        with zipfile.ZipFile(directory / (base + '.zip')) as archive:
            for name in ('UNNOTARIZED.txt', 'INSTALL.md', 'INSTALL.zh-CN.md',
                         'WordNest-artwork-LICENSE.txt', 'WordNest.app/Contents/fixture'):
                self.assertIn(name, archive.namelist())
            self.assertNotIn('UNSIGNED-PREVIEW.txt', archive.namelist())
            self.assertIn(b'NOT Developer ID-signed', archive.read('UNNOTARIZED.txt'))
        info = dict(line.split('=', 1) for line in (directory / (base + '-build-info.txt')).read_text().splitlines())
        self.assertEqual(info['package_mode'], 'unsigned')
        self.assertEqual(info['signing'], 'ad-hoc')
        self.assertEqual(info['notarized'], 'no')
        self.assertEqual(info['source_state'], 'clean')
        self.assertEqual(info['source_revision'], self.run_git('rev-parse', 'HEAD').stdout.strip())
        for line in (directory / (base + '-SHA256SUMS.txt')).read_text().splitlines():
            digest, name = line.split('  ', 1)
            self.assertEqual(digest, hashlib.sha256((directory / name).read_bytes()).hexdigest())
        duplicate = self.package('--unsigned')
        self.assertEqual(duplicate.returncode, 2)
        self.assertIn('Refusing to overwrite', duplicate.stderr)

    def test_unsigned_requires_clean_source(self):
        with (self.root / 'config/product.env').open('a') as file:
            file.write('\n# Uncommitted fixture\n')
        result = self.package('--unsigned')
        self.assertEqual(result.returncode, 2)
        self.assertIn('clean committed', result.stderr)
        self.assertFalse((self.root / 'work/releases').exists())

    def test_unsigned_requires_no_apple_configuration(self):
        result = self.package('--unsigned', SUBTITLE_LOOKUP_SIGNING_IDENTITY='', WORDNEST_NOTARY_PROFILE='')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_dirty_preview_remains_distinct(self):
        (self.root / 'untracked-fixture.txt').write_text('private local fixture')
        result = self.package('--unsigned-preview')
        self.assertEqual(result.returncode, 0, result.stderr)
        directory = self.root / 'work/releases'
        archive = next(directory.glob('*.zip'))
        self.assertIn('-unsigned-preview.zip', archive.name)
        with zipfile.ZipFile(archive) as bundle:
            self.assertIn('UNSIGNED-PREVIEW.txt', bundle.namelist())
            self.assertNotIn('UNNOTARIZED.txt', bundle.namelist())
        self.assertIn('source_state=dirty', next(directory.glob('*-build-info.txt')).read_text())

    def test_signed_modes_fail_without_credentials(self):
        for args in ((), ('--signed',)):
            with self.subTest(args=args):
                result = self.package(*args, SUBTITLE_LOOKUP_SIGNING_IDENTITY='-', WORDNEST_NOTARY_PROFILE='')
                self.assertEqual(result.returncode, 2)
                self.assertIn('No unsigned fallback', result.stderr)
        self.assertFalse((self.root / 'work/releases').exists())

    def test_rejects_ambiguous_or_unknown_modes(self):
        for args in (('--unknown',), ('--unsigned', '--signed')):
            with self.subTest(args=args):
                self.assertEqual(self.package(*args).returncode, 2)

    def test_source_change_during_build_prevents_final_artifacts(self):
        result = self.package('--unsigned', FIXTURE_CHANGE_SOURCE='yes')
        self.assertEqual(result.returncode, 2)
        self.assertIn('Public source changed during packaging', result.stderr)
        self.assertEqual(list((self.root / 'work/releases').iterdir()), [])
        self.assertEqual(list((self.root / 'work/release-staging').iterdir()), [])


if __name__ == '__main__':
    unittest.main(verbosity=2)

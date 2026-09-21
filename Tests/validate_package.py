"""Inspect the actual deb without installing it or applying its setuid permissions."""
from pathlib import Path
import io
import lzma
import plistlib
import re
import subprocess
import sys
import tarfile
from macho_signature import verify_signature

package = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('Releases/com.creaturecoding.tweaksettings_1.0.9_iphoneos-arm64.deb')
blob = package.read_bytes()
assert blob.startswith(b'!<arch>\n')
members = {}
offset = 8
while offset < len(blob):
    header = blob[offset:offset + 60]
    assert header[58:60] == b'`\n'
    name = header[:16].decode().strip().rstrip('/')
    size = int(header[48:58])
    members[name] = blob[offset + 60:offset + 60 + size]
    offset += 60 + size + size % 2
assert members['debian-binary'] == b'2.0\n'

def archive(prefix):
    name = next(name for name in members if name.startswith(prefix))
    data = members[name]
    if name.endswith('.lzma'):
        data = lzma.decompress(data)
    return tarfile.open(fileobj=io.BytesIO(data), mode='r:*')

with archive('control.tar') as control, archive('data.tar') as data:
    controls = {member.name[2:] if member.name.startswith('./') else member.name: member for member in control.getmembers()}
    text = control.extractfile(controls['control']).read().decode()
    assert 'Architecture: iphoneos-arm64' in text
    assert 'Version: 1.0.9' in text
    assert 'firmware (>= 15.0)' in text
    for name in ('postinst', 'postrm'):
        assert controls[name].mode & 0o111
    files = {member.name[2:] if member.name.startswith('./') else member.name: member for member in data.getmembers()}
    for name, member in files.items():
        if member.isfile():
            assert name.startswith('var/jb/'), name
            assert member.uid == member.gid == 0, name
            assert member.mode & 0o022 == 0, name
    app = 'var/jb/Applications/TweakSettings.app/'
    helper = 'var/jb/usr/bin/tweaksettings-utility'
    assert files[helper].mode == 0o4755
    assert files[app + 'TweakSettings'].mode == 0o755
    info = plistlib.loads(data.extractfile(files[app + 'Info.plist']).read())
    assert info['CFBundleShortVersionString'] == info['CFBundleVersion'] == '1.0.9'
    assert info['MinimumOSVersion'] == '15.0'
    assert 'arm64' in info['UIRequiredDeviceCapabilities']
    assert app + 'en.lproj/Localizable.strings' in files
    assert app + 'Assets.car' in files
    assert any(name.startswith(app + 'Base.lproj/LaunchScreen.storyboardc') for name in files)
    destination = Path('build/package-check')
    destination.mkdir(parents=True, exist_ok=True)
    for name in (helper, app + 'TweakSettings'):
        binary = destination / Path(name).name
        binary.write_bytes(data.extractfile(files[name]).read())
        arches = subprocess.check_output(['xcrun', 'lipo', '-archs', str(binary)], text=True).split()
        assert set(arches) == {'arm64', 'arm64e'}, arches
        commands = subprocess.check_output(['xcrun', 'otool', '-arch', 'all', '-l', str(binary)], text=True)
        assert commands.count('cmd LC_CODE_SIGNATURE') == 2
        assert len(re.findall(r'minos 15\.0\b', commands)) == 2
        libraries = subprocess.check_output(['xcrun', 'otool', '-L', str(binary)], text=True)
        assert '/Users/' not in libraries and '/opt/' not in libraries
        for arch in arches:
            thin = binary.with_suffix('.' + arch)
            subprocess.run(['xcrun', 'lipo', str(binary), '-thin', arch, '-output', str(thin)], check=True)
            entitlement_data = subprocess.check_output(['ldid', '-e', str(thin)])
            entitlements = plistlib.loads(entitlement_data)
            assert entitlements['platform-application'] is True
            if name == helper:
                assert 'get-task-allow' not in entitlements
                assert 'task_for_pid-allow' not in entitlements
            verify_signature(thin.read_bytes())
        print(f'{binary.name}: arm64 + arm64e, iOS 15.0 minimum, ldid code/entitlement hashes verified')
print(f'{package.name}: rootless layout, root ownership, modes, resources and versions passed')

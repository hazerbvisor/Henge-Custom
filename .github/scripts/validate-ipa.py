"""Validate the official ad-hoc IPA before exposing it as a build artifact."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import zipfile

ipa, source, husk = map(Path, sys.argv[1:])

def run(*args):
    return subprocess.check_output(args, text=True).strip()

def require(condition, message):
    if not condition:
        raise SystemExit(message)

def plist(path):
    return plistlib.loads(path.read_bytes())

fix = 'f0eec63e9d62966133f861d8b57aedc890437467'
subprocess.run(['git', '-C', str(source), 'merge-base', '--is-ancestor', fix, 'HEAD'], check=True)
with tempfile.TemporaryDirectory() as tmp:
    with zipfile.ZipFile(ipa) as archive:
        require(archive.testzip() is None, 'Corrupt IPA')
        for item in archive.infolist():
            p = Path(item.filename)
            require(not p.is_absolute() and '..' not in p.parts, 'Unsafe archive path')
            require(not p.name.lower().startswith(('avpbooter', 'avpsepbooter')) and p.suffix.lower() not in
                    ('.ipsw', '.dmg', '.img', '.img4', '.im4p', '.aea', '.qcow2', '.vhdx'),
                    f'Firmware/restore image in IPA: {p}')
        archive.extractall(tmp)
    app = Path(tmp) / 'Payload/Henge.app'
    helper = app / 'PlugIns/HengeJITHelper.appex'
    framework = app / 'Frameworks/StikJIT.framework'
    for f in [app/'Henge', app/'henge-jit.js', app/'henge-agent.gz',
              helper/'HengeJITHelper', framework/'StikJIT', framework/'Info.plist']:
        require(f.is_file() and f.stat().st_size > 0, f'Missing required bundle file: {f}')
    require(b'avp-ctrr' in (app/'Henge').read_bytes(), 'avp-ctrr implementation missing from app binary')
    info = plist(app/'Info.plist')
    require(info['CFBundleIdentifier'] == 'com.henge.app', 'App bundle ID changed')
    require(plist(helper/'Info.plist')['CFBundleIdentifier'] == 'com.henge.app.JITHelper', 'Helper ID changed')
    require(2 in info['UIDeviceFamily'], 'iPad support missing')
    require(tuple(map(int, info['MinimumOSVersion'].split('.'))) <= (27, 0, 1), 'Deployment target too high')
    for bundle, executable in [(app, 'Henge'), (helper, 'HengeJITHelper'), (framework, 'StikJIT')]:
        subprocess.run(['codesign', '--verify', '--strict', str(bundle)], check=True)
        require('arm64' in run('lipo', '-archs', str(bundle/executable)), 'arm64 missing')
    embedded = subprocess.check_output(['codesign', '-d', '--entitlements', ':-', str(app)], stderr=subprocess.DEVNULL)
    entitlements = plistlib.loads(embedded)
    expected = plist(source/'ios/Henge/Henge.entitlements')
    require(all(entitlements.get(k) == v for k, v in expected.items()), 'Upstream entitlements lost')
    subprocess.run(['nm', str(source/'build/ios/devices/vmapple.o')], check=True, stdout=subprocess.DEVNULL)
    manifest = {
        'henge_commit': run('git', '-C', str(source), 'rev-parse', 'HEAD'),
        'husk_commit': run('git', '-C', str(husk), 'rev-parse', 'HEAD'),
        'required_fix_ancestor': fix,
        'sha256': hashlib.sha256(ipa.read_bytes()).hexdigest(),
        'bundle_identifier': info['CFBundleIdentifier'],
        'entitlements': entitlements,
        'signing': 'ad-hoc; re-sign with your own development certificate',
        'xcode': run('xcodebuild', '-version'),
        'run_url': f"{os.environ['GITHUB_SERVER_URL']}/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}",
    }
    (ipa.parent/'build-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print(json.dumps(manifest, indent=2))

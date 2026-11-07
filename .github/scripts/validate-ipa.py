"""Validate the official ad-hoc GPU-fix IPA and preserved input/JIT functionality."""
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
upstream = 'da7332e32134f0aa14a67f8cbf67307e68f5367e'
mouse_fix = 'e740e26fa0efcf62feb10ef85a7ab360281428c0'
subprocess.run(['git', '-C', str(source), 'merge-base', '--is-ancestor', mouse_fix, 'HEAD'], check=True)
# The workaround must not alter the shared VM or on-screen mouse contract.
unchanged = ['ios/Henge/Native/henge-vm.c', 'host/vm.c', 'devices/virtio_input.c',
             'devices/virtio_input.h', 'ios/Henge/Trackpad.swift']
subprocess.run(['git', '-C', str(source), 'diff', '--exit-code', upstream, 'HEAD', '--', *unchanged], check=True)
mouse_sources = ['ios/Henge/Hardware.swift', 'ios/Henge/PhysicalMouseButtons.swift', 'ios/Henge/SettingsView.swift']
gpu_sources = ['devices/pvg_metal.m', 'devices/pvg_lite.c', 'devices/pvg_mac.m', 'devices/pvg_decode.h',
               'ios/Henge/GPUDiagnostics.swift', 'ios/Henge/SessionView.swift', 'ios/Henge/Installer.swift']
subprocess.run(['git', '-C', str(source), 'diff', '--exit-code', 'HEAD', '--', *gpu_sources], check=True)
gpu_test_log = ipa.parent/'gpu-tests.log'
require(gpu_test_log.is_file() and gpu_test_log.stat().st_size > 0, 'GPU test log missing')
gpu_test_output = gpu_test_log.read_text()
require('PASS' in gpu_test_output, 'GPU tests did not report a pass')
subprocess.run(['git', '-C', str(source), 'diff', '--exit-code', 'HEAD', '--', *mouse_sources], check=True)
require(run('git', '-C', str(source), 'rev-parse', 'HEAD') == os.environ['HENGE_SHA'], 'Wrong fork commit built')
buildlog = (source/'ios/build/DerivedData.buildlog').read_text()
for name in ['Hardware.swift', 'PhysicalMouseButtons.swift', 'SettingsView.swift', 'GPUDiagnostics.swift']:
    require(name in buildlog, f'Required custom source not in compiler log: {name}')
subprocess.run(['git', '-C', str(source), 'merge-base', '--is-ancestor', fix, 'HEAD'], check=True)
with tempfile.TemporaryDirectory() as tmp:
    with zipfile.ZipFile(ipa) as archive:
        require(archive.testzip() is None, 'Corrupt IPA')
        for item in archive.infolist():
            p = Path(item.filename)
            require(not p.is_absolute() and '..' not in p.parts, 'Unsafe archive path')
            require(p.suffix.lower() not in ('.mobileprovision', '.provisionprofile', '.p12', '.pfx', '.p8'), f'Signing material in IPA: {p}')
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
    require(b'henge.mouse.swapRightAndMiddle' in (app/'Henge').read_bytes(), 'Compatibility setting missing from compiled app')
    require(b'henge.mouse.swapLeftAndMiddle' not in (app/'Henge').read_bytes(), 'Previous left/middle workaround still present in compiled app')
    require(b'HV_PVG_DIAGNOSTICS' in (app/'Henge').read_bytes(), 'GPU diagnostics missing from compiled renderer')
    require(b'henge.gpu.diagnostics' in (app/'Henge').read_bytes(), 'GPU diagnostics preference missing from compiled app')
    require(b'physical mouse button: raw=' in (app/'Henge').read_bytes(), 'Mouse routing diagnostics missing from compiled app')
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
        'mouse_fix_ancestor': mouse_fix,
        'upstream_baseline': upstream,
        'workflow_commit': os.environ['GITHUB_SHA'],
        'mouse_sources_sha256': {p: hashlib.sha256((source/p).read_bytes()).hexdigest() for p in mouse_sources},
        'gpu_sources_sha256': {p: hashlib.sha256((source/p).read_bytes()).hexdigest() for p in gpu_sources},
        'gpu_fix_status': 'candidate; physical-device verification pending',
        'gpu_physical_device_status': 'awaiting verification on iPad Air M4',
        'gpu_tests_log_sha256': hashlib.sha256(gpu_test_log.read_bytes()).hexdigest(),
        'gpu_test_skips': [line for line in gpu_test_output.splitlines() if 'SKIP' in line][:16],
        'mouse_compatibility_default': 'swap physical right/middle; left unchanged',
        'shared_input_pipeline': 'unchanged from upstream',
        'sha256': hashlib.sha256(ipa.read_bytes()).hexdigest(),
        'bundle_identifier': info['CFBundleIdentifier'],
        'entitlements': entitlements,
        'signing': 'ad-hoc; re-sign with your own development certificate',
        'xcode': run('xcodebuild', '-version'),
        'run_url': f"{os.environ['GITHUB_SERVER_URL']}/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}",
    }
    (ipa.parent/'build-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print(json.dumps(manifest, indent=2))

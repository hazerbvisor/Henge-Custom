#!/usr/bin/env python3
"""Apply and verify the isolated Henge 0.2 M4 conservative-startup patch.

This modifies only Swift startup preferences and the transient boot configuration.
No virtual disk, APFS volume, auxiliary storage or machine.json is edited.
"""
from pathlib import Path
import hashlib
import json
import os
import plistlib
import subprocess
import sys
import zipfile

ROOT = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else Path("Henge").resolve()
MODE = sys.argv[1] if len(sys.argv) > 1 else "patch"
UPSTREAM_SHA = "f9c12c93620af4c4c5f5f65f9793b72f883be682"
FILES = [
    "ios/Henge/EngineTuning.swift",
    "ios/Henge/Machines.swift",
    "ios/Henge/SessionView.swift",
    "ios/Henge/SettingsView.swift",
]

def run(*args):
    return subprocess.check_output(args, text=True).strip()

def replace_once(relative_path, before, after):
    path = ROOT / relative_path
    source = path.read_text()
    count = source.count(before)
    if count != 1:
        raise SystemExit(f"{relative_path}: expected one exact patch anchor, got {count}: {before[:70]!r}")
    path.write_text(source.replace(before, after, 1))

def verify_base():
    current = run("git", "-C", str(ROOT), "rev-parse", "HEAD")
    if current != UPSTREAM_SHA:
        raise SystemExit(f"Wrong upstream Henge version, expected {UPSTREAM_SHA}, got {current}")
    print("PASS upstream exact release source:", current)

def apply_patch():
    verify_base()
    e = "ios/Henge/EngineTuning.swift"
    replace_once(e,
        '    static let superblocksKey = "henge.perf.superblocks"\n',
        '    static let superblocksKey = "henge.perf.superblocks"\n'
        '    static let safeStartupKey = "henge.safeStartup.m4"\n')
    replace_once(e,
        '        for (k, v) in env.sorted(by: { $0.key < $1.key }) {\n',
        '        // Conservative startup overrides persisted experimental settings and\n'
        '        // even henge-env.txt; disable this explicitly in Settings to opt out.\n'
        '        if d.object(forKey: safeStartupKey) as? Bool ?? true {\n'
        '            env["HV_SUPERBLOCKS"] = "0"\n'
        '            env["HV_WFI_SPIN"] = "0"\n'
        '        }\n'
        '        for (k, v) in env.sorted(by: { $0.key < $1.key }) {\n')
    m = "ios/Henge/Machines.swift"
    replace_once(m,
        '        let ram = min(UInt64(mac.ramMB), room, reach > 512 ? reach - 512 : 0) / 512 * 512\n'
        '        HengeLog.log("session", "guest RAM \\(ram) MB (asked \\(mac.ramMB), disk room \\(room), largest mapping \\(reach))")\n',
        '        let safe = UserDefaults.standard.object(forKey: EngineTuning.safeStartupKey) as? Bool ?? true\n'
        '        let requested = safe ? min(mac.ramMB, 8192) : mac.ramMB\n'
        '        let ram = min(UInt64(requested), room, reach > 512 ? reach - 512 : 0) / 512 * 512\n'
        '        HengeLog.log("session", "guest RAM \\(ram) MB (asked \\(mac.ramMB), safe \\(safe), disk room \\(room), largest mapping \\(reach))")\n')
    s = "ios/Henge/SessionView.swift"
    replace_once(s,
        '        let rc = henge_vm_boot(mac.rom.path, mac.disk.path, mac.aux.path, mac.ecid, mac.seed, ram, Int32(cpus), &buffer, buffer.count)\n',
        '        // Keep the saved VM CPU setting untouched; only cap this boot.\n'
        '        let safe = UserDefaults.standard.object(forKey: EngineTuning.safeStartupKey) as? Bool ?? true\n'
        '        let bootCPUs = safe ? min(cpus, 4) : cpus\n'
        '        HengeLog.log("session", "M4 conservative startup: safe=\\(safe) cpus=\\(bootCPUs) ram=\\(ram)MB")\n'
        '        let rc = henge_vm_boot(mac.rom.path, mac.disk.path, mac.aux.path, mac.ecid, mac.seed, ram, Int32(bootCPUs), &buffer, buffer.count)\n')
    t = "ios/Henge/SettingsView.swift"
    replace_once(t,
        '    @AppStorage(EngineTuning.superblocksKey) private var superblocks = false\n',
        '    @AppStorage(EngineTuning.superblocksKey) private var superblocks = false\n'
        '    @AppStorage(EngineTuning.safeStartupKey) private var safeStartup = true\n')
    replace_once(t,
        '                Section("Performance") {\n',
        '                Section("Performance") {\n'
        '                    Toggle("Conservative startup (M4)", isOn: $safeStartup)\n'
        '                    Text("When enabled, boot with up to 4 CPUs and 8 GB RAM, with experimental Superblocks and quicker wake disabled. Your saved Mac configuration and disk are unchanged. Turn off to restore your normal performance settings. Applies next boot.")\n'
        '                        .font(.footnote).foregroundStyle(.secondary)\n')
    subprocess.run(["git", "-C", str(ROOT), "diff", "--check"], check=True)
    diff = run("git", "-C", str(ROOT), "diff", "--name-only").splitlines()
    if sorted(diff) != sorted(FILES):
        raise SystemExit(f"Unexpected modified files: {diff}")
    check_source()
    print("PASS: isolated safe startup patch applied to", ", ".join(diff))

def check_source():
    e = (ROOT / FILES[0]).read_text()
    m = (ROOT / FILES[1]).read_text()
    s = (ROOT / FILES[2]).read_text()
    t = (ROOT / FILES[3]).read_text()
    checks = [
        ('safe startup preference', 'henge.safeStartup.m4' in e),
        ('superblocks safely overridden after custom env', e.index('env["HV_SUPERBLOCKS"] = "0"') > e.index('let url = docs.appendingPathComponent("henge-env.txt")')),
        ('idle spin safely disabled', 'env["HV_WFI_SPIN"] = "0"' in e),
        ('RAM limited before allocation', 'safe ? min(mac.ramMB, 8192)' in m),
        ('vCPU cap is transient', 'safe ? min(cpus, 4)' in s),
        ('CPU and RAM boot logged', 'M4 conservative startup:' in s),
        ('user can toggle off', 'Toggle("Conservative startup (M4)"' in t),
    ]
    for name, valid in checks:
        if not valid: raise SystemExit(f"FAIL: {name}")
        print("PASS:", name)

def verify_ipa(ipa_path):
    verify_base()
    check_source()
    ipa_path = Path(ipa_path)
    if not ipa_path.is_file() or ipa_path.stat().st_size < 1000000:
        raise SystemExit("IPA missing or unexpectedly small")
    with zipfile.ZipFile(ipa_path) as z:
        if z.testzip() is not None: raise SystemExit("Invalid IPA archive")
        names = z.namelist()
        for needed in ["Payload/Henge.app/Henge", "Payload/Henge.app/Info.plist"]:
            if needed not in names: raise SystemExit("Missing "+needed)
        info = plistlib.loads(z.read("Payload/Henge.app/Info.plist"))
        if info.get("CFBundleIdentifier") != "com.henge.app":
            raise SystemExit("Bundle identifier changed")
        if 2 not in info.get("UIDeviceFamily", []):
            raise SystemExit("IPA no longer supports iPad")
        app = z.read("Payload/Henge.app/Henge")
        if b'henge.safeStartup.m4' not in app:
            raise SystemExit("Safe startup preference missing from compiled app")
        if b'M4 conservative startup:' not in app:
            raise SystemExit("Safe startup log marker missing from compiled app")
        for part in names:
            name = Path(part).name.lower()
            if name.endswith(('.p12', '.p8', '.pfx', '.mobileprovision')):
                raise SystemExit("Sensitive signing file in IPA: " + part)
    record = {
        "status": "Built; iPad physical boot validation pending",
        "upstream_commit": UPSTREAM_SHA,
        "workflow_commit": os.environ.get("GITHUB_SHA"),
        "run_url": f"{os.environ.get('GITHUB_SERVER_URL', 'https://github.com')}/{os.environ.get('GITHUB_REPOSITORY', 'hazerbvisor/Henge-Custom')}/actions/runs/{os.environ.get('GITHUB_RUN_ID', '')}",
        "ipa_filename": ipa_path.name,
        "ipa_bytes": ipa_path.stat().st_size,
        "ipa_sha256": hashlib.sha256(ipa_path.read_bytes()).hexdigest(),
        "safe_profile": "default ON; max 4 vCPU, max 8GiB RAM, HV_SUPERBLOCKS=0, HV_WFI_SPIN=0",
        "base_safety": "No persistent virtual disk or machine.json edits",
        "signing": "ad-hoc; user must re-sign with appropriate developer certificate",
        "xcode_version": run("xcodebuild", "-version"),
        "source_sha256": {s: hashlib.sha256((ROOT / s).read_bytes()).hexdigest() for s in FILES},
    }
    out = ipa_path.parent / "build-manifest.json"
    out.write_text(json.dumps(record, indent=2)+"\n")
    print(json.dumps(record, indent=2))

if MODE == "patch":
    apply_patch()
elif MODE == "verify":
    if len(sys.argv) < 4: raise SystemExit("verify requires IPA path")
    verify_ipa(sys.argv[3])
else:
    raise SystemExit("Usage: apply_safe_boot.py [patch|verify] Henge [artifacts/Henge-M4-safe.ipa]")

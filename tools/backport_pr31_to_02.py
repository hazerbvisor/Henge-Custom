#!/usr/bin/env python3
"""Minimal backport of upstream Henge PR #31 to the official 0.2 release.

Original: https://github.com/Leviidev/Henge/pull/31
Changes ONLY bdif firmware-disk handling, disk I/O and native regression tests.
VM CPU/RAM/performance settings, aux files and guest disks are not modified.
"""
from pathlib import Path
import subprocess
import sys

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path("Henge").resolve()
BASE = "f9c12c93620af4c4c5f5f65f9793b72f883be682"
FILES = ("devices/bdif.c", "host/disk.c", "tests/test_devices.c")

def change(path, old, new):
    p = ROOT / path
    original = p.read_text()
    count = original.count(old)
    if count != 1:
        raise SystemExit(f"Patch anchor mismatch in {path}: {count} matches: {old[:95]!r}")
    p.write_text(original.replace(old, new, 1))

rev = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
if rev != BASE:
    raise SystemExit(f"Wrong official 0.2 base: got {rev}; expected {BASE}")

change("devices/bdif.c", "#define MAX_LEN (128u << 20)\n", "")
change("devices/bdif.c",
    "        if (devid == DEVID_ROOT) return 0x8000000;\n"
    "        if (devid == DEVID_AUX) return 0x10000;\n",
    "        /* PR #31: return the actual capacity in 512-byte sectors. */\n"
    "        if (devid == DEVID_ROOT) return b->root ? b->root->size / 512 : 0;\n"
    "        if (devid == DEVID_AUX) return b->aux ? b->aux->size / 512 : 0;\n")
change("devices/bdif.c",
    "if (hv_phys_read(b->m, req[0].addr, sector, sizeof sector) == 0 && req[1].len <= MAX_LEN) {",
    "if (hv_phys_read(b->m, req[0].addr, sector, sizeof sector) == 0) {\n"
    "            /* PR #31: accept large firmware assets only with a valid guest RAM buffer. */")

change("host/disk.c", "#include <fcntl.h>\n", "#include <fcntl.h>\n#include <errno.h>\n")
change("host/disk.c", "#include <unistd.h>\n",
    "#include <unistd.h>\n\n/* PR #31: bound individual syscalls, not the guest's total transfer. */\n"
    "#define DISK_IO_CHUNK (128u << 20)\n")
change("host/disk.c",
    "        ssize_t n = pread(d->fd, p, len, (off_t)(d->offset + off));\n"
    "        if (n <= 0) return -1;",
    "        size_t count = len > DISK_IO_CHUNK ? DISK_IO_CHUNK : (size_t)len;\n"
    "        ssize_t n = pread(d->fd, p, count, (off_t)(d->offset + off));\n"
    "        if (n < 0 && errno == EINTR) continue;\n"
    "        if (n <= 0) return -1;")
change("host/disk.c",
    "        ssize_t n = pwrite(d->fd, p, len, (off_t)(d->offset + off));\n"
    "        if (n <= 0) return -1;",
    "        size_t count = len > DISK_IO_CHUNK ? DISK_IO_CHUNK : (size_t)len;\n"
    "        ssize_t n = pwrite(d->fd, p, count, (off_t)(d->offset + off));\n"
    "        if (n < 0 && errno == EINTR) continue;\n"
    "        if (n <= 0) return -1;")

change("tests/test_devices.c", '#define WORK "/Volumes/macOS Storage/husk-work/hengevm"',
       '#define WORK "/tmp" /* CI runner test fixture only */')
change("tests/test_devices.c", "#define RAM_SIZE (64ull << 20)",
       "#define RAM_SIZE (384ull << 20)")

change("tests/test_devices.c",
    '    check("bdif root next-device", rd32(VMAPPLE_BDOOR + 0x420), 0x8000000);',
    '    check("bdif root capacity", rd32(VMAPPLE_BDOOR + 0x420), root->size / 512);\n'
    '    check("bdif aux capacity", rd32(VMAPPLE_BDOOR + 0x10000 + 0x420), aux->size / 512);\n'
    '    uint64_t original_size = root->size;\n'
    '    root->size = 96ull << 30;\n'
    '    check("bdif expanded root capacity", rd32(VMAPPLE_BDOOR + 0x420), (96ull << 30) / 512);\n'
    '    root->size = original_size;')

end_anchor = (
    '        check(which ? "bdif aux data" : "bdif root data", memcmp(ram(data), want, 1024), 0);\n'
    '    }\n'
    '}\n\n/* A small virtio driver, as a guest would do it. */'
)
end_replacement = (
    '        check(which ? "bdif aux data" : "bdif root data", memcmp(ram(data), want, 1024), 0);\n'
    '    }\n'
    '    /* Regression from PR #31: 272 MiB boot asset exceeds old 128 MiB cap. */\n'
    '    const uint32_t large_length = 285216768;\n'
    '    const uint64_t disk_offset = 4ull << 20;\n'
    '    const uint64_t large_data = base + (32ull << 20);\n'
    '    const uint8_t marker = 0xa7;\n'
    '    check("large disk fixture", ftruncate(root->fd, (off_t)(disk_offset + large_length)), 0);\n'
    '    root->size = disk_offset + large_length;\n'
    '    check("large disk first marker", pwrite(root->fd, &marker, 1, (off_t)disk_offset), 1);\n'
    '    check("large disk last marker", pwrite(root->fd, &marker, 1, (off_t)(root->size - 1)), 1);\n'
    '    sector[2] = (uint32_t)(disk_offset / 512);\n'
    '    memcpy(ram(sec), sector, sizeof sector);\n'
    '    memcpy(r + 16, &large_data, sizeof large_data);\n'
    '    memcpy(r + 24, &large_length, sizeof large_length);\n'
    '    memcpy(ram(req), r, sizeof r);\n'
    '    ram(ret)[0] = 0xee;\n'
    '    wr64(VMAPPLE_BDOOR + 0x408, req);\n'
    '    check("firmware asset >128 MiB accepted", ram(ret)[0], 0);\n'
    '    check("firmware asset first byte", ram(large_data)[0], marker);\n'
    '    check("firmware asset last byte", ram(large_data)[large_length - 1], marker);\n'
    '    const uint64_t invalid = base + RAM_SIZE - 1024;\n'
    '    memcpy(r + 16, &invalid, sizeof invalid);\n'
    '    memcpy(ram(req), r, sizeof r);\n'
    '    ram(ret)[0] = 0xee;\n'
    '    wr64(VMAPPLE_BDOOR + 0x408, req);\n'
    '    check("firmware transfer beyond guest RAM rejected", ram(ret)[0], 1);\n'
    '    check("restore disk test fixture", ftruncate(root->fd, (off_t)original_size), 0);\n'
    '    root->size = original_size;\n'
    '}\n\n/* A small virtio driver, as a guest would do it. */'
)
change("tests/test_devices.c", end_anchor, end_replacement)

subprocess.run(["git", "-C", str(ROOT), "diff", "--check"], check=True)
names = subprocess.check_output(["git", "-C", str(ROOT), "diff", "--name-only"], text=True).strip().splitlines()
if names != sorted(FILES):
    raise SystemExit(f"Unexpected changed files: {names} (expected {sorted(FILES)})")
print("PASS: backported official Henge PR #31 to release 0.2")
print("PASS: only firmware disk handling, host disk I/O and native tests changed")
print("PASS: all VM settings remain under original Henge 0.2 controls")

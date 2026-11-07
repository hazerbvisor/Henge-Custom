# Physical mouse compatibility on iPad

This fork provides a configurable workaround for the reported left/middle reversal
on an iPad Air M4 (iPad16,8), iPadOS 27.0.1. It is enabled by default on iPad in this build; iPhones retain the original mapping.
In **Settings > Mouse and Trackpad**, turn **Swap physical left and middle
buttons** off for a mouse or Magic Keyboard trackpad that already works normally.
Changes apply when a Mac session starts; fully close and reopen Henge before
starting another session (Henge supports one guest per launch).

## Investigation and scope

`HardwareMouse` receives named GameController left/right/middle callbacks.
`henge_vm_mouse_button` in `ios/Henge/Native/henge-vm.c` forwards the ID unchanged.
`hv_vm_mouse_button` in `host/vm.c` maps 0/1/2 to Linux BTN_LEFT/RIGHT/MIDDLE
(0x110/0x111/0x112). `devices/virtio_input.c` queues and delivers these codes,
with no further permutation. The on-screen trackpad and click buttons use the
same bridge with the standard IDs. Those files and their mapping are unchanged.

With compatibility on, only GameController button events use 0 -> 2, 1 -> 1,
2 -> 0, for both press and release. The setting is fixed per session and cleanup
releases the mapped IDs. Movement, wheel processing and pointer-lock requests are
unchanged. GameController also supplies external trackpads, so the setting covers
those devices too. It is a global preference, not per-mouse auto-detection.

The pipeline uses standard codes. Source inspection cannot establish why the
reported hardware/OS/guest combination reverses them, or whether other mice do.
This is a compatibility workaround, not a proven universal driver correction.

The log records the mouse vendor, selected mapping, the first 32 button events
(raw ID, mapped ID, down/up), and cleanup releases. Existing pointer-lock and
scroll diagnostics remain. Share it from **Settings > Log > Share henge.log**.

## Automated verification and build

`ios/scripts/check_mouse_buttons.sh` compiles the actual Swift routing state
machine on macOS and tests swapped drag press/release, unchanged right-click,
standard opt-out, invalid input and disconnect/background cleanup.
The manual `.github/workflows/ios-development-ipa.yml` workflow checks out the
fork commit (the workflow commit by default), runs these tests, builds pinned Husk
networking/pairing dependencies, and uses Henge's official packaging scripts.
Husk supplies its official vendored StikJIT XCFramework.

Validation requires the avp-ctrr ancestor and compiled binary marker, the mouse
setting and diagnostics in the binary, all three mouse Swift sources in the
compiler log, unchanged shared input files, the app and JIT extension, StikJIT,
JIT resources, original IDs and entitlements, ARM64 code and valid ad-hoc bundle
signatures. Firmware, restore images and provisioning profiles are rejected.
`build-manifest.json` records source commits, mouse source hashes and IPA SHA256.
No Apple credentials are required. Re-sign `Henge-M4-MouseFix.ipa` and its nested
bundles together using your development certificate and supported entitlements.

## Physical-device acceptance tests (not yet performed)

1. Sign and install the IPA; confirm Settings shows the swap enabled. Enable JIT
   using the built-in helper and start the guest with the physical mouse attached.
2. In Finder, left-click selects, double left-click opens, and a left-button drag
   moves an item without releasing early or remaining held after release.
3. Right-click opens the context menu. In Safari, left-click follows a link and
   middle-click opens a link in a background tab (subject to Safari preferences).
   Check the same buttons in Roblox and another application.
4. Move in both axes, scroll vertically and horizontally where supported, and
   check pointer lock keeps the iPad pointer out of the guest. Test keyboard input.
5. Hold left, then disconnect the mouse; reconnect and confirm nothing is stuck.
   Repeat while switching away from Henge and returning. Check right-button drag
   or camera movement in Roblox and simultaneous button holds if supported.
6. Use the on-screen trackpad: tap, hold-drag, two-finger right-click and scroll.
   Test the on-screen Click and Right-click buttons; these should behave as before.
7. Turn the compatibility toggle off, fully close/reopen Henge and start a session.
   Confirm the original mapping returns. Try another mouse or Magic Keyboard
   trackpad and retain whichever setting makes left/middle/right behave normally.
8. Export `henge.log` after a short test. With swap on, raw 0 should show guest 2,
   raw 2 guest 0, and raw 1 guest 1, with paired down/up events. Include mouse model,
   connection type and selected setting if reporting a remaining issue.

A successful build and bundle validation do not verify physical click behavior,
KravaSign entitlement grants, pointer lock or guest restoration on real hardware.

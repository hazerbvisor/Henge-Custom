#!/bin/bash
# Runs the same physical-button state machine compiled into the iOS application.
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/mouse-check
xcrun --sdk macosx swiftc -swift-version 5 -O \
  ios/Henge/PhysicalMouseButtons.swift tests/test_physical_mouse_buttons.swift \
  -o build/mouse-check/test-physical-mouse
build/mouse-check/test-physical-mouse

# CLAUDE.md

## Project

Swift macOS menu bar app controlling DPI on a Logitech G402 Hyperion Fury mouse via HID++ 2.0 over USB. Replaces Logitech G Hub.

## Build & Run

```bash
# Build everything (main app + CLI smoke test)
swift build

# Build release
swift build -c release

# Run the main app (menu bar)
.build/release/G402DPIController

# Run CLI smoke test (HID++ debugging)
swift build --product CLISmokeTest
.build/debug/CLISmokeTest
```

## Key Conventions

- The main app and CLISmokeTest must stay in sync — any changes to HID++ protocol handling, DPI logic, or tolerance values should be reflected in both targets.
- DPI values are queried at runtime from the hardware via `getSensorDpiList` (HID++ feature 0x2201, function 1). Hardcoded values in `G402DPI` are fallback only.
- User-facing preset labels (400, 800, 1200, 1600, 3200) are friendly display values — actual hardware DPI is snapped to the nearest valid value via `SensorDPICapabilities.snap()`.

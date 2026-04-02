# G402 DPI Controller

A lightweight SwiftUI menu bar app that controls DPI on the Logitech G402 Hyperion Fury mouse. Replaces Logitech G Hub (~200MB Electron app) with a <1MB native macOS app.

## Why

Logitech G Hub has a bug where mouse DPI resets to the onboard default after screen lock/unlock. The root cause: the G402 boots into **onboard mode** on every USB re-enumeration (which happens during sleep/wake), and G Hub's `onDpiRestoreTuning` fails to switch back to **host mode**.

This app explicitly switches to host mode and re-applies your preferred DPI on every connect and wake/unlock event.

## Requirements

- macOS 15.0 (Sequoia) or later
- Logitech G402 Hyperion Fury (wired USB)
- Xcode Command Line Tools or Xcode (for building)

## Build & Install

```bash
# Clone and build
cd ~/Developer/G402DPIController
swift build -c release

# Copy to Applications
cp -r .build/release/G402DPIController /usr/local/bin/
# Or create an app bundle (see below)
```

### Quick start (run from terminal)

```bash
swift build -c release
.build/release/G402DPIController
```

### Run as a proper app bundle

To get a dock-less menu bar app with proper icon:

```bash
# Build release
swift build -c release

# Create app bundle
mkdir -p ~/Applications/G402DPIController.app/Contents/MacOS
cp .build/release/G402DPIController ~/Applications/G402DPIController.app/Contents/MacOS/
cp G402DPIController/App/Info.plist ~/Applications/G402DPIController.app/Contents/
```

Then open `~/Applications/G402DPIController.app`.

## Permissions

On first launch, macOS will prompt for **Input Monitoring** permission:

1. Go to **System Settings > Privacy & Security > Input Monitoring**
2. Enable the toggle for `G402DPIController` (or your terminal app if running from terminal)

This is required because IOKit HID device access needs TCC authorization on macOS 15+.

## Uninstalling Logitech G Hub

Before uninstalling G Hub, make sure this app is working correctly.

```bash
# 1. Quit G Hub
killall lghub_agent lghub_system_tray lghub_ui 2>/dev/null

# 2. Remove G Hub's HID filter system extension (if still active)
systemextensionsctl list  # Check if com.logi.ghub.hidfilter is listed
# If present and active:
# Go to System Settings > General > Login Items & Extensions > Driver Extensions
# and disable "Logitech G HUB HID Driver Extension"

# 3. Remove the app
sudo rm -rf /Applications/lghub.app

# 4. Remove launch agents/daemons
sudo rm -f /Library/LaunchAgents/com.logi.ghub.plist
sudo rm -f /Library/LaunchDaemons/com.logi.ghub.updater.plist

# 5. Remove user data (optional — only if you don't plan to reinstall)
rm -rf ~/Library/Application\ Support/LGHUB
rm -f ~/Library/Preferences/com.logi.ghub.plist
rm -f ~/Library/Preferences/com.logi.ghub.ui.plist

# 6. Remove system-level device configs (optional)
sudo rm -rf /Library/Application\ Support/Logi/LGHUB
```

## Usage

The app runs as a menu bar icon:

- **Mouse icon** when disconnected, **"DPI: 1596"** when connected
- Click to open the popover:
  - Connection status indicator
  - Current DPI readout
  - Preset buttons: 400, 800, 1200, 1600, 3200
  - Custom DPI slider (300–4000)
  - Toggle: Restore DPI on wake/unlock
  - Toggle: Launch at login
  - Quit

The app automatically:
- Switches the mouse from onboard to host mode on connect
- Sets your preferred DPI
- Re-applies DPI after wake from sleep, screen unlock, and screensaver exit

> **Note:** The G402 rounds DPI to its hardware step (~12 DPI). So 1600 becomes 1596. This is normal.

## Architecture

```
SwiftUI MenuBarExtra  →  HIDPlusPlusManager (IOKit)  →  G402 USB HID++ 2.0
```

The app talks directly to the mouse over USB using Logitech's HID++ 2.0 protocol via IOKit's `IOHIDManager`. No kernel extensions or drivers needed.

Key files:
- `HID/HIDPlusPlusProtocol.swift` — HID++ 2.0 message framing
- `HID/HIDPlusPlusManager.swift` — IOKit device lifecycle, host mode switching, DPI commands
- `Services/WakeEventService.swift` — wake/unlock/screensaver event handling
- `App/G402DPIControllerApp.swift` — SwiftUI MenuBarExtra entry point

## CLI Smoke Test

A standalone CLI tool is included for debugging HID++ communication:

```bash
swift build --product CLISmokeTest
.build/debug/CLISmokeTest
```

This will: discover HID++ features, switch to host mode, read current DPI, set DPI to 1600, and read back to verify.

## License

MIT

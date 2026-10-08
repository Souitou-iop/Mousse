# Mousse

<p align="center">
  <b>A lightweight, single-process menu bar mouse utility for macOS.</b>
</p>

<p align="center">
  <a href="https://github.com/Souitou-iop/Mousse/releases/latest"><img src="https://img.shields.io/github/v/release/Souitou-iop/Mousse?color=blue&label=Release" alt="Release"></a>
  <a href="LICENSE.md"><img src="https://img.shields.io/badge/License-PolyForm%20Noncommercial%201.0.0-green.svg" alt="License"></a>
  <img src="https://img.shields.io/badge/Platform-macOS%2026%2B%20%7C%20Apple%20Silicon-orange.svg" alt="Platform">
  <img src="https://img.shields.io/badge/Language-Swift%206-F05138.svg" alt="Swift">
</p>

<p align="center">
  <b>English</b> | <a href="README_zh.md">简体中文</a> | <a href="README_ja.md">日本語</a>
</p>

---

**Mousse** is a lightweight, single-process menu bar utility for Macs running macOS 14 or later — Apple silicon and Intel both supported. It brings essential mouse enhancements to standard USB and Bluetooth mice — smooth scrolling, customizable button remapping, pointer acceleration management, Windows-style auto-scrolling, and Space-switching gestures — without background helper daemons, license servers, or system configuration tampering.

> [!NOTE]
> This repository is an enhanced fork of the original [Mousse](https://github.com/MinhQuang28/Mousse) created by **Ha Minh Quang ([@MinhQuang28](https://github.com/MinhQuang28))**.

---

## ✨ Key Enhancements in This Fork

Compared to the upstream project, this fork adds significant capabilities, performance improvements, and interface polish:

- 🎯 **Pointer Control & Acceleration Management**:
  - Independent toggle for macOS mouse acceleration (enable/disable without affecting trackpad).
  - Fine-grained pointer speed multiplier (`0.25× – 4.0×`).
  - **Per-app overrides**: Frontmost apps can inherit, enable, or disable acceleration and apply dedicated speed multipliers.
  - Live pointer diagnostics and graceful handling of external system changes without fighting system settings.
- 🧭 **Windows-Style Auto-Scroll & Edge Scrolling**:
  - **Continuous Auto-Scroll**: Enter mode via any mouse button (Middle-Click, side buttons, etc.) and move the cursor away from the anchor point to scroll continuously with 120 Hz spring smoothing and sub-pixel dispatch.
  - **Pointer Anchor Locking**: Keeps the synthetic scroll target anchored, allowing infinite, seamless scrolling in nested scroll panes (e.g. AI chat dialogs, sidebars, code editors).
  - **Single-Process HUD Indicator**: Smooth, transparent floating indicator rotating with pointer direction and refresh-rate sync (can be toggled in settings).
  - **Screen Edge Scrolling**: Hovering at the top or bottom screen edge smoothly scrolls the active window.
- 🖲️ **Expanded Button Triggers & Actions**:
  - **Multi-Trigger Recognition**: Configure **Single Click**, **Double Click** (100–500 ms interval), and **Long Press** (100–800 ms duration) per button.
  - **Smart Navigation**: Native history commands for Safari and Finder (`⌘[` / `⌘]`), standard Button 4/5 for Chromium browsers, and simulated Navigation Swipe for Apple apps.
  - **Rich Action Presets**: Spotlight Search, Siri, App Switcher (`⌘+Tab`), Smart Zoom (equivalent to trackpad 2-finger double tap), Middle-Click simulation, and custom `.app` launching.
  - **Hold-and-Scroll Volume Control**: Hold a button while scrolling the wheel to adjust volume up/down, working independently per button.
- 📜 **Refined Scrolling & Independent Zoom**:
  - **Independent Pinch-to-Zoom Speed**: `⌘ + Wheel` zoom sensitivity (`0.2× – 6.0×`) is decoupled from general scroll speed.
  - **Per-App Scroll Exceptions**: Separately enable/disable Mousse scrolling optimization and reverse scrolling for specific applications (e.g. Parallels Desktop VM passthrough).
  - **Stall-Free Smooth Scrolling**: Removed reversal brakes and transitioned to continuous phase-free event streams.
- 🌌 **Space Dragging with Pointer Freeze**:
  - Locks the pointer in place during drag-to-switch-Spaces gestures, preventing the cursor from wandering off-screen.
- 🔍 **Diagnostics Center & Configuration Management**:
  - Real-time Diagnostics panel in General settings: monitors Accessibility permissions, event-tap health, recovery counts, connected mice, frontmost app resolution, and pointer HID state.
  - **JSON Config Export & Import**: Backup, migrate, or share configurations with strict schema validation.
- 🌐 **Multilingual & Modern macOS Interface**:
  - 5 UI languages supported: **English**, **Simplified Chinese (简体中文)**, **Japanese (日本語)**, **Korean (한국어)**, and **Spanish (Español)**.
  - Dock-aware Settings window with minimize support, organized into 5 intuitive tabs: **General**, **Buttons**, **Scroll**, **Pointer**, and **Gestures**.
  - Adaptive system appearance: native styling on macOS 14 / 15, Liquid Glass on macOS 26+.

---

## Scroll modes, devices and compatibility

- **Native** keeps the original wheel event and applies only device/global vertical and horizontal reversal. It does not run Mousse wheel speed gain, smoothing, Cmd zoom, Shift/Option/Control enhancements, or ordinary per-app direction/transposition rules. Trackpad phased scrolling and safety bypasses stay untouched. Explicit button mappings, auto/edge scrolling and held-button wheel volume controls remain available.
- **Standard** remains the existing mode; old `standard` and `smoothScroll:false` configs are not migrated to Native. **Smooth** supports smoothness and acceleration; **Smooth-step** sets normal notch distance with **Lines per notch**.
- Every non-Native mode exposes speed and Cmd zoom speed. In Standard and Smooth-step, speed adjusts **high-resolution wheel gain**, not normal notched-wheel distance (macOS controls Standard notches; Lines per notch controls Smooth-step). High-resolution smoothing is available only in Smooth/Smooth-step. Inactive controls are hidden without discarding their saved values.
- The Devices tab creates a profile from current global scroll settings, edits offline profiles, and removes profiles. Profiles use USB/Bluetooth `vendor:product`; identical models share a profile. HID and CGEvent delivery are unordered, so the **first scroll event after changing mice may use the previous device's settings**.
- Normal-mode precedence, from lowest to highest: **device/global base → explicit app override → hard safety passthrough**. App overrides control direction and whether Mousse enhancements run; terminals stay hard passthrough, iPhone Mirroring keeps its original event, and configured remote-desktop/game bypasses remain authoritative. Native ignores ordinary app overrides, not these safety rules.
- Device attribution requires **Input Monitoring**. Without attribution the base resolver falls back to global settings; the existing permission gate can also suspend processing. The tracker runs for `(enabled && profiles exist) || Devices tab is actually visible`: the page can discover mice even while Mousse is disabled. Tab switching, window close/minimize/hide and App Hide release UI demand; pending permission retries stop when no demand remains. Permission recovery retries while needed, without requiring an app restart.
- Switching scroll contexts clears the previous context's inertia and not-yet-executed queued zoom tasks. A down/up pair already admitted for execution must finish; cancellation does not retract it.

These are source-level changes with automated regression coverage, **not proof of real HID switching, wake recovery, iPhone Mirroring or long-duration memory stability**. Those require separate runtime acceptance.

## 📸 Screenshots

<p align="center">
  <img src="docs/screenshots/buttons_en.png" alt="Buttons Tab" width="23%" />
  <img src="docs/screenshots/scroll_en.png" alt="Scroll Tab" width="23%" />
  <img src="docs/screenshots/pointer_en.png" alt="Pointer Tab" width="23%" />
  <img src="docs/screenshots/devices_en.png" alt="Devices settings preview" width="23%" />
</p>
<p align="center">
  <i>Buttons Mapping • Scroll & Enhancements • Pointer Control • Devices</i>
</p>

> Source-rendered settings content previews (without native window toolbar) from isolated XCTest + NSHostingView/AppKit. Device names/data are examples; these are not live HID acceptance screenshots. Rendering uses disabled temporary configuration and a fake tracker, without starting the full app or its event tap.

---

## 📥 Requirements & Installation

### Requirements
- Apple silicon (`arm64`) or Intel (`x86_64`) Mac.
- macOS 14.0 or later.
- **Accessibility Permission** (System Settings → Privacy & Security → Accessibility).

Releases ship one archive per architecture — `Mousse-<version>-arm64.zip` and `Mousse-<version>-x86_64.zip`. Check which one you need under the Apple menu → **About This Mac** (Chip / Processor); the wrong slice refuses to launch.

> [!NOTE]
> System-version differences: closing Mission Control / App Exposé by dragging back in the natural direction needs macOS 26+, where the overlay state is detectable; on macOS 14 / 15 vertical drags keep the plain one-step toggle. Everything else — smooth scrolling, button remapping, pointer acceleration, auto-scroll, follow-finger Space switching and synthesized pinch zoom — behaves identically. Intel coverage is new in this release and the pointer-takeover IOHID path has not been accepted on real Intel hardware yet.

### Option 1: Download Pre-Built App (Recommended)
1. Download `Mousse-<version>-arm64.zip` or `Mousse-<version>-x86_64.zip`, matching your Mac, from [Latest Releases](https://github.com/Souitou-iop/Mousse/releases/latest).
2. Unzip and drag `Mousse.app` into your `/Applications` folder.
3. Remove the Gatekeeper quarantine attribute (since the binary uses local signing):
   ```sh
   xattr -dr com.apple.quarantine /Applications/Mousse.app
   ```
4. Launch `Mousse.app` and grant Accessibility permission when prompted.

### Option 2: Build from Source
Requires Xcode Swift toolchain:
```sh
# Setup a stable local signing identity (prevents repeated Accessibility prompts)
tools/setup-signing-cert.sh

# Build one bundle per architecture: build/Mousse-arm64.app and build/Mousse-x86_64.app
./build-app.sh

# Launch the app (pick the bundle matching your Mac)
open build/Mousse-arm64.app
```

---

## ⚙️ Configuration & Features Overview

Launch Mousse to access the menu bar icon. Press `⌘,` to open Settings:

| Tab | Key Capabilities |
| :--- | :--- |
| **General** | Launch at login, UI language switch, Live Diagnostics Center, JSON Config Export/Import. |
| **Buttons** | Capture mouse buttons, configure Single / Double / Long-press triggers, map to Shortcuts, Presets (Spotlight, Siri, App Switcher, Smart Zoom, Middle Click), Launch App, or Volume Control. |
| **Scroll** | Styles (Native, Standard, Smooth, Smooth-step), Speed & Direction (Invert, Zoom speed), Enhancements (Auto-scroll speed/HUD, Edge scroll, High-res smoothing), Modifier keys, Per-app scroll exceptions. |
| **Pointer** | Manage macOS mouse acceleration, Pointer speed multiplier (`0.25× – 4×`), Per-app acceleration & speed overrides, live HID diagnostics. |
| **Devices** | Per-model scroll profiles, independent axes, connected/offline editors, global fallback. |
| **Gestures** | Drag to switch Space, drag distance threshold, Pointer freeze during drag. |

---

## 🤖 CLI for Agents

Mousse includes a local, JSON-producing CLI for scripts and AI agents. The app must already be running; the CLI does not launch a second instance. Typical commands are:

```sh
Mousse status
Mousse diagnostics
Mousse get scrollMode
Mousse set scrollMode smooth
Mousse set scrollSpeed 0.5
```

Agents should check both the process exit code and the JSON `ok` field. `Mousse help` prints the current command and configuration-key contract. See the dedicated [CLI for Agents guide](docs/cli-for-agents.md) for the workflow, supported values, protocol, and safety rules.

## 🛠 Development

```sh
# Run all unit tests
swift test

# Build and package a local release zip with sha256 checksums
tools/package-release.sh
```

---

## 🙏 Acknowledgments & Credits

- **[Ha Minh Quang (@MinhQuang28)](https://github.com/MinhQuang28)** — Original author and creator of [Mousse](https://github.com/MinhQuang28/Mousse). Sincere thanks for the clean single-process architecture, lightweight Swift event-tap foundation, and initial smooth scroll and Space gesture implementations.
- **[Noah Nuebling (@noah-nuebling)](https://github.com/noah-nuebling)** — Creator of [Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix), whose `TouchSimulator` (Navigation Swipe) and `PointerFreeze` concepts provided valuable inspiration and architectural reference.

---

## 📄 License

Mousse is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE.md):
- ✅ Free for personal, non-commercial use, reading, modifying, compiling, and sharing.
- ❌ Commercial use is prohibited without a separate license from the author.

Copyright © Ha Minh Quang & Contributors.

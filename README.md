# Mousse

<p align="center">
  <b>A lightweight, single-process menu bar mouse utility for macOS.</b><br>
  <b>面向 Apple 芯片 Mac 与 macOS 15+ 的轻量级、单进程菜单栏鼠标增强工具。</b>
</p>

<p align="center">
  <a href="https://github.com/Souitou-iop/Mousse/releases/latest"><img src="https://img.shields.io/github/v/release/Souitou-iop/Mousse?color=blue&label=Release" alt="Release"></a>
  <a href="LICENSE.md"><img src="https://img.shields.io/badge/License-PolyForm%20Noncommercial%201.0.0-green.svg" alt="License"></a>
  <img src="https://img.shields.io/badge/Platform-macOS%2015%2B%20%7C%20Apple%20Silicon-orange.svg" alt="Platform">
  <img src="https://img.shields.io/badge/Language-Swift%206-F05138.svg" alt="Swift">
</p>

<p align="center">
  <a href="#english">English</a> • <a href="#简体中文">简体中文</a>
</p>

---

<a name="english"></a>
## English

**Mousse** is a lightweight, single-process menu bar utility for Apple Silicon Macs running macOS 15+ (Sequoia and later). It brings essential mouse enhancements to standard USB and Bluetooth mice — smooth scrolling, customizable button remapping, pointer acceleration management, Windows-style auto-scrolling, and Space-switching gestures — without background helper daemons, license servers, or system configuration tampering.

> [!NOTE]
> This repository is an enhanced fork of the original [Mousse](https://github.com/MinhQuang28/Mousse) created by **Ha Minh Quang ([@MinhQuang28](https://github.com/MinhQuang28))**.

---

### ✨ Key Enhancements in This Fork

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
  - Adaptive system appearance on macOS 15 through macOS 26+.

---

### 📥 Requirements & Installation

#### Requirements
- Apple Silicon Mac (`arm64`).
- macOS 15.0 (Sequoia) or later.
- **Accessibility Permission** (System Settings → Privacy & Security → Accessibility).

#### Option 1: Download Pre-Built App (Recommended)
1. Download `Mousse.zip` from [Latest Releases](https://github.com/Souitou-iop/Mousse/releases/latest).
2. Unzip and drag `Mousse.app` into your `/Applications` folder.
3. Remove the Gatekeeper quarantine attribute (since the binary uses local signing):
   ```sh
   xattr -dr com.apple.quarantine /Applications/Mousse.app
   ```
4. Launch `Mousse.app` and grant Accessibility permission when prompted.

#### Option 2: Build from Source
Requires Xcode Swift toolchain:
```sh
# Setup a stable local signing identity (prevents repeated Accessibility prompts)
tools/setup-signing-cert.sh

# Build the application bundle into build/Mousse.app
./build-app.sh

# Launch the app
open build/Mousse.app
```

---

### ⚙️ Configuration & Features Overview

Launch Mousse to access the menu bar icon. Press `⌘,` to open Settings:

| Tab | Key Capabilities |
| :--- | :--- |
| **General (常规)** | Launch at login, UI language switch, Live Diagnostics Center, JSON Config Export/Import. |
| **Buttons (按钮)** | Capture mouse buttons, configure Single / Double / Long-press triggers, map to Shortcuts, Presets (Spotlight, Siri, App Switcher, Smart Zoom, Middle Click), Launch App, or Volume Control. |
| **Scroll (滚动)** | Styles (Standard, Smooth, Smooth-step), Speed & Direction (Invert, Zoom speed), Enhancements (Auto-scroll speed/HUD, Edge scroll, High-res smoothing), Modifier keys, Per-app scroll exceptions. |
| **Pointer (指针)** | Manage macOS mouse acceleration, Pointer speed multiplier (`0.25× – 4×`), Per-app acceleration & speed overrides, live HID diagnostics. |
| **Gestures (手势)** | Drag to switch Space, drag distance threshold, Pointer freeze during drag. |

---

### 🛠 Development

```sh
# Run all unit tests (190+ test cases)
swift test

# Build and package a local release zip with sha256 checksums
tools/package-release.sh
```

---

### 🙏 Acknowledgments & Credits

- **[Ha Minh Quang (@MinhQuang28)](https://github.com/MinhQuang28)** — Original author and creator of [Mousse](https://github.com/MinhQuang28/Mousse). Sincere thanks for the clean single-process architecture, lightweight Swift event-tap foundation, and initial smooth scroll and Space gesture implementations.
- **[Noah Nuebling (@noah-nuebling)](https://github.com/noah-nuebling)** — Creator of [Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix), whose `TouchSimulator` (Navigation Swipe) and `PointerFreeze` concepts provided valuable inspiration and architectural reference.

---

### 📄 License

Mousse is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE.md):
- ✅ Free for personal, non-commercial use, reading, modifying, compiling, and sharing.
- ❌ Commercial use is prohibited without a separate license from the author.

Copyright © Ha Minh Quang & Contributors.

---

<a name="简体中文"></a>
## 简体中文

**Mousse** 是一款专为 Apple 芯片 Mac 与 macOS 15+（Sequoia 及后续版本）设计的轻量级、单进程菜单栏鼠标增强工具。它为普通 USB 和蓝牙鼠标补齐了 macOS 原生缺失的核心体验：平滑滚动、按键动作重映射、指针加速度接管、Windows 风格自动滚动以及拖拽切换 Space 手势，且**无需后台常驻 Daemon 辅助进程、无需许可证联网验证、无需破坏性修改系统底层配置**。

> [!NOTE]
> 本仓库为 **Ha Minh Quang ([@MinhQuang28](https://github.com/MinhQuang28))** 原项目 [Mousse](https://github.com/MinhQuang28/Mousse) 的增强 Fork 版本。

---

### ✨ 本 Fork 核心增强特性

相比原版项目，本 Fork 进行了大量深度重构与功能拓展：

- 🎯 **指针控制与加速度管理**：
  - **独立加速度开关**：可单独开启或关闭 macOS 鼠标加速度（消除鼠标飘浮感，且不影响触控板）。
  - **指针速度倍率**：支持 `0.25× – 4.0×` 精细速度调节。
  - **按应用独立覆盖**：可按当前前台应用单独继承、开启或关闭加速度，并设置专属速度倍率。
  - **系统设置协调与诊断**：实时检测 HID 状态变化与外部漂移，自动同步基准而不反复抢写冲突。
- 🧭 **Windows 风格自动滚动与边缘滚动**：
  - **原生级自动滚动**：通过中键或任意鼠标按键触发，光标偏离锚点即可驱动页面持续滚动；采用 120 Hz 弹簧平滑与子像素渲染，丝滑流畅。
  - **指针锚定机制**：进入自动滚动时锁定事件派发锚点，完美解决 AI 对话框、侧边栏、代码编辑器等嵌套滚动区域移出失效的问题。
  - **单进程 HUD 指示器**：低侵入半透明光标 HUD，跟随鼠标方向平滑旋转并实时指示滚动强度（支持在设置中关闭）。
  - **屏幕边缘滚动**：光标悬停在屏幕顶部或底部边缘时自动平滑滚动当前窗口。
- 🖲️ **丰富按键触发与动作映射**：
  - **多触发机制**：每个按键均可独立分配**单击**、**双击**（100–500 ms 判定）与**长按**（100–800 ms 判定）。
  - **智能前进/后退**：Safari 与 Finder 采用原生历史快捷键（`⌘[` / `⌘]`），Chromium 浏览器发送标准 Button 4/5，Apple 原生应用触发 Navigation Swipe 滑动手势。
  - **丰富系统级预设**：支持聚焦搜索（Spotlight）、Siri、应用切换器（`⌘+Tab`）、智能缩放（等价触控板双指双击）、模拟中键点击等。
  - **启动任意应用**：按键动作可绑定启动任意指定的 `.app`。
  - **按住滚动调整音量**：长按指定按键并滚动滚轮即可快速增减音量，且支持按按键独立生效。
- 📜 **精细化滚动与独立缩放**：
  - **独立缩放速度**：`⌘ + 滚轮` 缩放灵敏度（`0.2× – 6.0×`）与普通滚动速度解耦，可独立调节。
  - **按应用例外控制**：每个应用可独立控制是否启用 Mousse 滚动优化与反向滚动（例如在 Parallels 虚拟机中直通原生事件）。
  - **彻底告别滚动卡顿**：移除反向刹车限制，采用无相位连续事件流，杜绝页面中途卡顿。
- 🌌 **Space 拖拽手势增强**：
  - 拖拽切换 Space 期间支持**光标原地锁定（Pointer Freeze）**，避免手势操作时光标移出屏幕可视范围。
- 🔍 **诊断中心与配置导入导出**：
  - 常规页面内置**实时诊断面板**，一览辅助功能权限、事件监听健康度、已连接鼠标数、前台应用以及指针 HID 状态。
  - **配置 JSON 导入/导出**：方便备份、跨机迁移与分享，具备严格的格式校验。
- 🌐 **五国语言与现代 macOS 外观**：
  - 支持 **简体中文**、**English**、**日本語**、**한국어**、**Español**（随系统自动切换或手动指定）。
  - 打开设置时显示 Dock 图标并支持窗口最小化，关闭后自动退出 Dock 恢复纯菜单栏模式；界面划分为**常规**、**按钮**、**滚动**、**指针**、**手势** 5 大页面。
  - 完美适配 macOS 15 (Sequoia) 及 macOS 26+ 系统新外观。

---

### 📥 系统要求与安装

#### 系统要求
- Apple 芯片 Mac（`arm64`）。
- macOS 15.0 (Sequoia) 或更高版本。
- **辅助功能权限**（系统设置 → 隐私与安全性 → 辅助功能）。

#### 方式一：下载预构建应用（推荐）
1. 从 [最新发布页面](https://github.com/Souitou-iop/Mousse/releases/latest) 下载 `Mousse.zip`。
2. 解压并将 `Mousse.app` 拖入 **应用程序 (Applications)** 文件夹。
3. 移除 macOS Gatekeeper 隔离标记（由于采用本地签名）：
   ```sh
   xattr -dr com.apple.quarantine /Applications/Mousse.app
   ```
4. 运行 `Mousse.app` 并在弹出提示中授予辅助功能权限。

#### 方式二：从源码编译
需要 Xcode Swift 工具链：
```sh
# 创建本地稳定签名证书（避免重新编译后重复提示授权辅助功能）
tools/setup-signing-cert.sh

# 编译应用包至 build/Mousse.app
./build-app.sh

# 启动应用
open build/Mousse.app
```

---

### ⚙️ 设置与功能页面一览

启动 Mousse 后点击菜单栏图标，或按下快捷键 `⌘,` 打开设置窗口：

| 标签页 | 核心功能 |
| :--- | :--- |
| **常规 (General)** | 登录时启动、界面语言切换、实时诊断面板、配置 JSON 导入与导出。 |
| **按钮 (Buttons)** | 捕获鼠标物理按键，配置单击 / 双击 / 长按触发方式，映射为自定义快捷键、系统预设（聚焦搜索、Siri、应用切换器、智能缩放、模拟中键）、打开指定 App 或滚动调音量。 |
| **滚动 (Scroll)** | 滚动模式（标准、平滑、平滑步进）、滚动速度与反转、⌘+滚轮缩放速度、自动滚动参数与 HUD 开关、边缘滚动、高分辨率鼠标平滑、按应用例外。 |
| **指针 (Pointer)** | macOS 鼠标加速度接管、全局指针速度倍率（`0.25×–4×`）、按前台应用独立覆盖加速与速度、HID 状态诊断。 |
| **手势 (Gestures)** | 按住按键拖拽切换 Space、切换灵敏度距离设定、拖拽期间锁定鼠标指针。 |

---

### 🛠 本地开发与测试

```sh
# 执行完整单元测试套件（包含 190+ 测试用例）
swift test

# 打包本地 Release 发布包并生成 sha256 校验和
tools/package-release.sh
```

---

### 🙏 致谢与致敬

- **[Ha Minh Quang (@MinhQuang28)](https://github.com/MinhQuang28)** — [Mousse](https://github.com/MinhQuang28/Mousse) 原项目的创作者与原作者。衷心感谢其构建的优雅单进程架构、轻量级 Swift Event Tap 事件基础以及初代平滑滚动与手势实现。
- **[Noah Nuebling (@noah-nuebling)](https://github.com/noah-nuebling)** — [Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix) 的创作者，其 `TouchSimulator`（Navigation Swipe 导航手势）与 `PointerFreeze` 设计思想为本项目的相关实现提供了重要的启发与参考。

---

### 📄 许可证

Mousse 遵循 [PolyForm Noncommercial License 1.0.0](LICENSE.md) 协议开源：
- ✅ 允许个人非商业使用、学习源码、修改代码、自行编译及免费分享。
- ❌ 未经原作者许可，严禁用于任何商业产品、销售或收费服务。

Copyright © Ha Minh Quang 与贡献者。

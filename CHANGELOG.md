# 更新日志 / Changelog

本项目遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。本文件同时提供中文与英文条目 / This file is bilingual.

## [0.26.0] - 2026-08-18

### 改进 / Improved

- **滚动与手势设置页面折叠排版优化**：重构“滚动”与“手势”设置页面，将高级增强功能（边缘滚动、自动滚动参数、高分辨率平滑）与应用例外列表（排除应用、横纵轴交换、远程桌面直通）统一收纳在轻量折叠面板（`DisclosureGroup`）中。默认视图大幅缩短页面垂直高度达 60% 以上，让核心样式与速度调节一览无余，显著提升交互体验。
- **Collapsible settings layout for scroll and gestures**: restructured the Scroll and Gestures preference panes by organizing advanced enhancements (edge scroll, auto-scroll parameters, high-res smoothing) and application exception lists (exclusions, axis swaps, remote desktop passthrough) into elegant collapsible disclosure groups. Reduces default vertical scroll length by over 60% while keeping core adjustments front and center.
- **预置应用纯净初始化**：清空远程桌面和游戏避让的内置预设列表，默认配置保持纯净，完全由用户按需添加自定义 App。
- **Clean default application lists**: set default lists for remote desktop and game bypasses to empty arrays, keeping initial configuration minimal and purely user-driven.

[0.26.0]: https://github.com/Souitou-iop/Mousse/releases/tag/v0.26.0

## [0.25.0] - 2026-08-18

### 新增 / Added

- **远程桌面与虚拟机原生直通**：新增独立开关与可自定义应用列表，内置支持 Microsoft Remote Desktop、Parsec、Moonlight、Parallels、VMware Fusion、TeamViewer、AnyDesk 等应用；处于列表内应用时，自动绕过像素平滑与手势拦截，以 1:1 原生 Notch 方式直通宿主系统，消除双重阻尼与惯性漂移。
- **Remote desktop & VM passthrough**: added a dedicated toggle and customizable application list supporting Microsoft Remote Desktop, Parsec, Moonlight, Parallels, VMware Fusion, TeamViewer, AnyDesk, and others; automatically bypasses pixel smoothing and gesture interception over listed apps for 1:1 native scroll delivery.
- **游戏全屏与光标避让**：新增独立开关与自定义游戏列表，当处于游戏内时自动挂起 SpaceDrag 手势与指针控制，防止 3D/FPS 游戏中拖拽手势对视角旋转造成干扰。
- **Gaming & cursor auto-bypass**: added a dedicated toggle and customizable game list, automatically suspending SpaceDrag gestures and pointer overrides in games to prevent view rotation interference.
- **多显示器动态帧时钟自适应**：ScrollAnimator 渲染引擎内置跨屏幕动态刷新率同步机制，光标在 120Hz ProMotion 内置屏与外接显示器之间移动时毫秒级动态重绑定物理时钟，多屏来回滚动与热插拔无感顺滑。
- **Multi-display dynamic refresh rate sync**: integrated adaptive display link synchronization in the scroll engine, seamlessly rebinding the physical frame clock across 120Hz ProMotion and external displays without stuttering or dropped frames.

[0.25.0]: https://github.com/Souitou-iop/Mousse/releases/tag/v0.25.0

## [0.24.0] - 2026-08-18

### 修复 / Fixed

- **按键超时定时器失效导致单击被阻塞**：修复当按键同时配置了单击与双击/长按时，单次定时器（one-shot timer）触发后失效导致单击动作被卡在状态机内、必须点第二次才被释放的问题。将按键触发定时器重构为支持持续重置的重复定时器，并在周期 Tick 中加入超时兜底，确保单击在识别窗口结束后即时触发。
- **Button trigger timer expiration causing blocked clicks**: fixed an issue where a button configured with both click and double-click/hold would have its click action trapped in the recognizer state machine after the one-shot timer fired and became dead, requiring a second press to flush the action. Refactored the button trigger timer to a re-armable repeating timer with periodic tick fallback, guaranteeing clicks fire promptly after the recognition window expires.
- **未激活窗口侧键响应**：修复鼠标悬停在后台非激活窗口时，点击前进/后退侧键需要点击两次才能响应的问题。智能导航分发时将自动激活目标应用并精准派发导航操作，消除 macOS 系统对后台窗口首击的 Click-through 拦截。
- **Side button navigation on inactive windows**: fixed an issue where clicking the forward/back mouse side buttons over an inactive background window required two clicks to take effect. Smart Navigation now activates the target application and routes the action directly, eliminating the macOS background window click-through barrier.
- **按键手势误触发桌面切换**：对齐 Mac Mouse Fix，彻底移除手势结束时的非零退出惯性速度（Exit Speed），让微小位移在松手时由系统平滑回弹（Snap Back）至原桌面；同时优化起始死区门槛（10px），防止按下中键/手势按键时的机械微动公差误触发切屏。
- **Space drag accidental triggering on press**: aligned with Mac Mouse Fix by removing non-zero exit speed momentum on gesture completion, allowing small accidental offsets on button release to snap back smoothly to the current Space instead of triggering a full Space switch; refined the initial drag deadzone threshold (10px) to prevent mechanical button travel jitter from initiating gestures.

### 改进 / Improved

- **构建产物统一与版本标识**：打包脚本优化，构建产物统一输出至 `build/` 目录，归档包自动附加版本号（如 `build/Mousse-0.24.0.zip`）。
- **Unified build artifacts and versioning**: packaging script refined to output archives consistently into the `build/` directory with explicit version tags (e.g. `build/Mousse-0.24.0.zip`).

[0.24.0]: https://github.com/Souitou-iop/Mousse/releases/tag/v0.24.0

## [0.21.0] - 2026-08-17

### 新增 / Added

- **菜单栏快速控制**：在菜单栏下拉菜单中直接加入“反转滚动方向”和“平滑滚动”全局开关，方便快速切换滚轮行为，无需每次打开设置窗口。
- **Menu bar quick toggles**: added direct toggles for "Reverse Scrolling" and "Smooth Scrolling" in the menu bar extra menu for rapid workflow adjustments without opening the Settings window.

[0.21.0]: https://github.com/Souitou-iop/Mousse/releases/tag/v0.21.0

## [0.20.1] - 2026-08-16

### 修复 / Fixed

- **语言菜单选项固定**：设置中语言切换菜单的“跟随系统”选项固定为英文“System Default”，避免在系统首选语言为日文等环境时偶发显示为“システムに従う”等不一致文本。
- **Pinned system language option**: the "System Default" entry in the Language picker is now pinned to English across all system locales, preventing dynamic localization mismatch.

### 改进 / Improved

- **多语言截图文档**：各语言 README（中/英/日）补充了按键、滚动与指针设置的高清本地化界面展示。
- **Localized documentation screenshots**: embedded high-resolution screenshot galleries across English, Simplified Chinese, and Japanese READMEs.

[0.20.1]: https://github.com/Souitou-iop/Mousse/releases/tag/v0.20.1

## [0.20.0] - 2026-08-16

### 改进 / Improved

- **按键设置页布局居中**：操作选择下拉菜单在触发标签（如“单击 →”）与删除按钮之间自动居中对齐，并适度拓展宽度至 200pt，优化多语言界面下的排版视觉。
- **Centered button mapping layout**: action popup controls now automatically center between the trigger label (e.g. "Click →") and the delete button, with width refined to 200pt for clean visual alignment across all localized UI strings.
- **多语言文档体系**：拆分为独立的中、英、日（README.md, README_zh.md, README_ja.md）专属文档页面，并在页面顶部提供一键语言切换导航。
- **Multilingual documentation**: split documentation into dedicated English, Simplified Chinese, and Japanese README pages with seamless top navigation bar.

[0.20.0]: https://github.com/Souitou-iop/Mousse/releases/tag/v0.20.0

## [0.19.0] - 2026-08-15

### 新增 / Added

- **macOS 15+ 支持**：最低系统版本由 macOS 26 调整为 macOS 15，Release、Debug staging、SwiftPM 和 GitHub Actions 统一生成 arm64、`minos 15.0` 的应用。
- **macOS 15+ support**: the minimum system version is now macOS 15. Release and debug staging, SwiftPM, and GitHub Actions consistently produce an arm64 app with `minos 15.0`.
- **系统外观自适应**：继续使用标准 SwiftUI/AppKit 结构；macOS 15 保持其原生样式，macOS 26 及后续版本由系统自动采用 Liquid Glass 等对应平台外观。
- **Adaptive system appearance**: standard SwiftUI and AppKit structures remain in use, preserving the native macOS 15 style while allowing macOS 26 and later to adopt Liquid Glass and subsequent system appearances automatically.

### 说明 / Notes

- 使用 macOS 26 SDK 构建以获得新系统适配，同时不调用需要 macOS 26 才能运行的未保护界面 API；自绘自动滚动 HUD 保持透明、低侵入设计。
- Builds continue to use the macOS 26 SDK for current-system integration without unguarded UI APIs that require macOS 26 at runtime. The custom auto-scroll HUD remains transparent and low-profile.

[0.19.0]: https://github.com/Souitou-iop/Mousse/releases/tag/v0.19.0

## [0.18.1] - 2026-08-15

### 修复 / Fixed

- **应用滚动开关独立生效**：关闭某个应用的 Mousse 滚动优化后，仍可单独启用反向滚动；只有两个开关都关闭时才会完全原样传递滚轮事件。
- **Independent app scrolling switches**: reverse scrolling can now stay enabled when Mousse scrolling optimization is off. Wheel input is passed through unchanged only when both switches are off.
- **Parallels 虚拟机滚动**：仅反向时保留原始滚动幅度和按键修饰状态，不进入平滑、速度、加速度、缩放或轴转换处理。
- **Parallels virtual-machine scrolling**: reverse-only mode preserves the native scroll magnitude and modifier flags without entering smoothing, speed, acceleration, zoom, or axis-transpose processing.
- **自动发布**：推送版本 tag 后由 GitHub Actions 验证并发布 Release，同时移除 ZIP 中外置磁盘产生的 `._*` 元数据文件。
- **Automated releases**: version tags now publish a validated GitHub Release through Actions, and release ZIPs omit `._*` metadata generated on external disks.

[0.18.1]: https://github.com/Souitou-iop/Mousse/releases/tag/v0.18.1

## [0.18.0] - 2026-08-15

### 新增 / Added

- **指针控制**：新增独立“指针”页面，可选择由 Mousse 管理 macOS 鼠标加速，并以 `0.25×–4×` 相对倍率调整指针速度；默认关闭，升级后不会自动改变现有鼠标手感。
- **Pointer control**: a new Pointer tab can let Mousse manage macOS mouse acceleration and adjust pointer speed with a relative `0.25×–4×` multiplier. It is off by default, so upgrading does not change the existing pointer feel.
- **按应用覆盖**：可按前台应用分别继承、开启或关闭加速，并选择全局或独立速度倍率；按钮映射仍在“按钮”页面全局管理。
- **Per-app overrides**: each frontmost app can inherit, enable, or disable acceleration and use either the global or a custom speed multiplier. Button mappings remain global in the Buttons tab.
- **指针诊断**：诊断中心新增接管状态、匹配配置、目标加速与速度、已应用鼠标数量，以及不可用、失败或外部状态漂移提示。
- **Pointer diagnostics**: Diagnostics now reports management state, matched profile, target acceleration and speed, applied mouse count, and unavailable, failed, or externally drifted states.
- **系统设置协调**：接管期间若系统或其他工具修改了鼠标 HID 状态，Mousse 会逐属性保留为新的恢复基准而不反复抢写；“指针”页可采用该基准并重新应用当前配置。
- **System-settings coordination**: if the system or another utility changes mouse HID state during management, Mousse preserves each changed property as the new restore baseline without continuously fighting it. The Pointer tab can adopt that baseline and reapply the current profile.
- **应用滚动设置**：滚动页面的应用例外现在可分别开启 Mousse 滚动和反向滚动；Mousse 滚动继续使用全局模式与速度，旧排除列表会保持原生滚动行为。
- **Per-app scrolling**: app exceptions on the Scroll tab can now enable Mousse scrolling and reverse direction independently. Mousse scrolling continues to use the global mode and speed, while legacy exclusions retain native scrolling behavior.

### 说明 / Notes

- Mousse 仅调整通用鼠标的 macOS HID 软件状态，不读取或修改鼠标板载 DPI，也不会写入触控板。关闭接管、停用 Mousse 或正常退出时会恢复最近的系统基准，并保留接管期间检测到的外部修改。
- Mousse changes only the macOS HID software state for generic mice. It neither reads nor modifies onboard DPI and does not write to trackpads. Disabling management, disabling Mousse, or quitting normally restores the latest system baseline, including external changes detected during management.

### 移除 / Removed

- **简化应用配置**：移除独立“应用”页面及按应用按钮映射。旧配置中的 `perAppMappings` 会在读取或导入时忽略，并在下次保存或导出时省略；滚动应用例外、横向滚动应用列表及指针按应用配置保持不变。
- **Simplified app configuration**: removed the standalone Apps tab and per-app button mappings. Legacy `perAppMappings` data is ignored when loading or importing and omitted on the next save or export; scroll app exceptions, horizontal-scroll app lists, and per-app pointer profiles remain available.

[0.18.0]: https://github.com/Souitou-iop/Mousse/releases/tag/v0.18.0

## [0.17.0] - 2026-08-15

### 新增 / Added

- **诊断中心**：常规设置新增实时诊断面板，可查看辅助功能权限、Mousse 引擎和 event tap 健康度、恢复次数、已连接鼠标、指针下应用、匹配的按钮配置以及最近一次映射动作。
- **Diagnostics center**: General settings now include a live diagnostics panel for Accessibility permission, Mousse engine and event-tap health, recovery count, connected mice, the app under the pointer, the matched button profile, and the most recent mapped action.
- **自动滚动指示器**：自动滚动现在会在锚点显示单进程纯图形 HUD，以方向和强度反馈滚动状态；可通过 Esc、点击或真实鼠标滚轮退出，点击和滚轮仍会正常传递。指示器默认开启，可在滚动增强设置中关闭。
- **Auto-scroll indicator**: auto-scroll now shows a single-process graphical HUD at its anchor, communicating direction and strength. Escape, a click, or a real mouse wheel exits the mode while clicks and wheel input still pass through. The indicator is enabled by default and can be disabled in Scroll Enhancements.

### 改进 / Improved

- **更轻量流畅的 HUD**：指示器改为跟随鼠标方向旋转的紧凑箭头，并按显示器刷新率更新；方向和强度使用时间相关平滑，减少高刷新率屏幕上的跳变和延迟。
- **Lighter, smoother HUD**: the indicator is now a compact arrow that rotates with pointer direction and updates at the display refresh rate, with time-based smoothing for direction and strength.
- **自动滚动触发仲裁**：新增 50–500 毫秒独立启动延迟。双击在第二次松开时确认，第二次按住时长按优先，避免自动滚动与双击、长按映射互相误触。
- **Auto-scroll trigger arbitration**: added a dedicated 50–500 ms activation delay. Double-clicks resolve on the second release, while holding the second press gives hold actions priority, preventing conflicts with auto-scroll.

### 修复 / Fixed

- **自动滚动加速度档位**：加速度使用 0.05 步进，可准确选择 `0.25`、`0.30`、`1`、`2`、`8` 等值并正确持久化。
- **Auto-scroll acceleration steps**: acceleration now uses 0.05 increments, allowing exact integer and intermediate values with correct persistence.
- **设置窗口按钮**：设置窗口首次打开即可显示最小化按钮，切换标签页、关闭重开或从 Dock 恢复时保持一致，同时仍不可缩放。
- **Settings window controls**: the minimize button now appears immediately and remains correct across tab changes, reopening, and Dock restoration while the window stays non-resizable.

[0.17.0]: https://github.com/Souitou-iop/Mousse/releases/tag/v0.17.0

## [0.16.2] - 2026-08-14

### 修复 / Fixed

- **全局禁用后仍持续滚动**：关闭 Mousse 时，周期任务现在会立即取消自动滚动并重置边缘滚动状态，不再继续发送合成滚动事件。
- **Scrolling continued after globally disabling Mousse**: the periodic task now cancels auto-scroll and resets edge-scroll state as soon as Mousse is disabled, preventing further synthetic scroll events.
- **重复应用配置导致崩溃**：按钮映射解析器不再因相同 bundle ID 的重复配置触发字典异常；直接编辑的本地配置会确定性地采用最后一项，导入文件则会显示错误并拒绝应用。
- **Duplicate app profiles caused a crash**: the button mapping resolver no longer traps when profiles share a bundle ID. Hand-edited local configuration deterministically uses the last profile, while imported files are rejected with a clear error.
- **无效配置被误报为导入成功**：配置导入现在要求顶层为 JSON 对象，并拒绝重复的应用配置，避免 `[]` 等无效内容被解码为默认设置并覆盖现有配置。
- **Invalid configuration was reported as successfully imported**: imports now require a top-level JSON object and reject duplicate app profiles, preventing inputs such as `[]` from decoding to defaults and replacing existing settings.
- **缺失应用被重复查询**：Launch Services 找不到应用时也会缓存结果，避免 SwiftUI 重绘期间重复执行相同查询。
- **Missing applications were repeatedly resolved**: failed Launch Services lookups are now cached, avoiding repeated work during SwiftUI redraws.

[0.16.2]: https://github.com/Souitou-iop/Mousse/releases/tag/v0.16.2

## [0.16.1] - 2026-08-14

### 修复 / Fixed

- **语言跟随与切换失效**:SwiftPM 会把 `zh-Hans.lproj` 规范化为 `zh-hans.lproj`,此前按大小写精确查找语言包会匹配失败,导致系统为中文时仍显示英文、手动切换语言也无效。现在语言包按大小写不敏感匹配。
- **System language and manual switching not working**: SwiftPM normalizes `zh-Hans.lproj` to `zh-hans.lproj`, and the previous case-sensitive lookup missed it, so a Chinese system still showed English and manual language switching had no effect. Language bundles are now matched case-insensitively.

[0.16.1]: https://github.com/Souitou-iop/Mousse/releases/tag/v0.16.1

## [0.16.0] - 2026-08-14

### 新增 / Added

- **日语、韩语、西班牙语**:设置 → 常规 → 语言新增日本語、한국어、Español,系统语言也会自动匹配中/日/韩/西/英五种界面语言。
- **Japanese, Korean, and Spanish**: Settings → General → Language now offers 日本語, 한국어, and Español. The system language also auto-matches Simplified Chinese, Japanese, Korean, Spanish, or English.

### 其他 / Other

- **设置窗口加高**:设置窗口从 360pt 增高到 480pt,为按钮映射等密集页面留出更多操作空间。
- **Taller Settings window**: the Settings window grew from 360pt to 480pt tall, giving crowded pages such as button mappings more room.

[0.16.0]: https://github.com/Souitou-iop/Mousse/releases/tag/v0.16.0

## [0.15.0] - 2026-08-14

### 新增 / Added

- **每应用按钮映射**:设置新增"应用"页,可为特定应用单独配置按钮→动作映射。未配置的按钮自动回退到全局设置;当前应用按鼠标指针所在的窗口判定。支持每应用独立保留空按钮分组,并能随配置导入/导出。
- **Per-App button mappings**: a new Apps tab configures button→action mappings per app. Buttons without an app override fall back to the global mapping; the current app is resolved from the window under the mouse pointer. Per-app empty button groups persist and travel with config export/import.

### 修复 / Fixed

- **Safari 前进/后退失效**:与 Finder 相同,Safari 的 Navigation Swipe 在部分系统上会被忽略。现在 Safari 改用其原生历史命令 ⌘[ / ⌘],侧键前进/后退可正常触发。
- **Safari Back/Forward not working**: like Finder, Safari ignored synthesized Navigation Swipe events on some systems. Safari now uses its native history commands (Cmd+[ / Cmd+]), so side-button Back/Forward works again.

[0.15.0]: https://github.com/Souitou-iop/Mousse/releases/tag/v0.15.0

## [0.14.0] - 2026-08-14

### 新增 / Added

- **系统级动作**:按钮映射新增"聚焦搜索"(Spotlight)、"Siri"和"应用切换器(⌘+Tab)"三个预设动作。Spotlight 会读取并回放系统当前的快捷键绑定;Siri 在 macOS 26 上直接启动系统 Siri 应用(旧系统无此应用时回退到系统快捷键)。
- **System actions**: new presets for Spotlight, Siri, and the App Switcher (Cmd+Tab). Spotlight replays the system's current shortcut binding; Siri launches the system Siri app on macOS 26 (falling back to the symbolic-hotkey shortcut on older systems where the app is unavailable).
- **打开应用**:按钮映射可通过"选择应用…"绑定任意 .app,触发时直接启动;应用名称随配置持久化,可随配置导入/导出。
- **Open App**: button mappings can now launch any .app chosen from the system picker. The app's display name persists with the configuration and survives export/import.
- **自动滚动基础速度**:新增"自动滚动基础速度"(0–1000 px/s,默认 120 px/s),指针离开锚点后即使偏移很小也会先按基础速度滚动,不再几乎停滞;原"自动滚动速度"改名为"自动滚动加速度"(0.25×–8×),与基础速度叠加。
- **Auto-scroll base speed**: a new setting (0–1000 px/s, default 120 px/s) keeps auto-scroll moving immediately once the pointer leaves the dead zone instead of nearly stalling on small offsets. The former speed setting is now labeled "auto-scroll acceleration" (0.25×–8×) and stacks with the base speed.
- **配置导入/导出**:设置 → 常规新增"配置"分区,可导出全部设置为 JSON 文件,也可从 JSON 文件导入并立即生效。导出格式与本地 `config.json` 一致,便于备份、迁移和未来的 iCloud 同步。
- **Config export/import**: the General tab now exports the full configuration to JSON and imports it back with immediate effect. The format matches the local `config.json`, making backups, migration, and future iCloud sync straightforward.

### 其他 / Other

- **扩大滚动速度调节范围**:滚动速度 0.05×–3×,缩放速度 0.2×–6×,边缘滚动速度 50–2400 px/s,自动滚动加速度 0.25×–8×;自动滚动输出速度上限由 2000 提高到 4000 px/s。
- **Expanded speed ranges**: scroll speed 0.05×–3×, zoom speed 0.2×–6×, edge-scroll speed 50–2400 px/s, and auto-scroll acceleration 0.25×–8×; the auto-scroll output cap rose from 2000 to 4000 px/s.

[0.14.0]: https://github.com/Souitou-iop/Mousse/releases/tag/v0.14.0

## [0.13.0] - 2026-08-14

### 新增

- **自动滚动速度可调**:设置 → 滚动 → 增强 新增"自动滚动速度"(0.5×–4×,默认 1.5×,较此前默认更快),作用于按钮映射中的"自动滚动"动作——指针偏离锚点时页面滚动更快。

### 其他

- **滚动设置页重构**:按分类整理为"滚动样式"(模式/平滑度/行数)、"速度与方向"(滚动速度/加速度/反转/缩放速度)、"增强"(边缘滚动/自动滚动速度/高分辨率平滑)、"修饰键"与"按应用"分区,不再平铺堆叠。

[0.13.0]: https://github.com/Souitou-iop/Mousse/releases/tag/v0.13.0

## [0.12.3] - 2026-08-14

### 修复

- **自动滚动改为 Windows 原生逻辑**:此前实现为"指针锁定/移动驱动"方式,与 Windows 行为不符。现在:进入模式后记录锚点,鼠标向某个方向移动一次,页面即**自动持续**朝该方向滚动(无需持续移动鼠标);指针离锚点越远滚动越快;指针移回锚点附近(±6px)停止;越过锚点即反向。指针完全自由,不被锁定。

[0.12.3]: https://github.com/Souitou-iop/Mousse/releases/tag/v0.12.3

## [0.12.2] - 2026-08-14

### 修复

- **自动滚动在嵌套滚动区域(如浏览器 AI 对话窗)失效**:此前的"移动指针滚动"模式中,合成滚动事件派发到指针当前位置,指针移出对话框后滚动目标就变成外层页面。现在进入自动滚动模式时**指针锚定在进入位置**(复用指针锁定机制),移动鼠标产生"虚拟位移"驱动滚动——滚动事件始终派发到锚点,对话框等嵌套滚动区域可被持续、无限地滚动,对任意应用通用,无需逐应用适配。

[0.12.2]: https://github.com/Souitou-iop/Mousse/releases/tag/v0.12.2

## [0.12.1] - 2026-08-14

### 修复

- **自动滚动无法无限滚动**:指针受屏幕范围限制,滚到屏幕边缘后就没有位移了。现在指针进入屏幕边缘带后,页面按进入边缘前的移动速度**持续向该方向滚动**(四向均支持),直到指针离开边缘——可无限滚动长页面。
- **自动滚动卡顿**:滚动量不再以 30Hz 整数像素直接发送,而是喂给滚动动画器(与滚轮同一管线:120Hz 显示链路 + 弹簧平滑 + 子像素输出),丝滑度与直接滚动滚轮一致。

[0.12.1]: https://github.com/Souitou-iop/Mousse/releases/tag/v0.12.1

## [0.12.0] - 2026-08-14

### 新增

- **自动滚动(Windows 中键式)**:按钮动作新增"自动滚动(移动指针滚动页面)"。触发一次(单击/双击/长按均可,按钮可在按键设置中自定义,不限于中键)进入滚动模式,之后移动鼠标指针即带动页面滚动——指针上移页面上滚、下移下滚,左右同构;再次触发退出模式。模式中真实滚轮照常可用。第一版无光标/视觉指示,退出仅通过再次触发。

[0.12.0]: https://github.com/Souitou-iop/Mousse/releases/tag/v0.12.0

## [0.11.2] - 2026-08-14

### 其他

- "按住滚动调整音量"动作文案改为"按住滚动滚轮调整音量",语义更明确(中英同步)。

[0.11.2]: https://github.com/Souitou-iop/Mousse/releases/tag/v0.11.2

## [0.11.1] - 2026-08-14

### 修复

- **按住滚动调整音量在侧键上不生效**:引擎此前只取配置列表中的第一个长按映射,且进入模式时不区分按钮——配置一个按钮后,所有按钮的按下都会被劫持进音量模式,侧键原本的功能(长按动作等)反而失效。现在按按钮独立匹配:每个配置了该动作的按钮(中键/侧键均可)各自生效,未配置的按钮完全不受影响。

[0.11.1]: https://github.com/Souitou-iop/Mousse/releases/tag/v0.11.1

## [0.11.0] - 2026-08-14

### 新增

- **缩放速度(⌘+滚轮)**:Cmd+滚轮捏合缩放的灵敏度现在可以独立于滚动速度调节(0.5×–3×),快速滚动手感不再强迫激进的缩放。
- **边缘滚动**:开启后,将指针停在屏幕顶部或底部边缘约半秒,页面即向该方向持续滚动;指针离开边缘或滚动滚轮即停止。速度可调(100–1200 px/s)。
- **按住滚动调整音量**:按钮的"长按"动作新增"按住滚动调整音量"——按住按钮期间滚轮上/下 = 音量 +1/−1 档,松开即恢复;按下立即生效(不等长按时长)。长按的其他单次动作不受影响。

### 修复

- 无(本版无修复项)。

[0.11.0]: https://github.com/Souitou-iop/Mousse/releases/tag/v0.11.0
## [0.10.0] - 2026-08-14

### 新增

- **拖动切换 Space 时锁定鼠标指针**(手势设置):按住拖移按钮进入拖拽后,指针锚定在拖拽起点不动,真实移动量照常驱动 Space 切换;适合指针容易滑出可操作范围的场景。移植自 Mac Mouse Fix 的 PointerFreeze,默认开启,可关闭。
- **智能缩放**:向任意按钮映射"智能缩放"动作,可触发 Safari/预览等应用的缩放至合适大小(等价触控板双指双击)。
- **模拟中键点击**:向按钮映射"模拟中键点击",可模拟第 3 键(中键)点击,例如在新标签页中打开链接。
- **设置窗口 Dock 动态显示**:平时保持纯菜单栏应用;打开设置窗口时出现 Dock 图标,窗口支持最小化,点击 Dock 图标可重新打开设置,关闭窗口后 Dock 图标自动消失。
- 新动作与既有动作名称的中英文案补全(调度中心、应用程序窗口、启动台、智能缩放、模拟中键等)。

### 修复

- **启动台在 macOS 26 上失效**:macOS 26 将 Launchpad 替换为 Apps 应用并清空了符号热键绑定。现在按系统分流——macOS 26+ 直接打开 Apps(零系统写入),macOS 15 及更早走符号热键(默认零写入,仅在用户手动禁用快捷键时采用 MMF 式不可见绑定兜底)。
- **平滑滚动在页面中间或边缘偶发卡住**:移除反向刹车(反向第一格不再被吞),并将平滑模式的滚轮事件改为无相位连续像素事件(与 Mac Mouse Fix 默认一致),消除应用端每格切换手势/动量流导致的输入丢失。平滑步进模式不受影响。
- **添加操作时默认选中"向左移动一个 Space"**:新增的映射不再预设任何操作,显示"选择操作…"由用户自行选择;未配置完成前该按钮保持原生行为,不会被吞掉。

### 其他

- 构建脚本支持安装在外置磁盘的 Xcode;CI 增加产物资源包、架构、签名与实际启动校验(避免"构建成功但打不开")。
- 修复 Release 构建后资源包加载崩溃导致应用无法启动的问题。

[0.10.0]: https://github.com/Souitou-iop/Mousse/releases/tag/v0.10.0

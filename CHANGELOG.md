# 更新日志 / Changelog

本项目遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。本文件同时提供中文与英文条目 / This file is bilingual.

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

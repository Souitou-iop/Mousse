# Mousse

面向 macOS 15（Sequoia）及更高版本的轻量级、单进程菜单栏鼠标工具。
它为普通 USB/Bluetooth 鼠标补上 macOS 未提供的能力：平滑滚动、按键重映射，以及拖动切换 Space，
不需要后台辅助进程、许可证服务器或修改系统配置。

## 功能

### 滚动

- **三种样式**：_标准_（滚轮立即响应，无动画）、_平滑_（触控板式缓动惯性）和 _平滑步进_
  （Windows 浏览器风格，每格缓动固定行数，不保留余速）。
- 可调节滚动速度和每格行数（平滑步进模式）。
- 可独立于系统设置反转滚动方向。
- 可选的高分辨率鼠标平滑，适用于没有硬件飞轮、滚动不连贯的鼠标（例如 Keychron M6）。
  MX Master 3 等自由滚轮鼠标已有硬件飞轮，建议关闭此选项。
- 可添加滚动排除应用；指针位于这些应用时，平滑、速度、加速、反向、轴向交换和滚动修饰键均不介入。
- 不会修改触控板手势，只处理实体鼠标滚轮。

### 按钮

- 将任意鼠标按钮的单击、双击和长按分别映射为预设动作（返回/前进、向左/右移动一个 Space、
  Mission Control、App Exposé、Launchpad、媒体键），或录制自定义键盘快捷键（例如 ⌘W、⌘⇧4）。
- 返回/前进会为适用的 Apple 应用模拟 Navigation Swipe，为 Finder 和部分特殊应用使用
  `⌘[` / `⌘]` 等原生快捷键，并为 Chromium 等第三方应用发送标准鼠标按钮 4/5。Navigation Swipe 的事件实现
  参考 Mac Mouse Fix，但不要求本机配备触控板。
- 捕获时按下鼠标按钮以创建对应按钮分组，再从分组标题添加单击、双击或长按触发方式；捕获事件会被 Mousse 吞掉，不会触发其他应用的侧键功能。
- 双击间隔和长按时长可调。只有同一按钮配置了双击动作时，单击动作才会等待双击判定窗口。
  双击间隔范围为 100–500 毫秒，长按时长范围为 100–800 毫秒。

### 手势

- **拖动切换 Space**：按住指定按钮向左/右拖动，可按可配置的拖动距离逐个切换 Space。

### 可靠性

- 从睡眠/唤醒和显示器变化（插拔显示器或修改分辨率）中自动恢复，滚动和手势不会悄然失效。
- 正确处理高分辨率和自由滚轮鼠标，在尊重速度和反向设置的同时避免干扰硬件飞轮。
- 单个 Swift 进程运行，空闲 CPU 占用极低，内存占用小且稳定。

## 系统要求

- macOS 15.0（Sequoia）或更高版本。
- **辅助功能权限**（系统设置 → 隐私与安全性 → 辅助功能），用于读取鼠标输入。

## 安装

### 方式一：下载预构建应用

从 [最新版本](https://github.com/MinhQuang28/Mousse/releases) 下载 `Mousse.zip`，解压后将 `Mousse.app`
拖入 **应用程序** 文件夹。

此版本使用本地（未公证）证书签名，首次启动可能被 macOS 阻止。可在系统设置 → 隐私与安全性中选择
**仍要打开**，或在终端执行：

```sh
xattr -dr com.apple.quarantine /Applications/Mousse.app
```

启动 Mousse 后，在提示中授予辅助功能权限（系统设置 → 隐私与安全性 → 辅助功能 → 启用 Mousse）。
鼠标图标会出现在菜单栏，点击即可配置滚动和按钮。

### 方式二：从源码构建

需要 Xcode（测试版）Swift 工具链：

```sh
# 可选：设置稳定的签名身份，使辅助功能授权在重新构建后仍然有效
tools/setup-signing-cert.sh

# 构建菜单栏应用到 build/Mousse.app
./build-app.sh

# 运行
open build/Mousse.app
```

## 使用

启动应用后它会常驻菜单栏（不显示 Dock 图标）。打开 **设置**（⌘,）可看到四个标签页：
**常规**、**按钮**、**滚动** 和 **手势**。

## 开发

```sh
# 运行测试套件
swift test

# 打包发布版本：构建、压缩并生成 sha256（仅本地）
tools/package-release.sh

# 同时创建 GitHub Release 并上传压缩包
tools/package-release.sh --publish
```

## 项目结构

| 路径 | 用途 |
| --- | --- |
| `Sources/Mousse/` | 应用源码（事件监听、滚动动画、设置界面、配置） |
| `Tests/MousseTests/` | 单元测试 |
| `build-app.sh` | 组装并签名 `.app` |
| `tools/setup-signing-cert.sh` | 创建稳定的本地签名证书 |
| `tools/package-release.sh` | 构建、压缩、校验并可选发布版本 |

## 许可证

Mousse 以 [PolyForm Noncommercial License 1.0.0](LICENSE.md) 提供源代码：

- ✅ 允许个人非商业使用、阅读源码、修改、构建和免费分享。
- ❌ 禁止商业使用；如需将源码用于商业产品、销售或收费访问，请另行取得作者许可。

Copyright © Ha Minh Quang。

返回/前进中的 Navigation Swipe 行为参考并以 Swift 独立重写自
[Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix) 的 `TouchSimulator`，原实现采用 MMF License。

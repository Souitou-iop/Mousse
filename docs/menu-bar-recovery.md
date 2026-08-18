# 菜单栏状态项故障处理记录

## 适用症状

- Mousse App 可以启动，但菜单栏图标不出现。
- App 启动后很快退出，日志中出现 `NSStatusItemChangeVisibilityAction`、`terminate` 或 AppKit Automatic Termination。
- 修改 `MenuBarExtra`、改用 `NSStatusItem`、重新签名或单独重启 Control Center 没有解决问题。

## 已确认根因

问题不在 `MenuBarExtra` 菜单内容、滚动引擎或签名本身，而是 macOS 为 bundle ID `com.mousse.app` 保存的状态项缓存损坏。

同一份二进制临时换用新的 bundle ID 后可以正常显示，说明故障绑定在系统状态项身份。不要把临时 bundle ID 直接作为正式修复方案，否则会导致 Accessibility / Input Monitoring 权限重新授权，并破坏后续升级连续性。

## 可恢复的恢复流程

以下操作只针对 Mousse 和当前用户的 Control Center 状态。先把文件移动到废纸篓目录，不要使用不可恢复的删除命令。

1. 停止所有 Mousse 进程。
2. 将旧 App、`~/Library/Preferences/com.mousse.app.plist`、对应缓存和 Saved State 移到带时间戳的 `~/.Trash/Mousse-status-reset-YYYYMMDD` 目录。
3. 备份当前用户的 Control Center 偏好文件：

   `~/Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist`

4. 从 `trackedApplications` 数组中移除以下 bundle 记录及其它应用 `menuItemLocations` 中对它们的引用：

   - `com.mousse.app`
   - 本次排查产生的临时测试 ID，例如 `com.mousse.statusitem-probe`

5. 注销旧 App 的 Launch Services 路径。
6. 重启当前用户的 `cfprefsd` 和 Control Center 进程。只重启 Control Center 而不重启 `cfprefsd`，旧缓存可能会被重新写回。
7. 安装并注册正式 App，再从 App Bundle 启动，不要直接运行 SwiftPM 裸二进制。
8. 通过进程、日志和实际屏幕观察确认菜单栏图标出现。

本次恢复使用的备份目录是：

`~/.Trash/Mousse-status-reset-20260818`

## 验收标准

- `com.mousse.app` 正式包进程在启动数秒后仍然存在。
- 菜单栏能看到 Mousse 图标并可打开菜单。
- 日志不再出现状态项变化后立即 `terminate`。
- Control Center 状态项记录重新生成且允许显示。
- App 的 Accessibility 和 Input Monitoring 权限分别可见。
- 未授权时，“启用 Mousse”显示为关闭且不可点击；授权完成后才允许启用。

## 构建注意事项

正式包和 Debug staging 必须使用一致的 App 元数据，至少包括：

- `CFBundleIdentifier=com.mousse.app`
- `CFBundlePackageType=APPL`
- `LSUIElement=true`
- `NSPrincipalClass=NSApplication`

发布前必须从打包后的 App Bundle 启动验证。只验证 `swift build`、ZIP 或代码签名，不能证明菜单栏状态项实际可用。

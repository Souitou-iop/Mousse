# Mousse 修改总结(2026-09-26)

> 本次会话完成三个版本的迭代:**v0.27.0(已发布)**、**v0.28.0** 与 **v0.28.1(已构建,未提交/未发布)**。
> 工作区:`/Volumes/SanDisk/Projects/Mousse` · 运行实例:`/Volumes/SanDisk/Applications/Mousse.app`

| 版本 | 主题 | 状态 |
|---|---|---|
| 0.27.0 | 滚动引擎移植(快甩减速尾巴 + 显示器跨度缓存) | ✅ 已提交(`c99a83e`)、已推 tag、已发 [GitHub Release](https://github.com/Souitou-iop/Mousse/releases/tag/v0.27.0) |
| 0.28.0 | 本地命令行接口(CLI,面向 AI/脚本自动化)+ 实现审查 4 项修复 | ⏳ 代码完成、229 测试通过、本地打包完成;**未提交、未发布** |
| 0.28.1 | 按键映射按应用排除 + 菜单栏指针加速开关 | ⏳ 代码完成、229 测试通过、本地打包完成;**未提交、未发布** |

---

## v0.27.0 — 滚动引擎移植(来自上游 0.9.6 `6492eae`)

### 背景与选型

分析了上游 `MinhQuang28/Mousse` 领先的 8 个提交(0.9.5 → 0.10.0),结论:

- 其中 4 个功能(覆盖层自然关闭、flick 冷却重置、唤醒重建 event tap、指针冻结、独立缩放速度)与 fork 已有实现**重复**,整支合并必然冲突,放弃;
- 真正有价值的两项:①快甩减速尾巴(唯一有手感含量的改动);②ScreenSpanResolver 性能优化;
- 上游补丁依赖其保留的**反向刹车与 wheel 相位流**,而 fork 在 `6b81738` 有意删除了这两者,物理模型已分叉——因此只移植思路,不 cherry-pick。

### 改动 1:快甩减速尾巴

- **旧行为**:快速甩动触发 12,000 px/s 输出上限后,按上限匀速排空积压,排空瞬间**戛然而止**;且排空期间同向新滚轮格取到计划末端速度 ≈ 0,**从静止重新起速**(中途顿挫)。
- **新行为**:一旦积压距离 ≤「从上限速度起滑的拖拽 coast 覆盖距离」(Snappy ≈524px / Balanced ≈1,112px / Floaty ≈3,857px),动画器把剩余量重规划为 `HybridPlan(coastDistance:)` 纯减速滑行,以当前 profile 自身的 drag 曲线收尾。
- **关键实现**:
  - 新增 `ScrollAnimator.ceilingTail(backlog:profile:)`(纯函数,可单测)与 `planSpeedLocked`——节流期间向后续格子报告**真实输出速度**(12,000 px/s)而非计划名义速度;
  - 新增 `HybridPlan.init(coastDistance:profile:)` 与共享的 `coast(distance:profile:)` 助手(`ScrollMath.swift`);
  - 单次甩动计划距离上限从 100,000 px 收紧为 `ceiling × maxDuration`(18,000 px);
  - **适配点**:反向立即翻转(fork 无刹车)、动量标注保持休眠(相位流已删),上游相关代码一律未带。
- **生效条件**:仅当甩动真正触及上限(默认灵敏度下约需连续 5 次快速连锁甩动);日常中低速滚动与旧版逐比特一致。

### 改动 2:ScreenSpanResolver(新文件)

- 旧行为:事件 tap 线程上**每个滚轮格**执行 `CGGetDisplaysWithPoint` + `CGDisplayPixels*`(约 16 µs),用于屏幕尺寸灵敏度缩放与 Ctrl 快速滚动窗口;
- 新行为:缓存显示器 bounds 与两轴像素跨度,命中为矩形包含测试;随 cursorApp 缓存一同失效(唤醒/显示器变化/Space·应用切换),5 秒 TTL 兜底;行为结果不变。

### 测试

新增 `CeilingTailTests` 6 个:附着规则、交接连续性(触顶帧与 tail 起点速度一致)、阈值边界(0.5px)、修饰档 profile、五 profile 帧级甩动模拟(平台期后速度只降不升、无速度台阶、缓慢收尾)。

---

## v0.28.0 — 本地命令行接口(CLI)

### 背景与选型

改造前评估:项目**没有任何**程序化接口——无命令行参数处理、无 URL Scheme、无 IPC,`config.json` 仅启动时读一次且无文件监听(外部改了不生效,还会被 UI 的下一次保存覆盖)。对比三个方案后选定**方案 3(完整 CLI)**,同时守住两条用户约束:

1. **单进程设想不变**:CLI 是毫秒级存活的无状态瘦客户端,引擎所有权只属于 GUI 进程;
2. **系统设置后台项列表零变化**:不注册任何 launchd/登录项/帮助工具。

### 架构

```
CLI 进程(毫秒级)                    GUI 进程(引擎唯一所有者)
MousseEntry.main() ── argv 分岔      MousseApp(@main 移除,改由 Entry 调起)
  └─ CLICommand(纯参数解析)            └─ AppDelegate.applicationDidFinishLaunching
       └─ CommandServer.request()   ──►      └─ CommandServer.shared.start()
            (Unix socket 往返)                    └─ accept 线程 ──► CommandRouter(纯函数)
                                                       └─ AppCommandDelegate(主线程桥接)
```

四条不变量(构造保证,非约定):

1. CLI 路径在 `App.main()`/NSApplication 启动**之前**分支退出——不创建 event tap、动画器、菜单栏场景;
2. 配置**单写者**:`set` 经 socket 转交 GUI 进程的 `ConfigStore`,走与设置界面完全相同的属性赋值路径(`didSet` → 引擎实时重载 + 防抖持久化);CLI 从不直写 config.json(顺带消除了"外部改文件被覆盖"这类冲突);
3. socket 服务只是 app 内一条线程;app 未运行时 CLI 直接报错退出,**不做**"CLI 兜底启动引擎";
4. CLI 进程不触发任何 TCC 授权(不建 tap、不调 AX API)。

### 命令面(全部 JSON 回复,`Mousse help` 自文档化)

```
Mousse status | diagnostics | get <key> | set <key> <value> | quit | help | --version
```

- 可写键白名单(10 个,服务端校验类型/范围/枚举值):`enabled`、`reverseScroll`、`scrollAcceleration`、`smoothHighRes`、`edgeScroll`、`scrollSpeed`(0.05–3.0)、`zoomSpeed`(0.2–6.0)、`edgeScrollSpeed`(50–2400)、`scrollMode`、`scrollSmoothness`;拒绝时返回说明性错误(如 `expects a number in [0.05, 3.0]`)。
- 协议:`{"v":1,"cmd":...}` → `{"ok":true,"v":1,...}` / `{"ok":false,"error":...}`,退出码 0/1/2。

### 工程细节(实测踩过并修复)

- `SO_NOSIGPIPE`:对端提前挂断(探测连接、短命客户端)时 `send` 必须降级为失败返回,否则 SIGPIPE 杀死进程——单测中真实触发过;
- JSON 整数 → Double 需经 `NSNumber.doubleValue`(Swift 原生 `Int` 在 `Any` 中不会动态桥接为 `Double`);
- `String.withUTF8` 是 mutating 方法,对 `let` 属性不可用,改用 `Array(path.utf8)`;
- socket 文件生命周期:bind 前**探测**——存活对端则本实例拒绝服务(绝不抢占),不可连接的残留则 unlink 重建;`applicationWillTerminate` 时 unlink + close;mode 0600;
- `onMain` 用 `MainActor.assumeIsolated` + `DispatchQueue.main.sync`,主线程永不等待本线程,无死锁面;
- 协议版本校验排除 JSON Boolean:`true` 经 NSNumber 桥接会被 `as? Int` 误判为版本 1,现显式拒绝(非布尔整数才接受);
- CLI 数值参数拒绝非有限值(`nan`/`inf`/`1e309`):`Double()` 接受但 `JSONSerialization` 拒绝,否则会被误报为「应用未运行」,现按用法错误处理(exit 2);
- 单次计划距离上限不再静默丢弃输入:超出 `planMaxDistance` 的部分转入 `planOverflow`,在后续同轴同向的 notch 中继续消费(反向时清空,与 `leftover` 语义一致);
- accept 循环按连接分发独立工作线程:`handle` 会阻塞在 `recv`(5s 超时),内联处理会让单个半开客户端拖住后续 `status`/`get`/`set`;delegate 仍是唯一触碰引擎的路径(经主线程 hop),工作线程只并发收发。

### 测试

新增 19 个(总计 **226 全通过**):

- `CommandRouterTests`(12):协议版本、未知命令、状态/诊断封装、get/set 全键校验矩阵(bool 必须真布尔——`1`/`"true"` 均拒;数值范围;枚举 raw 值)、`quit` 侧效应;
- `CommandSocketTests`(5):真实 socket 往返(status/get/set 回读)、垃圾输入容错、陈旧 socket 替换、存活 socket 不抢占、无服务时客户端返回 nil、**半开客户端不阻塞其他请求**;
- `CommandRouterTests` 新增 `v:true`/`v:false` 拒绝;`ScrollMathTests` 新增计划上限溢出结转(不丢距离)。
- 文件:`Tests/MousseTests/CommandRouterTests.swift`、`Tests/MousseTests/CommandSocketTests.swift`、`Tests/MousseTests/ScrollMathTests.swift`

### 端到端冒烟记录(真机)

1. 对无 socket 的旧版执行 `Mousse status` → 干净报错 exit 1,**未拉起第二个引擎**(验证 CLI 分岔);
2. 拉起新版 → `status` 返回真实状态(引擎 healthy、权限、双鼠标、配置值)→ `set scrollSpeed 0.6` exit 0 → `get` 回读 0.6 → 坏键/越界 exit 1 → `quit` 后进程优雅退出、**socket 文件已清理**。

---

## 验证与产物汇总

| 项 | 结果 |
|---|---|
| 单元测试 | 229/229 通过(`swift test`) |
| 构建 | `build/Mousse.app` 0.28.1,稳定本地签名,`codesign --verify --strict` 通过,`minos 26.0` arm64 |
| 发布产物 | `build/Mousse-0.27.0.zip`(已发布)· `build/Mousse-0.28.0.zip` sha256 `d528bdc4…b28aa8` · `build/Mousse-0.28.1.zip` sha256 `a941e459…96ee79`(均本地;稳定本地签名,`codesign --verify --strict` 通过) |
| 冒烟 | 启动 4s 存活 + 退出;CLI 端到端全通过 |
| CHANGELOG | 中英双语条目已写入 `CHANGELOG.md`(0.27.0 / 0.28.0 / 0.28.1) |

## 变更文件清单

**0.27.0**(已提交 `c99a83e`):`ScrollAnimator.swift`、`ScrollMath.swift`、`EventTapEngine.swift`、新增 `ScreenSpanResolver.swift`、`Tests/ScrollMathTests.swift`、`build-app.sh`、`CHANGELOG.md`

**0.28.0**(未提交):新增 `CommandRouter.swift`、`CommandServer.swift`、`CLICommand.swift`、`Tests/CommandRouterTests.swift`、`Tests/CommandSocketTests.swift`;修改 `MousseApp.swift`(@main 分岔 + 服务启停)、`build-app.sh`、`CHANGELOG.md`

**0.28.1**(未提交):`AppConfig.swift`(新增 `buttonMappingExcludedBundleIDs`)、`ButtonMappingsView.swift`(排除列表 UI)、`EventTapEngine.swift`(按 bundleID 放行 + 纯函数 `isButtonMappingBypassed`)、`PointerSettingsController.swift`(菜单开关纯函数)、`MenuContent.swift`(指针加速菜单项)、5 个 `Localizable.strings`、`AppConfigTests.swift`、`PointerSettingsControllerTests.swift`、`build-app.sh`、`CHANGELOG.md`

## 遗留事项 / 注意

1. **0.28.0 未提交、未发布**——按惯例提交 + 推 tag `v0.28.0` + 本地发布(该仓库 tag 不触发 CI,历来为本地发布路径);
2. 上游仍有 6 个未合并提交,均为 fork 已有实现的重复,建议保持不合并;
3. `ci.yml` 的 `push: tags` 触发器实际未生效(历史 run 全部为手动/本地),如需 tag 自动发布需检查仓库 Actions 设置;
4. 冒烟测试的 `set` 曾写入真实配置(`scrollSpeed` 0.3 → 0.6),**已恢复原值**并核对运行实例一致;
5. 替换 `/Volumes/SanDisk/Applications/Mousse.app` 并重启后,CLI 即可用:`Mousse status`。

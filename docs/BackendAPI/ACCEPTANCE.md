# Nana Prada 配置后验收

验收日期：2026-10-09 21:55（Asia/Shanghai）  
项目：Nana  适用 `sourceAppId`：`67746202`  
API origin：`https://lantern.nanacc.top`  
网页主域名：`https://nanacc.top`

## 已核对

| 范围 | 预期 | 实际 | 结果 |
| --- | --- | --- | --- |
| API 根地址 HEAD | TLS 与 origin 可响应 | HTTP 200，`content-type: text/plain`，未记录响应正文 | 通过 |
| 登录方式 GET `/nana/harbor/doorway` | 无参请求，`code=0`，四个配置别名为数字 0/1 | HTTP 200；`apple_lantern=1`、`email_tide=1`、`register_current=1`、`visitor_harbor=0` | 通过 |
| 内容路由 | 按当前 contract 返回 `code=0` 与 `data` 对象/数组 | 12/12 路由 HTTP 200，响应 envelope 与数据类型正确；未发现 `datasetVersion` | 通过 |
| 本地契约与导入文件 | sourceAppId、域名、路径和模板保持一致 | 静态复核通过；接口模板 15 项，配置参数 14 项 | 通过 |
| 网页主域名根地址 | 能提供可加载的 HTTP(S) 响应 | `HEAD https://nanacc.top/` 出现 HTTP/2 `PROTOCOL_ERROR`；HTTP/1.1 GET 返回 empty reply | 未通过（根地址检查） |

## 尚未验证

- 认证 POST：没有授权的测试账号或 Apple 测试凭证，因此没有伪造登录请求。
- Ably：没有真实认证 token、目标频道 attached 和后台事件证据。
- A/B 分流：没有真实 `HarborPageReady` 事件或合法 H5 URL；无法证明 A、B 两个运行分支。
- App 编译、安装、真机页面连续性、APNs、支付确认、录屏保护效果：本次未执行。

证据仅保留 HTTP 状态、响应结构和脱敏配置，不记录 token、密码、Apple 凭证或收据。

## 后续编译复核

2026-10-09 22:35（Asia/Shanghai）执行：

```text
xcodebuild -project Nana.xcodeproj -scheme Nana -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build
```

结果：`BUILD SUCCEEDED`。Ably、AblyDeltaCodec、msgpack 均成功编译并参与 Nana target；未启动模拟器。日志仍有 Swift 6 并发迁移提示和 iOS `UIScreen.screens` 弃用提示，但不阻塞当前 Swift 5 编译。

## 2026-10-10 Prada 增量维护（仅静态）

本节描述当前源码，不沿用上方历史构建/网络结果作为本次验证。按用户要求移除既有防截屏/录屏，保留原生 SwiftUI、现有素材、契约及业务。Taste / Design / Garden 已按适用范围评估：此次为已有原生入口的状态与加载反馈维护，不创建网页设计稿或新视觉资产，不引入不适用的 HTML 实现。

| 范围 | 当前调用链与静态结论 |
| --- | --- |
| 防截屏/录屏 | 删除 `NanaPrivacyShield.swift`、入口和协议页 modifier，以及 Xcode 文件、分组、Sources 引用。普通 `WKWebView` 直接承载网页；无 secure text canvas、录屏监听或采集遮罩。正常相机/麦克风业务保留。 |
| 单次分流 | `NanaEntryCoordinator.startRealtime` → `undecided / preparingB / showingA / showingB / webFailure`。首次 connected 仅启动一次 3 秒期限；重连不延长。有效 URL 取消期限；A 已提交后忽略迟到 page 事件。连接本身另有 15 秒上限。 |
| 入口连续性 | 欢迎、账号和资料页保留到最终决议；`isEntryInProgress` 管理按钮附近反馈。静默恢复保留现有启动背景。移除 `routeLoading`、全屏登录提交遮罩及人为 3.4 秒等待，不先创建 A 首页。 |
| 首次 B 与网页失败 | `NanaWebDocument.prepare` → 主文档 HTTP 2xx + HTML/XHTML MIME → 当前 WKNavigation 的 didFinish → 显示 B。普通 WebView 实例保持在同一位置；未显示时关闭触摸和读屏。超时 30 秒、导航失败、HTTP/MIME 错误、内容进程终止进入独立错误态，可重试或返回欢迎，不自动转 A。 |
| 无地址与认证 | `NanaAuthenticationBoundary.authenticate` 优先校验非空 data 的 TokenRequest，不先按业务 code 拒绝有效实时凭证；允许的 HTTP 2xx + code=0 + 无 data 正常 A。`ConfiguredCoreEvent.pageDestination` 保留缺失/null/空白、合法 URL、无效配置三分支。iOS 路由串的查询解析避免直接向 percentEncodedQuery 传入未经解析字符串。 |
| 会话隔离 | `NanaSessionStore.beginEntryAttempt/checkEntryAttempt` 贯穿游客、邮箱、注册、Apple 和恢复；续期在写状态前核对会话代次与账号。实时回调、定时器与购买事件入口核对 route generation；WebView 完成核对 navigation，权限回调核对 generation。退出清理实时连接、加载、权限回调并回欢迎，旧回调不能再次登录。 |
| 协议与 Keychain | 游客协议默认勾选，Apple 独立状态默认未选；邮箱和注册仍未选。退出重建入口状态。Keychain 保存结构、service/account 名及重装恢复策略不变，不加入首次安装标记清理。 |
| 媒体权限 | `NanaWebDocument.isTrusted` 使用本次已认证 B URL 的完整 origin（scheme/host/port）并核对当前主框架及页面来源，删除 nanacc.top 固定判断。`NanaMediaAuthorization` 合并同设备类型并发请求，保留首次系统授权；退出/导航失效回调只 deny 一次。 |
| APNs | 启动 delegate → `NanaPushTokenCoordinator.start`；认证和续期共享最多 5 秒等待，拒绝/失败立即空值降级，取消不再发送认证。迟到 token 仅供后续请求。 |
| 奖励、支付与内容 | 删除未使用的欢迎赠币展示类型、状态和 dismiss 入口，保留 1200 奖励及原账本字段。现有商品、验单、购买恢复与本地钱包业务保持；支付遮罩显示时底层操作及读屏禁用，并仅绑定发起购买的账号，退出后不遮挡欢迎页。本轮不重构购买恢复体系，不据此声明支付专项通过。内容获取与实时分流分开推进，A 的欢迎关注副作用仅在实际显示 A 时启用。 |
| 配置与唤醒 | `67746202`、API `https://lantern.nanacc.top`、主域名 `https://nanacc.top`、冻结字段/事件、两个导入模板、SPM 锁文件均未修改。现有 Bundle ID Scheme、`.onOpenURL` 路由、相机/麦克风/相册声明保留。 |
| 清理与工程 | 本次改动文件的普通业务注释已清理；保留素材、部署来源和工程资料。其余编辑均在既有 target 源文件内；Ably target 产品引用保留。未新增依赖或重生成部署配置。 |

静态检查：`git diff --check`、`plutil -lint`（工程及 AppInfo.plist）通过；当前 contract 和生成 JSON 可解析；改动 Swift 文件均仍关联 Sources，删除的防护源码无残余工程引用。检查了可选 TokenRequest / URLComponents 解包及新增主线程 WebView owner；静态阅读不等于 Swift 编译通过。

未编译、未测试、未启动 App/模拟器、未截图，未请求真实业务接口、连接 Ably 或执行支付。页面实际呈现、真实网站权限及网络异常恢复需后续设备验证。

## 2026-10-12 新版契约同步（增量、仅静态）

本节取代历史记录中的 GET/四开关说明；历史编译或网络结果不是本次证据。此次保留原生布局与资产，仅将现有按钮组接入新的模式状态，不新增设计稿、图标或背景。

- **F01/F02 契约与数据**：`contract.json` 删除 `loginFlags`，新增固定字段 `loginEntryField=harbor_entry`；显式登录响应保留 `#{h5Url}`。最新版 `render_contract.py --replace` 同步双模板、常量、CSV 和请求样例。离线逐项比较：12 份内容响应与 HEAD 完全相等；15 个接口的内层响应与来源相等；14 项配置映射相等；认证/支付响应不变；两层 JSON 紧凑；App ID、域名、所有原路径和事件不变。未重新导出或改写内容模型/素材。
- **F03 工程**：生产 `IntegrationContract.generated.swift` 与生成物（去除普通注释后）一致，仍使用既有 Sources 成员。Ably 产品引用、SPM 版本/锁文件、Bundle ID Scheme、相机/麦克风/相册声明保留。新类型均位于已有 target 文件内；没有添加依赖或构建目标。
- **F04 请求**：`NanaAServiceClient.request/perform` 统一使用 `IntegrationContract.apiMethod`。内容 POST 明确发送 `{}`，没有认证参数/APNs 等待；核心请求为 JSON，禁止自动重定向。认证单独允许 HTTP 401 中的非空有效 token，空 data 仍要求 2xx + 整数 code=0。登录方式和支付确认不共享该例外，成功码拒绝布尔和浮点。HEAD 仅判断是否收到真实 HTTP 响应，不跟随重定向。
- **F04 APNs/设备**：启动注册与首个 active 的通知授权分开，实际 delegate 转交结果。`NanaPushTokenCoordinator` 以独立 continuation/5 秒定时器替换轮询；取消、失败/拒绝、超时和成功只完成当前等待者一次。`publicFields` 在其他字段合并后写入固定四参数并取最新 token；登录方式并行等待 HEAD 和 APNs，认证/恢复/续期共用构造器。设备 ID 仅在 Keychain 明确不存在时新建，写入后回读，不因读取失败换临时 ID。
- **F05 入口**：生成的 `ConfiguredLoginEntryMode.parse` → `NanaLoginEntryState.checking/resolved/fallback` → 欢迎页按钮与协调器表单路由。仅游客/标准模式互斥，删除四开关与“全关闭”分支。入口检测按欢迎周期缓存；表单返回不重查已完成结果；离开/后台取消未完成任务。网络失败显示可操作的标准 fallback，以 2/4/8/16/30 秒退避或网络恢复唤醒；用户开始认证时冻结模式并取消检测。游客协议初始为 true，网络恢复不重置手动选择；其他协议状态独立。各实际提交入口同步取得共享 attempt 锁后再启动异步工作。
- **网络监听适配**：使用独立 `NanaEntryNetworkWaiter`（系统 `NWPathMonitor`）配合现有 URLSession，无全局监听覆盖。已查阅 [Alamofire 5.12.2 官方源码](https://github.com/Alamofire/Alamofire/blob/5.12.2/Source/Features/NetworkReachabilityManager.swift)：其 `NetworkReachabilityManager` 在 iOS 17.4 起弃用并建议 NWPathMonitor；本项目最低 iOS 17，故采用该等效原生实现，不额外引入弃用依赖。只读取官方元数据/源码，没有调用项目业务接口。
- **F06/F07/F08 分流与网页**：保持全消息订阅、generation 校验、首次 connected 3 秒期限及迟到 page 隔离。补齐 WKWebView 的 AirPlay/行内播放/无需用户手势媒体配置及返回手势。`NanaWebSurface` 报告已挂载且具有尺寸；协调器要求本 scene active、稳定启动 host 已准备、当前主文档 HTTP/MIME + didFinish 成功后才展示 B。`commitEntryRoute` 在最终 A/B 决议时保存活动会话标记，未完成的首次认证不提前保存；资料编辑保留原有保存行为。Keychain 恢复策略不变。
- **F09/F10 业务保留**：现有 StoreKit 商品、购买事务、奖励余额、本地互动和回执业务不重新接入。本轮仅把支付确认请求纳入统一 POST 常量并严格校验整数成功码，未修改商品表、余额算法或待确认账本。原 `apply` 的持久化 confirmed/processedTransactionIDs 在 finish 之前；历史补单与后台幂等仍不能据此静态记录声明端到端验收通过。
- **F11 防护与清理**：上次已删除的 `NanaPrivacyShield`、录屏监听和安全文本画布没有重新引入，源码/工程残留搜索为空；密码安全输入和真实媒体权限保留。删除旧登录开关常量/模型，保留配置、全部响应源、部署资料和素材。此次新生成的运行时普通注释已移除。

本次实际检查：JSON/CSV 离线比对、生成常量与生产调用点、Swift actor/continuation 取消边界、来源及 target 引用、`plutil -lint`、`git diff --check`。仅查询 Swift 工具链版本以核对依赖兼容性；未执行编译、测试、模拟器、App 启动或业务联调，未连接 Ably/执行支付。双模板待用户导入、校验并保存后，再按需验收线上行为。

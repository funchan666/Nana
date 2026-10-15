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

## 2026-10-14 A/B 内购隔离与 Keychain 恢复（增量、仅静态）

本节取代旧记录中“全部订单后台确认后给本地钱包加币”的行为说明。支付模式为客户端内部状态；当前 App ID `67746202`、域名、商品、冻结路径/字段/事件、响应源及双模板均不变，不需要重复导入后台。

| 核对项 | 实际调用链与边界 |
| --- | --- |
| F09 入口隔离 | `NanaWalletView` → `NanaCoinStore.purchase(pack:)` 固定 `hostLocal`；`NanaEntryCoordinator.handleRealtimeMessage(.purchase)` → `purchaseFromRealtime` 固定 `ablyServer`，传递原商品、订单号、messageID、requestID。B 商品直接查 StoreKit，不再必须命中 A 面目录；保留现有消耗型购买范围。来源写入后不可因页面、当前账号、缺订单号或后台失败改变。 |
| 唯一所有者 | `NanaAppDelegate.didFinishLaunching` → `NanaCoinStore.shared.start`，启动独立 `Transaction.updates` 与 `unfinished` 枚举。根界面复用同一实例。`beginSession` 只更新展示账号，logout/删除账号不取消监听。成功返回、updates、unfinished 均进入 `receive`，以 App/环境/transactionId 合并后进入唯一 `process`；并发回放复用同一处理任务，不阻塞其他交易的监听。 |
| Keychain 账本 | 新增 `NanaPurchaseLedger`，固定独立 service `com.nanalantern.harbortide.purchase-orders.v1`，每单 UUID account；先枚举属性，再逐项读取数据，不依赖沙盒索引。保存来源、商品/类型、原账号、原 Apple 账号 token、App、版本、设备、原钱包标识和本地权益；B 另保存原订单/事件/requestID、origin、确认路径及实际五字段和成功字段。环境及原 transactionId 从 verified 交易补写。新记录 Add、既有 Update，关键写入后逐项回读；重复项读取后合并，冻结关联与终态不能被旧回调覆盖。 |
| 本地交付 | `process(.hostLocal)` → 原钱包按 transactionId 幂等加 `pack.coins`，余额及 processedTransactionIDs 同一次 Keychain 写入并回读 → 订单 `localDelivered` 写入回读 → finish。不需要后台订单号、收据或确认接口。钱包沿用原 service、商品/奖励/送礼算法及保护级别；未整体搬迁。订单先标 `deliveringLocal`，中断重试查钱包幂等证据，原钱包 identity 缺失/改变则待核对，不把新空钱包当未交付。 |
| 后台交付 | `process(.ablyServer)` → 读取当前 App receipt Base64 → `NanaAuthenticationBoundary.confirmPurchase` 使用订单冻结的服务/路径/版本/设备和五字段 → HTTP 2xx + 整数 code=0 → `serverConfirmed` 写入回读 → finish。不调用本地加币；不保存新完整收据，不用 JWS 代替。已交付回放只收尾；finish 后保存 `finished` 最小去重。 |
| 有界恢复 | `wakeRecovery` 在启动、前台、protected-data 解锁及独立 NWPathMonitor 恢复联网时枚举；失败按交易分别 2/8/30 秒退避，本轮耗尽后等下次触发。记录/凭据缺失保留，不调用 purchase、AppStore.sync 或自动弹 Apple 登录。存储未就绪时不扣款，早到交易暂存并保留 Apple 未完成状态。后台单恢复不依赖登录/Ably/主页内容；原钱包暂不可读不阻断已知 B 单确认。静默处理不安装交互遮罩、不向新账号弹旧结果。 |
| 迁移与未知记录 | 旧 `coins/ledger.v1` 实际混用了 A/B，`pendingOrderCodes` 仅按商品索引，`pendingPurchases` 缺模式、事件、购买时设备/服务等证据，不能靠 orderCode 存在推断真实来源。逐笔复制最小关联为 `legacyUnknown/needsReview`，保留旧 Keychain 原始副本；重复迁移识别 legacyKey，不覆盖已交付订单。坏单隔离、读写失败保留来源；旧未知单不触发加币、验单或 finish。钱包删除前检查待处理关联，避免把未交付的原权益仓库一并删掉。 |
| 反馈和并发 | 交互购买同步设置唯一锁再查商品/向 Apple 提交，沿用原纯文字反馈；成功、取消、pending 或转持久待处理后释放交互锁。原订单重放不再次扣款。存在同账号同商品且尚无交易号的未决关联时，先等待核对，不启动另一笔造成混淆；已明确关联且后台等待的单不阻塞其他原生购买。 |
| F03/F11 工程/生命周期 | `NanaPurchaseLedger.swift` 已加入实际 Nana Sources/Commerce 分组，`project.yml` 原 NanaHarbor 递归源目录涵盖它。新增状态属于 MainActor owner，网络回调转主线程；无新增 SDK、协议、权限或防截屏/录屏代码。登录与订单命名空间隔离，退出不能重置订单、恢复旧登录或给当前账号发放旧权益。 |

### 仍需真实证据的恢复边界

- 原 `appAccountToken` 是每账号 UUID，继续保留其含义。`purchase` 成功返回提供可信的当前调用关联；已写 transactionId 的订单可在重启/同身份重装后按原模式恢复。但 Apple 已付款、成功返回/transactionId 关键写尚未完成即进程中断，以及 Ask to Buy 仅通过后续回放到达的场景，没有可信逐单 UUID 或既有服务端对账接口，不能凭账号 token + 商品猜配；保留 Keychain intent 和 Apple unfinished 待核对。内存中的成功返回关联可在本次进程存储恢复后重试，但不能承诺跨进程消除此窗口。
- 历史提前 finish、原订单缺字段、已删除的关联、Keychain 丢失/访问配置变化均不能凭本次升级追回。旧未知单已保留，不把它们统一判成 A 或 B，也不新增猜测接口。Keychain 可读、同 App/原环境及有效 Apple 交易/收据是重装恢复条件。
- B 后端必须真实验单、持久入账并按 App/环境/transactionId 幂等。响应丢失仅原单重验，客户端不能验证该服务能力。收据缺失保持待处理，不以强制同步或启动循环弹授权“修好”。
- 本次仅做源码调用链、存储顺序、当前 SDK 声明、工程引用、契约/模板差异和 `git diff --check` / `plutil -lint` 静态核对。未编译、未测试、未启动 App/模拟器、未购买、未卸载重装、未连接后台/Ably；不能据此声称真实到账或重装专项验收通过。

## 2026-10-15 最新 Prada 原生 WebSocket 同步（增量、仅静态）

> 历史阶段记录：其中 tokenResult 载荷假设及“无需重导”已由文末“WebSocket 占位符修正”取代；支付版本以后续 StoreKit 1 记录为准。

本节取代此前“缺少线上 tokenResult 样本而停止迁移”及“需要 OPI rtLink / AES 配置”的说明。按新版技能，动态占位符本身不阻止静态迁移；沿用既有认证槽位和文档定义载荷完成客户端接线，未声称线上已经返回该结构。遵守用户本次及前述保留支付实现的限制，不执行 StoreKit 1 迁移。

| 项目 | 实际调用链及静态结论 |
| --- | --- |
| F01/F02 配置与数据 | `contract.json` 保留 `67746202`、API `https://lantern.nanacc.top`、网页主域 `https://nanacc.top`、所有字段/路径/事件。仅增加 `realtime.transport=rtLink` 标记、删除 `ably.rewind`；生产及文档生成常量同步该标记。全部响应源、两个导入模板与 HEAD 字节一致；不新增接口、不固化动态地址、不重新迁移内容。 |
| F03 工程 | 替换现有 Sources 成员 `ConfiguredRealtime.swift`，无遗漏的新源码成员。删除唯一 Ably package/product/framework 引用；锁文件仅有 Ably、其 delta-codec/MessagePack 依赖，已随唯一包移除。`project.yml` 本来没有包声明，无需生成工程。最低 iOS 17、Swift 5、原 Bundle ID 与权限/Scheme 保留。 |
| F04 认证适配 | `NanaAuthenticationBoundary.authenticate` → 映射后的 `data.token` → `ConfiguredRealtimeTicket.parseConnectionValue`，接受对象或单层 JSON 对象字符串。校验完整原样 wss URL、attach action/channel、可选身份及 epoch 毫秒到期；拒绝未替换占位符、纯 TokenRequest、缺字段或错误类型。HTTP/data 分流不变；空 data + 2xx + 整数 code=0 仍是正常 A。 |
| F04/F05/F08 会话接线 | `NanaSessionStore.realtimeTicket` → `NanaEntryCoordinator.startRealtime` → `ConfiguredRealtimeTransport.start`。连接参数只保存在会话内存，不写登录 Keychain。原 APNs 最多 5 秒、四公共字段、登录锁、游客/标准入口及协议状态不变。既有 `refreshRealtimeConnection` → `authentication.refresh` 仅发原公共参数，不重放密码/Apple 授权码；异步取消传播到请求，并核对账号及 entry generation。 |
| F06 单连接 | `@MainActor ConfiguredRealtimeTransport` 强持有唯一 URLSession/socket；安装回调后直接 `webSocketTask(with:)`，不新增 rtLink/AES 请求，拒绝 HTTP 重定向。持续 receive 支持文本和 JSON 字节；action 4 仅发送一次服务端 attach，action 11 核对当前频道后 ready；首次订阅上限 15 秒。 |
| F06 事件 | action 15 遍历全部消息，坏项独立跳过，JSON 字符串交现有业务解码器规范化。保留实际 message id/clientId/name；消息 id 缺失但存在真实协议帧 id 时按原 SDK 的 frameID:index 规则补全，保留原数组下标；两者及业务 msgId 都缺失则不执行副作用。不生成随机消息 ID。原四事件、退出包装、发送方过滤、内存去重及订单持久去重保持。 |
| F06 生命周期 | 任意接收帧更新单调时钟时间，按 action 4 的 maxIdleInterval + 5 秒检测空闲。断线/凭证失效/action 17/到期/前台/联网共用一个刷新任务与调度器；普通失败按 1/2/4/8/16/30 秒基数、±20% 抖动退避，只在 action 11 重置。前台/网络恢复仅在断线或期限已过时加速，健康连接不重建；合并并发刷新，并设 1 秒最小请求间隔避免即时失效循环。 |
| F06 刷新和终态 | 优先在有效期结束前 60 秒刷新；刚取得且不足 60 秒的有效地址允许先连，在剩余有效期的 80%（至少 1 秒）调度，避免零间隔刷新。无 expiry 不编造期限，依控制帧/断线复用现有刷新来源；未约定地址复用时重连取得新信息。刷新核对频道及已知房间身份，新地址成功取得后替换 socket generation；action 8 关闭且禁止自动恢复。stop 取消接收、发送、请求、全部定时器及网络/前台监听，旧回调不影响新会话。普通登录成功和页面切换不 stop，断线不清登录或订单。 |
| F07/F08 路由 | 从首次 action 11 启动一次 3 秒 A 决议期限，重连不延长。早于 ready 的 page 事件按 attempt 暂存，ready 后处理；有效 B 地址取消 A 期限，明确无地址进入 A，坏地址进入现有错误态。保留普通 WebView 的主文档 HTTP/MIME/didFinish、挂载尺寸、scene active 与持久会话提交门槛，未修改页面设计和资产。 |
| F09 支付 | `NanaCoinStore`、`NanaPurchaseLedger`、商品与钱包源码字节不变；认证文件中 `confirmPurchase` 及其后代码字节不变。仍由 App 启动的 StoreKit 2 updates/unfinished 进入唯一处理者，hostLocal 原验签/幂等入账后 localDelivered，ablyServer 原五字段 HTTP 确认后 serverConfirmed，关键写入回读后 finish。原账号/环境绑定、恢复重试及历史 needsReview 边界不变。 |
| F10/F11 清理 | 全项目未发现旧 publish/publishResult 的业务调用者，不新增上行 ACK 或回执队列。移除本链路 TokenRequest/ART 类型/import Ably/固定 rewind；仅保留身份、服务端发送方和历史订单的 ably 命名语义。无防截屏/录屏代码回归；退出仍回欢迎并清本次连接/网页，订单服务独立存活。日志不输出 URL、凭证或消息全文。 |

协议核对参考：[Ably 控制帧定义](https://github.com/ably/specification/blob/main/specifications/protocol.md)（ATTACH=10 / ATTACHED=11 的频道绑定）、[旧 SDK 的消息 ID 处理](https://github.com/ably/ably-cocoa/blob/1.4.0/Source/ARTRealtimeChannel.m)（onMessage 的真实帧 ID 与下标补全）。只查阅官方公开资料，没有请求项目业务接口。

静态检查：`git diff --check`、工程与 AppInfo.plist 的 `plutil -lint` 通过；全部 BackendAPI JSON 可解析；contract 差异严格限于 transport/rewind；双模板、响应源和 Commerce 文件逐字节对照 HEAD；生产/生成常量一致，修改文件保持 Sources 引用。复核了 MainActor 回调、异步任务取消、URLComponents 可选绑定、完整批次下标、15 秒连接及一次性 3 秒路由时序。未执行编译、测试、App/模拟器启动、购买或卸载重装。

未验证项：真实 `#{tokenResult}` 替换结果是否采用文档载荷、服务端订阅权限、刷新接口对新载荷的支持、网络中断/前后台实际行为及真实支付/WebView 效果。若线上仍返回旧 TokenRequest，需要平台按既有槽位提供直连载荷；客户端不会静默回退 SDK、另调 rtLink 或当作 A 成功。无需因本轮客户端传输更新重新导入双模板。

## 2026-10-15 A/B 统一 StoreKit 1（增量、仅静态）

本次用户明确授权两面迁移 StoreKit 1，本节取代前述“保留 StoreKit 2”的当前实现说明。App ID、域名、后台路径/五字段确认协议、商品、赠币比例、送礼和余额业务不变；不重新接入、不修改双模板、不要求后台重导入。

| 核对项 | 当前调用链与静态结论 |
| --- | --- |
| F09 入口/价格 | `purchase(pack:)` 固定 hostLocal；`purchaseFromRealtime` 固定 ablyServer。`NanaStoreKitRequests` 使用 SKProductsRequest，强持有请求/委托直到结果和结束回调齐备；15 秒超时、取消/换会话只收尾一次，回调在 MainActor 合并。价格来自 SKProduct.price/priceLocale。SKProduct 无商品 type，保留原消耗品业务范围并拒绝 subscriptionPeriod 非空的商品；收据有类型时复核，旧收据缺类型不声称已证明类型，B 还须服务器核实。 |
| 唯一消费者 | `NanaAppDelegate` 的启动/前台/解锁入口继续唤醒 `NanaCoinStore.shared`。`start` 强持有并只注册一个 `NanaPaymentQueueObserver`；`wakeRecovery` 合并 SKPaymentQueue.transactions 与暂存回调。已移除 SK2 Product、purchase、updates、unfinished、VerificationResult 和 finish 调用。queue 回调、恢复与两面购买共用同一 MainActor owner；不自动 restoreCompletedTransactions，不接受无原生订单关联的推广购买。 |
| 历史兼容 | `NanaPurchaseLedger` 的 schemaVersion=1、service/account、旧字段与冻结规则不变，仅增加可缺省的 applicationUsername。旧 appAccountToken 继续表示账号，不被重写为订单证据。新订单另存订单 UUID，并在付款前写入、回读后传给 SKMutablePayment.applicationUsername。回放优先精确 transactionIdentifier，否则只接受新逐单 UUID；存在冲突、旧单仅有账号 token/SKU 时不猜配。历史 legacyUnknown 原副本与 needsReview 边界保持。 |
| 新旧事务/幂等 | Apple purchased 到达后先保存原字符串交易号和 paid，再验收据、确定环境、按来源交付。处理任务在验证环境前按 Bundle/原交易号合并（更保守地串行化同号跨环境歧义）；环境与账本不一致拒绝。钱包新增 Bundle/环境/原交易号字符串幂等集合，仍读取并保留旧 UInt64 集合，能无损表示的新 ID 也双写旧集合。余额与两个幂等集合在同一钱包 Keychain 写入并回读。删除账号保留两种已处理索引；其他账号和已删除账号的交付证据不能被重新计入。 |
| 本地真实验证 | 新增 `NanaAppReceiptVerifier`，固定 TPInAppReceipt 4.0.2（tag commit `3ec500058c3cb62d0e736bf83c22b93b60279bd0`），已读取该 tag 的解码、验证及公开 API 源码。使用组件的完整证书/签名/元数据验证；额外明确以收据 creationDate 做证书链检查，并显式校验设备哈希（包括模拟器，不采用组件默认的模拟器跳过规则）。核对当前 Bundle ID、CFBundleVersion、原交易号、商品、数量 1、撤销/订阅字段。只接受 Apple production/sandbox，拒绝 Xcode/LocalTesting/未知收据环境，没有测试充值兜底或客户端 shared secret。 |
| 信任根/工程 | `NanaAppleRoot.cer` 与 Apple 官方证书下载逐字节一致，SHA-256 `b0b1730ecbc7ff4505142c49f1295e6eda6bcaed7e2c68c5be91b5a11001f024`。两个新 Swift 源码、证书 Resources、TPInAppReceipt Frameworks/product/package 引用已加入 Nana target；project.yml 同步 exactVersion 4.0.2。未重新生成工程覆盖已有配置。包声明需 Xcode 的 Swift 6 系列工具链，源码使用 @concurrent；本轮没有执行依赖解析、构建或安装验证，传递依赖待 Xcode 解析。 |
| A 面交付 | `process(.hostLocal)` 验签通过后，仍按冻结 localCoins 和原钱包 identity 幂等发放；原钱包缺失/改变保留 needsReview。保存并回读 localDelivered 后才进入唯一成功 finish。A 不调用 B 的五字段接口，不依赖实时连接/后台确认，不使用当前账号替代原账号。 |
| B 面交付 | `process(.ablyServer)` 使用当次验证过的 App receipt 原始 Data Base64，沿冻结 origin/path/version/device/orderCode 调用原 `confirmPurchase` 五字段接口。仅 HTTP 2xx + 整数 code=0 后保存并回读 serverConfirmed，再 finish；不本地加币、不保存新完整收据、不改后台协议。 |
| 收尾/待处理 | 已持久 localDelivered/serverConfirmed/finished 的已知交易只回读后补 finish，不要求收据再次包含已消耗商品，不重新加币。明确 failed/cancelled 只结束失败交易；deferred 解锁且不 finish/交付，批准后由 queue 回放处理。restored 不给消耗品重新加币，本项目没有新增非消耗品/订阅恢复业务。关联/存储/凭据异常不成功 finish；本次交互转 pending 后解除遮罩，旧单恢复不阻塞新页面。 |
| 恢复/生命周期 | 保留每单 2/8/30 秒有限重试，启动、前台、解锁、联网合并唤醒。只有当前显式购买、当前账号代次且 App 活跃时，缺失/不匹配收据可尝试一次 15 秒有界 refresh；后台恢复不发 receipt refresh、不循环触发 Apple 登录。logout 取消尚未提交的商品查询并解绑 UI，已提交订单继续由 App owner 按原账号/模式补单，迟到回调不能清除新购买的锁。 |

静态检查范围：Swift 源码调用关系、SDK 头文件及验证组件公开 API、唯一 observer/成功 finish owner、历史 Codable 可选字段、关键 Keychain 写入/回读顺序、原商品和业务方法差异、工程 Sources/Resources/package 引用、证书来源、JSON/plist 格式与 git diff。没有执行 Swift 编译/类型检查、测试、App/模拟器启动、支付、后台请求或卸载重装；不宣称沙盒到账或重装恢复已验收。

保留边界：旧 SK2 单若在交易号落盘前中断且只有账号级 token，仍缺逐单关联，不能靠迁移自动追回；新单依赖 Apple 回放保留其 applicationUsername UUID，缺失时同样待核对。Keychain/原钱包丢失、跨设备/访问组变化、提前 finish 的历史交易不保证恢复。SK1 的 App receipt 不提供与 SK2 相同的实时消耗品退款通知；本项目没有额外服务器退款通知渠道，本次不编造该能力。后台真实验单/幂等到账以及现有 B 商品在 App Store Connect 的消耗型配置仍待运行核实。

实现依据：[TPInAppReceipt 4.0.2 源码](https://github.com/tikhop/TPInAppReceipt/tree/4.0.2)、[Apple 设备收据验证](https://developer.apple.com/documentation/appstorereceipts/validating-receipts-on-the-device)、[Apple 根证书](https://www.apple.com/appleca/AppleIncRootCertificate.cer)。查阅/下载仅针对公开依赖与证书，未调用项目业务服务。


## 2026-10-15 内容媒体改为远程链接（仅静态）

- `NanaRemoteMedia.json` 按原文件名登记完整 62 张图片与 17 个视频；图片 URL 为用户提供 R2 origin 下的 `photo/<filename>.jpg`，视频为 `videoss/<filename>.mp4`，不改目录拼写。`NanaAssetLibrary` 保留原稳定 assetKey，通过该目录解析 URL，视频列表仍按原 key 排序；账号头像、帖子、收藏、屏蔽和创作者标识保持兼容，不把缓存文件路径写入业务数据。
- `NanaAssetImage` 通过 `NanaRemoteImageStore` 异步取图；按 URL 合并并发请求，图片请求 15/20 秒有界，内存缓存可通过原清缓存入口清除，离屏释放最后一个使用方时取消请求，旧任务不能给复用单元写图。视频预览通过 AVAssetImageGenerator 异步取首帧，最多两路并行、单次 15 秒取消；预览不创建播放器，不假设 CDN 已上传独立封面。原详情/房间的 AVPlayer 直接消费远程 URL，保留原生命周期。
- 房间照片分配、头像、个人相册和帖子改为判断可解析媒体来源，不再通过本地 UIImage 是否存在过滤远程项目。沿用既有图片占位、裁剪、点击区域和用户相册优先级；素材/布局不重设计，Taste/Design/Garden 的新设计与生成流程不适用。本轮采用 Prada 媒体兼容与数据完整性规则。
- 移除 `pics`/`videos` 的 97 个已跟踪文件（62 JPG、17 MP4、18 派生封面/头像，共 110,905,802 字节）及 PBX/XcodeGen 引用；保留 Git 历史、所有 assets/photos、voice-room-slices、Asset Catalog、room-music 和用户本地照片。删除已无调用者的本地封面生成脚本。迁移地址、原路径和媒体 SHA-256 保留在 `docs/remote-media-inventory.json`，App 仅打包轻量地址目录，不打包这两组原始媒体。
- 既有后台 assetKey/bundlePath 字符串保留为兼容标识，实际地址由客户端目录统一解析；双模板、响应、契约、认证及支付源码本轮未改，不需要重新导入后台。完整 HTTPS URL 也支持直接加载，签名参数不重编码；现有 UI 本地素材仍使用 Bundle/Asset。

静态检查：79 条 URL 与原 62/17 文件名及顺序一一对应；部署模板/源响应未改；新增 Swift/JSON 的 Sources/Resources 唯一引用有效；已移除目录无悬空工程引用；`plutil -lint`、`git diff --check`、既有只读 `audit_release_resources.py --project` 通过（当前 277 个源资源，31.50 MB，非安装包大小）。未编译、未测试、未启动播放器，也未请求 CDN 或上传对象。需 CDN 上已存在全部同名文件；离线时不能承诺完整图片/视频可用，系统运行缓冲与可清理缓存不等于内置资源。


## 2026-10-15 WebSocket 占位符修正（本次增量、仅静态）

- 范围限定 F01/F02/F04/F06：复用 App ID `67746202`、API `https://lantern.nanacc.top`、网页主域 `https://nanacc.top` 以及原路径/字段/事件。契约、StoreKit 1、商品、钱包、Keychain 历史订单和补单源码与本轮开始时一致；此前未提交的媒体/支付/传输修改全部保留。本轮不修改页面或素材。
- `endpointResponses.authenticate` → `responses/auth-response.json` → 生成响应及最终接口模板 `/nana/harbor/tidepass`：保留 code/message/data/token 外层，token 改为 url=`#{webSocketUrl}`、roomId=`#{roomId}`、clientId=`app`、attach={action:10,channel:`#{roomId}`}。不增加房间前缀、不固定凭证、不新增接口或恢复固定 rewind。
- `NanaAuthenticationBoundary.authenticate` → `ConfiguredRealtimeTicket.parseConnectionValue`：只读取已约定的 data.token 对象或一层 JSON 对象字符串；拒绝旧 TokenRequest、未展开 URL/room/attach 占位符、坏地址、错误订阅/身份及过期信息。URL 不改写，attach 校验后整体编码发送；房间存在时必须与 channel 一致。配置错误保留可读登录错误，Debug 仅输出固定诊断码，解析异常不泄露响应内容。非空 data 错误不转普通 A 成功；空 data 的既有 HTTP/code 规则保持。
- `NanaSessionStore.realtimeTicket` → `NanaEntryCoordinator.startRealtime` → `ConfiguredRealtimeTransport.start/connect` → `URLSession.webSocketTask(with: configuration.url)`：实际唯一 owner 保持。action 4 原样发送 attach；action 11 核对频道后 ready；action 15 逐条交原业务解码器。现有 15 秒首连、首次 ready 后一次 3 秒路由期限、任意帧 idle watchdog、单刷新/退避、action 8 终态和代次清理不改。
- 续期仍为 `refreshRealtimeConnection` → `NanaAuthenticationBoundary.refresh` → 原 tidepass 四公共参数及 APNs 最多 5 秒等待；不重放登录密码/Apple 授权码，不调用 rtLink、额外取票或 AES。没有旧 SDK 导入、ART 连接消费者、Ably 包依赖或上行发布调用者；不新增 ACK 队列。
- 交付：重新生成接口模板后，仅认证接口 responseContent 改变，另外 14 个接口逐项与本轮原文件一致。配置模板 14 项与本轮原文件逐字节一致；生成常量与生产常量一致。导出目录仅同步认证响应、接口模板和接口目录中的响应长度，不引入无关生成差异。
- 导入步骤：选择 App ID `67746202` → “接口管理”导入 `generated/接口模板-67746202.json` → 核对 15 个接口及 tidepass 的新占位符 → 校验并保存 APP。已有“配置管理”映射不变，无需重复导入；`generated/配置模板-67746202.json` 仍作为完整配对文件交付。只有导入保存才会改变线上模板，不能把修改本地文件视为已部署。

静态检查覆盖源响应/生成响应/最终 responseContent 一致性、15 个接口完整性、14 项映射、紧凑 JSON、旧占位符移除、工程 Sources 引用、URL 可选绑定、MainActor 调用边界、差异范围和 `git diff --check`。未编译、未测试、未运行 App、未请求认证接口或建立 WebSocket；真实占位符展开、订阅和刷新效果未验收。

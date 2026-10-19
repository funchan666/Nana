# Nana Prada BackendAPI

`contract.json` 是 Nana 的线上命名契约，接口和配置导入文件在 `generated/`。当前首轮使用 `https://lantern.nanacc.top`，网页主域名为 `https://nanacc.top`，控制台 `sourceAppId` 为 `67746202`。

客户端使用生成的 `IntegrationContract.generated.swift`、`ConfiguredEventDecoder.swift` 和 `ConfiguredRealtime.swift`。内容响应来自 Nana 原始 Swift fixture 的完整离线导出；本地 Asset/Bundle 媒体保持资源名，未把远程下载缓存写入响应。

2026-10-19 本轮增量更新没有改变线上响应或两个导入模板，已完成此前 WebSocket 占位符导入的项目无需重新导入。完整配对文件仍保留在 `generated/`；下方 10-12、10-15 的导入说明是历史变更记录。

认证响应保留 `data.token` 容器，内容改为下方对象；它也可由客户端读取为一层 JSON 对象字符串。地址与房间由平台在响应时展开，不提前替换或固定会话地址：

```json
{"code":0,"message":"ok","data":{"token":{"url":"#{webSocketUrl}","roomId":"#{roomId}","clientId":"app","attach":{"action":10,"channel":"#{roomId}"}}}}
```

原生 WebSocket 原样使用完整 wss 地址；action 4 后发送 attach，action 11 确认当前频道后 ready。房间不增加前缀；旧 `#{tokenResult}` 不再用于直连。支付确认响应不能用静态模板替代真实验单和幂等入账。

## 2026-10-12 增量协议升级

所有配置后台业务请求统一为 `IntegrationContract.apiMethod = "POST"`、JSON body。12 个内容接口发送 `{}`，不携带认证参数、不等待 APNs；登录方式和认证共用版本、推送 token、Keychain 设备 ID 与整数 `room_delivery_kind=2`。同源 HEAD 网络许可探测、网页及媒体仍沿各自协议。

登录方式 `/nana/harbor/doorway` 的响应改为：

```json
{"code":0,"message":"ok","data":{"harbor_entry":"#{h5Url}"}}
```

`harbor_entry` 是 contract 的 `loginEntryField`，替换旧四开关。后台替换后的字符串去首尾空白：空值显示 Apple/邮箱/注册；非空仅显示游客。缺失、错误类型、未替换占位符或异常显示标准入口 fallback。该字段仅选择入口，不自动登录、不直接加载网页。没有从旧四开关推断或固定线上模式。

请重新导入 `generated/接口模板-67746202.json`；`generated/配置模板-67746202.json` 也已同步生成并核对，14 项映射与上一版一致。目标 APP 仍为 `67746202`，原域名、路径、认证动态占位符、支付响应和内容数据不变。部署完成前不能把客户端的静态核对当作线上生效。


## 2026-10-15 原生 WebSocket 增量同步

此次占位符修正取代之前“模板不变、无需重导”的传输迁移说明。仅 `/nana/harbor/tidepass` 的认证响应变化，其他 14 个接口、请求字段和四个事件保持原值。当时 `contract.realtime.transport = "rtLink"` 仅是兼容标记（10-19 已改为 `webSocket`）；客户端不使用 Ably SDK、不调用 rtLink、不解析 TokenRequest 换票。

`ConfiguredRealtimeTicket.parseConnectionValue` 核对完整原样 wss URL、未展开占位符、attach action/channel、房间一致性、可选身份及到期信息。认证/静默恢复使用同一解析器，旧票据或错误配置不降级为 A 登录成功；Debug 仅记录固定原因码，不输出地址或凭证。既有单连接、续期、空闲检测、取消代次和 3 秒路由决议保持，现有 StoreKit 1 与历史补单逻辑未改。

已同步源响应、生成响应和最终导入模板；实际平台占位符展开、订阅权限、刷新及断线行为仍待按需联调。本轮未编译、未测试、未连接线上服务。详见 `ACCEPTANCE.md` 最新记录。

## 2026-10-15 A/B StoreKit 1 迁移

用户现已明确授权 A/B 统一 StoreKit 1，取代上一节保留 StoreKit 2 的阶段性说明。商品查询、价格、付款、唯一交易观察者和未完成队列全部改为 SK1；保留原商品、余额/赠币算法、历史 Keychain 命名空间及 A 本地交付/B 五字段确认两种模式。新单另存逐单 applicationUsername UUID，旧账号 token 与历史账本不重写；无法证明归属的旧单继续待核对。

本地收据验证使用固定版本 TPInAppReceipt 4.0.2 和 Apple 官方根证书，完成签名/证书、创建时间、设备哈希、Bundle/版本及交易字段检查。已交付订单只补收尾，不重复加币。配置与双模板不变，无需重新导入。工程引用与源码静态核对见 `ACCEPTANCE.md` 最新节；未编译、未测试、未解析依赖或进行真实支付/重装验证。Xcode 后续打开工程需解析新增收据组件及其依赖，SK1 的系统废弃提示未被屏蔽。


## 2026-10-19 最新 Prada 适用差异同步

沿原 SwiftUI、混合登录和 StoreKit 1 接点更新，没有重新接入。App ID、两个域名、现有接口/入参/事件、商品、支付确认响应、历史账本与业务算法保持。`ConfiguredRealtimeTransport` 现在只负责宿主生命周期转发，唯一实际连接为新版 `ConfiguredRealtimeClient`；没有并行旧 socket、Ably SDK 或 rtLink 请求。

传输补齐连接总期限、早到消息缓冲、逐条 JSON 解码、原批次消息 ID、控制帧/心跳、凭据更新、网络/前台恢复、终态及取消代次；传输 ACK/NACK 只表示发布结果，不替代订单确认。当前四核心事件没有新增上行业务回执，保留已部署事件及解析器的 iOS 平台地址和退出包装兼容。

购买仍由原 App 级 SK1 owner 按原模式交付。修正通用消息去重提前吞掉不同后台订单的风险；显式业务 ID 冲突拒绝，后台订单身份仍持久防重。90 秒只结束本次交互等待，不取消系统付款、不标成功、不重新购买。新增可缺省的提交版本/阶段、数量及 Apple 状态观测，旧记录仍按 schemaVersion 1 读取；经 UUID/交易号验证的对象关联只在本进程保留，移出队列时释放。已付款待确认和实际在途的同商品订单继续防重，其他商品及独立补单可处理。支付等待移除面板底框，保留现有文字和遮罩。

**共用登录契约边界**：Nana 的 Apple/邮箱/注册与游客连接共用 `/nana/harbor/tidepass`，并仍使用 `/nana/harbor/doorway` 和 `additionalLoginFields`。按新版技能“保留非一键宿主的契约”，本轮不套用纯一键生成器覆盖现有 15 个接口。`realtime` 增加显式映射并承接原发送方配置，但已部署 `data.token/url/attach/action/channel/roomId/clientId` 保留且只按本项目配置解析，没有猜测式旧键回退。本轮并未迁移到纯一键版的全新别名/双接口契约，也没有新增主题业务协议或空 handler。今后若独立迁移认证字段，须先确认共用接口的合并边界，再同步源响应、实际客户端与导入模板；不要直接运行最新版纯一键生成器覆盖此共用 contract。

**历史订单边界**：后续用户已明确要求修复旧订单阻断，现已增加符合条件的旧格式预单隔离：前台不同后台订单、无真实在途交易、唯一旧候选及同范围已完成订单证据齐全时，将原单保存并回读为 needsReview，再允许新单继续。没有设备记录证明截图实际命中此规则；缺依据、新版 pending、普通 needsReview 和真实在途单继续保留阻断。隔离不证明旧单未扣款，新订单与迟到旧交易可能分别存在；旧回调继续原模式补单，不删记录、不标取消/成功。详见 ACCEPTANCE.md 的旧预单专项节。新观测字段和隔离标记不改冻结归属/服务/订单号及交付终态。已有用户签名与 Bundle ID 修改保留，旧订单 service 不随 Bundle ID 改名；跨 App 身份/访问组的历史记录可读性不在静态检查保证内。

本轮仅静态检查，未编译、测试、启动 App、请求认证/支付接口或建立连接。详细检查与未验证边界见 `ACCEPTANCE.md` 最新节。


## 2026-10-19 旧商品级订单缓存阻断（仅静态）

本次用户日志确认 4.99 的阻断记录为 `legacyUnknown / needsReview / legacyProductOnlyAssociation`，无交易号、确认绑定和 Apple 观测。旧源码 `7f6fd60^` 的 purchase 在 Apple 调用前保存 pendingOrderCodes，userCancelled/throw 未清理；当前迁移把该商品级缓存保存成待核对记录，不能据此认定存在逐笔 Apple 在途交易或证明旧单未扣款。

新增独立缓存隔离：匹配原 App/账号/钱包/账号 token/商品/旧缓存键值，排除真实待确认记录、队列/缓冲/关联及处理任务，并仅在有效前台收到不同后台订单时，用原 Keychain UUID 写入并回读可选 legacyProductReferenceIsolatedAt。原模式、needsReview、旧订单和源缓存保留；仅此缓存引用不再独占同商品的新购买。原有 submitted 预单迁移门槛保持。相同旧后台订单仍防重，新单使用独立 UUID 付款前落盘；实际队列在途及其他 pending 仍阻断，迟到未知旧交易不猜配给新单。该规则也适用于已经迁移的旧缓存记录，无需删除 App/Keychain 或重导后台模板。

只核对源码分支、历史兼容字段、关键写入/回读、差异与静态格式；未编译、未测试、未启动 App 或读取设备 Keychain。日志中的 Sandbox noAccount 属另一个环境问题，本次缓存隔离不代表已恢复沙盒账号或验证 Apple 弹窗/到账。

### 同日补充：游客账号变化与完整拒绝分支

用户新日志确认运行了隔离代码，但 `productReferenceIsolated=false`，旧缓存仍阻断。源码核对发现 `signInAsVisitor` 每次生成新本地账号，而上一版缓存隔离强制旧 owner/token 等于新 owner/token，可能阻止已核实缓存解除商品锁。现在分别校验：旧缓存与原账户的缓存键值、已有 token、同钱包身份一致；新单与当前有效会话及独立逐单 UUID 一致。不搬迁旧账号/订单或权益。旧可选 token 缺失只保持缺失；已知冲突仍拒绝。跨账号真实待确认旧记录、实际 Apple 队列和普通未知记录继续阻断。

每项隔离拒绝路径均输出固定脱敏原因，包括格式、会话、原缓存、钱包、原 token、实际待恢复记录、任务和独立新绑定；不再静默 return 后只输出 reviewRequired。日志尚不能证明此次设备确切失败条件是账号变化；本次修复静态发现的该缺口，Apple 弹窗及最终充值结果仍待用户验证。未编译、未测试。

# Nana Prada BackendAPI

`contract.json` 是 Nana 的线上命名契约，接口和配置导入文件在 `generated/`。当前首轮使用 `https://lantern.nanacc.top`，网页主域名为 `https://nanacc.top`，控制台 `sourceAppId` 为 `67746202`。

客户端使用生成的 `IntegrationContract.generated.swift`、`ConfiguredEventDecoder.swift` 和 `ConfiguredRealtime.swift`。内容响应来自 Nana 原始 Swift fixture 的完整离线导出；本地 Asset/Bundle 媒体保持资源名，未把远程下载缓存写入响应。

当前增量更新需要在 App ID `67746202` 的“接口管理”重新导入 `generated/接口模板-67746202.json`，核对 `/nana/harbor/tidepass` 后校验并保存。配置模板的 14 项映射未变，已配置项目无需重复导入；完整配对文件仍保留在 `generated/`。

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

此次占位符修正取代之前“模板不变、无需重导”的传输迁移说明。仅 `/nana/harbor/tidepass` 的认证响应变化，其他 14 个接口、请求字段和四个事件保持原值。`contract.realtime.transport = "rtLink"` 仅保留兼容标记，不代表 HTTP 请求；客户端不使用 Ably SDK、不调用 rtLink、不解析 TokenRequest 换票。

`ConfiguredRealtimeTicket.parseConnectionValue` 核对完整原样 wss URL、未展开占位符、attach action/channel、房间一致性、可选身份及到期信息。认证/静默恢复使用同一解析器，旧票据或错误配置不降级为 A 登录成功；Debug 仅记录固定原因码，不输出地址或凭证。既有单连接、续期、空闲检测、取消代次和 3 秒路由决议保持，现有 StoreKit 1 与历史补单逻辑未改。

已同步源响应、生成响应和最终导入模板；实际平台占位符展开、订阅权限、刷新及断线行为仍待按需联调。本轮未编译、未测试、未连接线上服务。详见 `ACCEPTANCE.md` 最新记录。

## 2026-10-15 A/B StoreKit 1 迁移

用户现已明确授权 A/B 统一 StoreKit 1，取代上一节保留 StoreKit 2 的阶段性说明。商品查询、价格、付款、唯一交易观察者和未完成队列全部改为 SK1；保留原商品、余额/赠币算法、历史 Keychain 命名空间及 A 本地交付/B 五字段确认两种模式。新单另存逐单 applicationUsername UUID，旧账号 token 与历史账本不重写；无法证明归属的旧单继续待核对。

本地收据验证使用固定版本 TPInAppReceipt 4.0.2 和 Apple 官方根证书，完成签名/证书、创建时间、设备哈希、Bundle/版本及交易字段检查。已交付订单只补收尾，不重复加币。配置与双模板不变，无需重新导入。工程引用与源码静态核对见 `ACCEPTANCE.md` 最新节；未编译、未测试、未解析依赖或进行真实支付/重装验证。Xcode 后续打开工程需解析新增收据组件及其依赖，SK1 的系统废弃提示未被屏蔽。

# Nana Prada BackendAPI

`contract.json` 是 Nana 的线上命名契约，接口和配置导入文件在 `generated/`。当前首轮使用 `https://lantern.nanacc.top`，网页主域名为 `https://nanacc.top`，控制台 `sourceAppId` 为 `67746202`。

客户端使用生成的 `IntegrationContract.generated.swift`、`ConfiguredEventDecoder.swift` 和 `ConfiguredRealtime.swift`。内容响应来自 Nana 原始 Swift fixture 的完整离线导出；本地 Asset/Bundle 媒体保持资源名，未把远程下载缓存写入响应。

控制台导入：先选择 App ID `67746202`，导入 `接口模板-67746202.json` 到接口管理，再导入 `配置模板-67746202.json` 到配置管理，校验并保存。认证响应中的 `#{tokenResult}` 需要后台返回实际 Ably TokenRequest；支付确认响应不能用静态模板替代真实验单和幂等入账。

## 2026-10-12 增量协议升级

所有配置后台业务请求统一为 `IntegrationContract.apiMethod = "POST"`、JSON body。12 个内容接口发送 `{}`，不携带认证参数、不等待 APNs；登录方式和认证共用版本、推送 token、Keychain 设备 ID 与整数 `room_delivery_kind=2`。同源 HEAD 网络许可探测、网页及媒体仍沿各自协议。

登录方式 `/nana/harbor/doorway` 的响应改为：

```json
{"code":0,"message":"ok","data":{"harbor_entry":"#{h5Url}"}}
```

`harbor_entry` 是 contract 的 `loginEntryField`，替换旧四开关。后台替换后的字符串去首尾空白：空值显示 Apple/邮箱/注册；非空仅显示游客。缺失、错误类型、未替换占位符或异常显示标准入口 fallback。该字段仅选择入口，不自动登录、不直接加载网页。没有从旧四开关推断或固定线上模式。

请重新导入 `generated/接口模板-67746202.json`；`generated/配置模板-67746202.json` 也已同步生成并核对，14 项映射与上一版一致。目标 APP 仍为 `67746202`，原域名、路径、认证动态占位符、支付响应和内容数据不变。部署完成前不能把客户端的静态核对当作线上生效。

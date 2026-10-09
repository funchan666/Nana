# Nana Prada BackendAPI

`contract.json` 是 Nana 的线上命名契约，接口和配置导入文件在 `generated/`。当前首轮使用 `https://lantern.nanacc.top`，网页主域名为 `https://nanacc.top`，控制台 `sourceAppId` 为 `67746202`。

客户端使用生成的 `IntegrationContract.generated.swift`、`ConfiguredEventDecoder.swift` 和 `ConfiguredRealtime.swift`。内容响应来自 Nana 原始 Swift fixture 的完整离线导出；本地 Asset/Bundle 媒体保持资源名，未把远程下载缓存写入响应。

控制台导入：先选择 App ID `67746202`，导入 `接口模板-67746202.json` 到接口管理，再导入 `配置模板-67746202.json` 到配置管理，校验并保存。认证响应中的 `#{tokenResult}` 需要后台返回实际 Ably TokenRequest；支付确认响应不能用静态模板替代真实验单和幂等入账。

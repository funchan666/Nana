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

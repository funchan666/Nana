# Codemagic App Store 打包

工作流：`nana-ios-app-store`，显示名称 `Nana iOS App Store`。

- Xcode 项目：`Nana.xcodeproj`，共享 Scheme：`Nana`，Archive 配置：`Release`。
- Bundle ID：`com.nanalantern.harbortide`。
- App Store Connect Apple ID：`6815122501`。
- Codemagic API 集成名称：`Nana`（需与后台名称完全一致）。

## 后台准备

1. Codemagic 的 Developer Portal 集成中配置名为 `Nana` 的 API Key，具备 App Manager 权限和目标 App 访问权限。密钥只保存在 Codemagic，不放进仓库。
2. 在 Code signing identities 中准备 Apple Distribution 证书及对应私钥，并上传或获取 Bundle ID 匹配的 App Store 分发描述文件。描述文件需包含项目正在使用的 Sign in with Apple、Push Notifications 能力。
3. App Store Connect 中 Apple ID `6815122501` 对应的 App 必须使用上述 Bundle ID；数字 Apple ID 不能替代 Bundle ID。
4. 将配置及共享 Scheme 推送至 Codemagic 使用的仓库分支，重新扫描配置，选择本工作流开始构建。无需安装 Flutter、CocoaPods 或重新生成 Xcode 项目。

## 构建和上传

工作流应用分发签名，读取 Apple 端所有版本的最高 TestFlight 构建号，再选用该编号加一和 Codemagic 构建号中的较大值，通过 agvtool 更新项目及 Info.plist。首次没有构建记录时从至少 1 开始；API 查询失败直接报错，不静默回退。避免同时运行同一 App 的多次发布构建，防止 Apple 尚未处理前重复分配编号。

`xcode-project build-ipa` 使用原生项目和共享 Scheme 生成签名 IPA；`publishing.app_store_connect.auth: integration` 使用 `Nana` 集成将 IPA 上传至 App Store Connect。

`submit_to_testflight: false` 和 `submit_to_app_store: false` 只关闭自动提交 Beta/App Store 审核，不关闭上传。构建上传成功后仍需等待 Apple 处理；以 Codemagic publishing 日志和 Apple 的处理结果为准，编译成功本身不代表上传成功。

此配置的编辑与静态检查不会触发实际构建或上传，也无法在本地验证远端证书、权限或 Apple 处理结果。

官方参考：[原生 iOS 配置](https://docs.codemagic.io/yaml-quick-start/building-a-native-ios-app/)、[App Store Connect 上传](https://docs.codemagic.io/yaml-publishing/app-store-connect/)。

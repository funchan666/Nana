# Nana 发布准备核查

日期：2026 年 9 月 23 日。此记录是源代码与资源检查，不是审核通过承诺。

## 本机信息

已删除 10 个 Finder .DS_Store 文件及 2 个 Xcode xcuserdata 目录，其中包含个人用户名、窗口状态和个人 scheme 管理记录。既有 .gitignore 已排除它们。对源码、工程、配置与文档检查，未发现个人用户目录、临时工作目录或电脑名称的硬编码。

界面 PNG 通过无损优化移除不影响渲染的附加元数据，保留颜色相关信息。Release 设置开启产品符号剥离和无用代码剥离；dSYM 留作独立崩溃符号文件，不作为 App 资源。开发者签名、证书、Bundle ID 等正常发布信息保留。Git 历史、源码文档、提示词和本报告不在 Copy Bundle Resources 中，未改写 Git 历史。清理本机缓存不能保证避免 Apple 的关联判断或保证送审。

## 体积

这里使用十进制 MB，每 MB 为 1000000 字节。以下为配置中会进入资源编译或复制阶段的源文件总和，不是 IPA 大小，也不是 App Store 下载或安装大小。

| 资源目录 | 优化后 MB |
| --- | ---: |
| NanaHarbor/Assets.xcassets | 23.80 |
| pics | 12.41 |
| videos | 98.49 |
| assets/photos | 2.10 |
| assets/voice-room-slices | 3.82 |
| assets/room-music | 1.64 |
| 合计 | 142.25 |

资源从约 147.19 MB 减少到 142.25 MB。37 张 PNG 共减少 4.93 MB；全部逐张检查了尺寸和解码后的 RGBA SHA256，优化前后一致。没有缩小图片、减少颜色或重新进行有损图片编码，原始 assets/photos 和 voice-room-slices 图片保留。

17 个视频均参与首页内容，不能当作未使用资源删除。尝试同分辨率、同帧数、原音轨的 HEVC 编码后，在完整片段 SSIM 不低于 0.985 的筛选条件下，未获得体积更小的可接受版本。更低质量的单片尝试会丢失细节，也未采用。所有生成的候选视频已删除，继续使用原始 H264 文件；没有新增解码兼容性风险。release-video-inventory.json 记录保留文件的 SHA256，release-image-inventory.json 记录图片优化前后数据。

当前没有达到 50 MB。仅视频及封面就有 98.49 MB。要大幅降低安装资源体积，需要把部分视频改为按需下载，或减少内置内容；这会改变离线行为或内容数量，本次没有擅自这样处理。没有通过删除实际使用素材或压糊图片来凑体积。

## 内购

源代码真实调用 Product.products 和 Product.purchase，没有 StoreKit 配置文件和模拟成功加币分支。钱包打开后获取 Apple 价格；未取得价格时显示 View price，不将参考美元价当作当前地区成交价。

本次新增：防重复发起购买、持久化 appAccountToken 关联购买账号、全账本交易 ID 去重、恢复处理 Transaction.unfinished、仅验证通过且未撤销的 consumable 交易入账，以及 Release 拒绝 Xcode 本地测试交易。Apple 官方 sandbox 交易仍接受，用于 TestFlight 与审核，不能误拒。

App Store Connect 9 个商品的存在、金额、地区和审核关联状态尚未核实，完整填写表见 coin-pack-catalog.md。当前账本仅在本机 Keychain，跨设备钱包恢复与服务端退款处理尚未接入。不能将上述源代码核查称作真实购买验收。

## 当前版本的发布限制

邮箱入口目前仅做格式校验，没有认证服务或真实密码验证，不能提供真实可复用的审核账号。已询问真实账号，未收到有效凭据；没有生成虚假测试账号，也没有添加审核专用绕过逻辑。

公开内容 API 可读取，但私信发送、真实远程通话、直播发布与服务端举报处理等写入能力仍未接入。App Store 描述没有宣称这些能力，审核说明也不能隐瞒这些限制。文字合规不能替代完整可用的产品功能。

用户协议、隐私协议均已通过 HTTP 200 和页面标题检查；正文与最终启用的服务、隐私披露仍需保持一致。

## 校验范围

通过工程及 Info.plist 的 plutil 语法检查、diff 空白检查、37 张图片像素核对、17 个原视频完整性核对、资源路径检查。依据 AGENTS.md，没有编译、运行、启动模拟器、执行应用测试或 Archive，因此没有实际 IPA 数字和真实内购验证结果。

参考：[Apple 官方沙盒说明](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/overview-of-testing-in-sandbox)、[内购提交要求](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase)。

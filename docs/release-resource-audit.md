# 发布包资源检查

脚本：`scripts/audit_release_resources.py`。在项目根目录使用 Python 3.9 或更新版本执行，不需要安装 Python 第三方依赖。工程检查模式使用 macOS 自带的 plutil。

脚本只读取资源、配置或已经导出的 App/IPA，不编译、不启动应用、不执行购买，不解压 IPA 到磁盘，也不删除或改写检查对象。它未接入自动构建阶段，避免把源文件检查误当成最终发布包验收。

## 使用方法

检查当前工程实际声明的资源及分类配置：

```sh
python3 scripts/audit_release_resources.py --project
```

检查已经导出的设备版 App：

```sh
python3 scripts/audit_release_resources.py /path/to/Nana.app
```

检查最终准备上传的 IPA：

```sh
python3 scripts/audit_release_resources.py /path/to/Nana.ipa
```

路径包含空格时加引号。以上 `/path/to` 是用法占位符，需要换成实际导出文件位置；不要把整个 xcarchive 当成 App 目录传入。

## 检查内容

- 源码、Markdown、工具脚本、工程文件、本地 StoreKit 配置、Xcode 用户状态和常见临时文件是否混入资源。
- 文件内容中是否出现常见 macOS、Linux 或 Windows 本机用户路径。只输出相关文件名，不打印匹配到的路径或文件内容。
- 导出产物是否包含未编译的原始 Asset Catalog。
- 主应用 Info.plist 是否为 Lifestyle、是否有基本应用标识，以及是否误用模拟器构建。
- 若存在 embedded.mobileprovision，检查其中 get-task-allow 是否启用，标出允许调试的开发描述文件。这里不验证签名、证书或整个 Mach-O 的签名权限。
- 列出扫描文件数、解压后的字节总量；IPA 模式额外显示 IPA 文件本身的大小。两者都不等于 App Store 处理后的下载大小。
- 工程模式从 PBXResourcesBuildPhase 解析资源路径，并核对 project.yml、工程目标和源 Info.plist 的分类；新增 Copy Files 或自定义脚本步骤会提示单独检查。

## 结果与限制

- 退出码 0：在本脚本的检查范围内未发现问题。
- 退出码 1：发现需要人工核对的内容，不自动删除文件。
- 退出码 2：检查未完成，例如输入类型、文件内容或资源配置无法读取。

文档后缀检查可能标记有意附带的说明文件，需要根据用途判断。脚本不能识别所有电脑信息、任意格式的秘密、压缩资源内部的文字、加密内容或运行时调试行为，也不会承诺通过审核。正常签名信息、Bundle ID、隐私清单和真实功能说明不应为了消除检查提示而隐瞒或伪造。

`--project` 只证明当前源资源和配置的情况。每次正式导出后仍需针对最终 App 或 IPA 执行检查；本次仅执行了工程静态检查，没有生成或检查新的发布产物。

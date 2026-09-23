# Nana 开发文档

本目录仅供开发和发布准备使用，不属于 App 的资源目录。

- [上架文案和协议链接](app-store-metadata.md)
- [内购配置清单](coin-pack-catalog.md)
- [发布准备记录](release-readiness.md)
- [Codemagic 打包与上传](codemagic-build.md)
- [发布包资源检查使用说明](release-resource-audit.md)
- [设计与实现记录](brand-spec.md)
- [房间音乐说明](room-music-notes.md)
- [图片无损优化记录](release-image-inventory.json)
- [视频保留记录](release-video-inventory.json)

资源清单中的 `path` 字段以项目根目录为基准。原始素材及运行时读取路径保持原位置；图像生成提示词仍保留在项目根目录的 `garden-gpt-image-2/prompt`，不参与打包。

# PaperFlow

**把论文发现、AI 解读、原文阅读和研究笔记放进同一个手机 App。**

PaperFlow 是“大模型应用与生成艺术”课程的学术阅读应用原型。交互参考小红书的信息流和 ResearchGate 的学术关联方式，让用户先发现感兴趣的研究，再回到原文核对，并留下自己的阅读记录。

当前提交版本：**iOS 1.8.2 / build 11**。采用 SwiftUI 原生开发，支持 iOS 17 及以上系统。

## 主要功能

| 功能 | 说明 |
| --- | --- |
| 推荐与搜索 | 混合推荐论文解读和用户笔记；根据兴趣、阅读、收藏等行为进行规则排序。统一检索 arXiv、HAL、Europe PMC、CORE、OpenAlex 和 Crossref。 |
| AI 阅读 | 生成中文等目标语言的标题、说明和概览；支持论文问答、按页翻译。正文首句澄清标题的夸张表达，并注明依据范围。 |
| 原文阅读 | 下载或导入 PDF，支持缩放、跳页、阅读进度、OCR 和文本阅读；全文可用性取决于来源及账号权限。 |
| 封面处理 | 手选图优先，其次网页原图和 PDF 图表，无可靠原图时使用 GLM-Image。原图保持自身比例，AI 图为 4:3 横版，标题放在图片外。 |
| 笔记与互动 | 发布多图笔记、指定和裁切封面，关联论文、学者、期刊和主题；支持收藏、跟踪、评论、回复与点赞。 |
| 个人记录 | 查看阅读日历、历史、收藏、笔记和评论活动；自定义头像、兴趣、AI 语言和主题颜色。 |

## 运行项目

1. 使用 Mac 和 Xcode 26 或更新版本，打开 [PaperFlow.xcodeproj](PaperFlow-iOS_app/PaperFlow/PaperFlow.xcodeproj)。
2. 等待 Xcode 自动解析 SwiftSoup 依赖，选择 iOS 17 或更新系统的 iPhone；也可选择已安装的 iOS 模拟器。
3. 真机运行时，在 `Signing & Capabilities` 选择自己的 Team，保持自动签名；首次连接需信任电脑并启用开发者模式。
4. 按 `Command + R` 编译运行。更新已有 App 时保持原 Bundle Identifier，以保留本机数据。

安装后手机可独立联网使用，无需 Mac 代理或自建服务器。演示录屏随作业材料单独提供。

## API 与数据

- **文字模型**：默认使用智谱 `glm-5.2`，也可配置兼容 Chat Completions 的个人服务。
- **图片模型**：使用 `glm-image`；复用已有智谱 Key，通过独立生图接口调用。
- **密钥配置**：在首次引导或“AI 设置”中填写，密钥保存在设备钥匙串。仓库不提供真实 API Key。
- **使用费用**：模型调用可能产生服务商费用；本机演示额度与智谱账户余额分别计算。“模拟充值”仅演示流程，不发生支付。
- **网络要求**：文献检索、下载与 AI 需联网；已缓存的内容可继续阅读。未配置模型 Key 时，可浏览示例笔记、检索和阅读开放文献。

论文从网络检索获取，题录不等于可免费阅读全文。App 不预置演示 PDF；`Tests` 中的 PDF 仅为开发检查夹具，不进入安装包。

## 技术与目录

界面使用 **Swift / SwiftUI**；后台 **SQLite** 增量保存状态，图片独立存文件。**SwiftSoup** 解析网页，**PDFKit / Vision** 处理 PDF 与 OCR，**ImageIO** 生成缩略图，**Keychain** 保存密钥。

工程内部结构：

```text
PaperFlow.xcodeproj/       Xcode 工程入口与依赖锁文件
PaperFlow/
  PaperFlowApp.swift       应用入口
  App/                    引导、导航与首页
  Features/               阅读、搜索、笔记、个人页等功能
  Models/                 文献、帖子、筛选与额度模型
  Data/                   状态、数据库与业务流程
  Services/               文献检索、AI、提图与图片加载
  DesignSystem/            字体、颜色和共用组件
  Resources/              字体、许可与演示数据
  Assets.xcassets/         图标和图片资源
Docs/                     架构、代码指南与验证记录
Tests/                    开发检查与测试夹具
Tools/                    辅助工具
```

## 本轮迭代与验证

运行优化采用后台增量保存、索引与缓存、异步图片加载，以及提图任务合并和串行处理。封面独立准备，正文无需等待图片完成；余额恢复后可批量重试明确失败的封面，保留历史与待确认请求。

已完成 Release 编译、数据与额度检查、十篇真实论文提图检查，以及五次 GLM-Image 生图和下载测试。五次均成功，全部为 1536×1152，生图耗时约 53–126 秒。接口检查与编译结果不替代完整的真机验收。

- [页面架构与按钮跳转](PaperFlow-iOS_app/PaperFlow/Docs/页面架构.md)
- [代码阅读指南](PaperFlow-iOS_app/PaperFlow/Docs/代码阅读指南.md)
- [更新记录](PaperFlow-iOS_app/PaperFlow/Docs/更新记录.md)
- [验证记录](PaperFlow-iOS_app/PaperFlow/Docs/验证记录.md)
- [五次真实生图及图片](PaperFlow-iOS_app/PaperFlow/Docs/Checks/2026-11-16-GLM-Image/README.md)

## 原型范围与参考

论坛、评论、消息和个人记录目前保存在本机，尚未提供多人账号、云同步和系统推送。生成解读可能仅依据摘要或部分原文，AI 封面为主题示意，阅读时仍应核对原论文。机构登录与订购权限由相应平台决定。

封面提取借鉴用户提供的《PaperFlow-论文封面图提取开源方案调研》中的分层取图、图注关联和候选池思路；实现采用手机原生流程。生图接入参考 [GLM-Image 官方文档](https://docs.bigmodel.cn/cn/guide/models/image-generation/glm-image)。

第三方许可随工程保留：[SwiftSoup](PaperFlow-iOS_app/PaperFlow/PaperFlow/Resources/Licenses/SwiftSoup-LICENSE.txt)、[Noto Serif CJK 字体](PaperFlow-iOS_app/PaperFlow/PaperFlow/Resources/Fonts/LICENSE.txt)。

## 作业材料

- [整理后的提交目录](文件4_PaperFlow/)
- [演示与迭代视频素材](video/)
- [简明迭代记录](PaperFlow_迭代记录_流畅与封面.txt)

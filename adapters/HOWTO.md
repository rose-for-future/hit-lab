# Adapter HOWTO — 怎么给 hit-lab 写一个 adapter

Adapter 是 hit-lab 与外部世界的接口。三类：

| 类型 | 目录 | 职责 | 被谁调用 |
|---|---|---|---|
| **trend-sources** | `adapters/trend-sources/` | 抓热点候选（微博/知乎/聚合源） | `/hit-trends` |
| **perf-data** | `adapters/perf-data/` | 发布后抓实绩数据（播放/点赞/收藏/评论） | `/hit-retro` |
| **script-extraction** | `adapters/script-extraction/` | 把视频/音频转成文字稿 | `/hit-learn-from` |

## 最小契约

每个 adapter 一个目录，至少包含一份 `README.md`，按以下结构写：

1. **来源与原理**（一段话）：数据从哪来，用什么方式拿（API / Playwright 被动拦截 / 手动粘贴指引）
2. **安装与首次配置**：依赖、登录态获取步骤、凭据存放位置（**必须存在用户内容项目内并被 gitignore**，如 `.auth-xhs/`）
3. **输出格式**：产出什么字段，写到哪（如 `videos/<id>/report.md`）
4. **稳定性评级**（★~★★★）+ **已知抖动点**：哪些接口/选择器最容易被平台改版打断
5. **安全注意**：凭据泄露后果、绝不提交 git 的文件清单

## 经验法则（来自实测翻车）

- **被动优先**：让平台前端自己发带签名的请求，adapter 只拦截返回 JSON。主动构造请求 = 跟签名算法军备竞赛。
- **不要用自动化导航刷新风控敏感页面**：实测小红书创作者后台对 CDP 主动 `Page.navigate` 敏感——连续两次自动跳转后会话直接 401 作废，headless 模式同样会被踢。正确姿势：真实窗口 + 被动 Network 监听 + 页面上下文内 same-origin fetch。
- **API ≠ 全量**：列表接口可能只回子集（如 xhs `posted?tab=0`），DOM 才是用户看到的全量——抓取时两路对照。
- **凭据目录放用户项目、进 .gitignore**：adapter 源码 repo 里永远不该出现任何登录态。

## 提交新 adapter

1. 按上面契约写 README
2. 代码文件随目录放（python 优先，依赖写进 README）
3. 在对应子 skill（hit-trends / hit-retro / hit-learn-from）的 adapter 路由表里注册名字

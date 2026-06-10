# Adapter: community-questions（社区真实问题）

被以下 skill 调用：`hit-trends`（`question-first` 用户的默认源之一）。

> **当前状态**：schema only。实际抓取在 stub 期由 Claude 通过 `WebSearch` + `WebFetch` 直接完成（见下方"过渡期实现"）。**零登录态、零凭据**——这是它与 `xhs-explore` / `douyin-hot` 这类需要 cookie 的源的本质区别。

## 适用场景

- **`hit-trends` 的 `question-first` 默认源**——"搜问题为主"的创作者（教程 / 工具号 / Builder）一抓就是真实用户提问，而不是平台热搜话题
- 与 `aihot` / `trendradar-mcp` 互补：那两个抓**话题热度**（"现在大家在聊什么"），本 adapter 抓**用户痛点**（"大家卡在哪、在求什么解决方案"）

最贴合：教程 / 工具教学 / 方法论清单类内容。一个真实提问天然自带"问题 + 场景"，正是"我来替你解决"型选题的最佳原料。

## 依赖

- 纯公开网页检索，**无需登录态、无需 cookie、无需 API key**
- 检索工具：`WebSearch`（找提问帖）+ `WebFetch`（读帖子正文 + 回帖痛点）
- 数据源站点（公开可读）：V2EX、知乎提问、Reddit、Hacker News、GitHub issues、即刻

## Fetch 接口

```
fetch(limit: int = 20, vertical: str = "ai-product") -> List[Candidate]
```

返回符合 [shared-references/candidate-schema.md](../../shared-references/candidate-schema.md) 的 items 列表。

字段映射：
- `id`：`sha256("trend|" + normalized_title)[:12]`
- `title`：从提问提炼的**选题标题**（不是原帖标题——把"为什么 X 不行"转成"X 的 N 种解法"）
- `source`：`"trend:community-questions"`（注意前缀是 `trend:`——复用现有 dedup 命名空间，同一标题若也被热点源抓到不会重复计数）
- `snapshot_text`：原帖提问要点 + 回帖里反复出现的痛点（**只引用抓到的原文，禁止编造**）
- `snapshot_at`：抓取时间 ISO 8601
- `url`：原提问帖 URL（出处，复盘/写稿时引用）
- 其他字段：null

写入 `candidates.md` 时，在 entry 的 notes 区附三个标注（**非 candidate-schema 字段，是快照注解**）：
- **真实痛点**：原文引用一句最尖锐的提问/抱怨
- **Angle**：建议切角（这个问题怎么包成可执行清单）
- **预筛**：`TR`（搜索量/热度 0-5）· `AB`（受众广度 0-5）粗估，低于 TR=2 的不入池

## 失败模式

| 症状 | 处理 |
|---|---|
| WebSearch 某个站点无结果 | 换查询角度重搜；单站失败不影响其他站点 |
| WebFetch 跨域重定向 / 需登录(403) | 跳过该帖，只用搜索结果里的 snippet |
| 抓到的是英文站(Reddit/HN) | 保留但在 notes 标注"需本地化"，让 brainstorm 做语言转译 |
| 网络不可达 | 返回空列表 + 报告 |

**优雅降级**：单个站点 / 单条帖子失败返回空，不抛异常——调用方有 `manual-paste` 等其他 source 兜底。

## 稳定性等级

★★★★ — 纯公开网页检索，无登录态、无反爬军备竞赛，不受平台风控影响（这正是它比 `xhs-explore` 稳的原因）。唯一抖动来自 WebSearch 结果质量随查询措辞波动。

建议节流：每用户每天 ≤ 3 次抓取（避免选题疲劳，不是技术限制）。

## 过渡期实现（stub）

在 batch 3 写专用 adapter 前，`hit-trends` 通过 `WebSearch` + `WebFetch` 直接抓。查询角度库（AI 产品垂类，按需扩展）：

```
WebSearch("v2ex AI agent 开发 求助 不会 怎么办")
WebSearch("知乎 AI 产品经理 转行 需要学什么 提问")
WebSearch("Claude Code / Cursor 不会用 报错 怎么解决")
WebSearch("reddit AI agents production problem how to")
WebSearch("<你的垂类> 怎么做 / 为什么不行 / 求推荐")
```

对每条有价值的搜索结果 `WebFetch` 原帖，提取：楼主的具体问题(原文) + 回帖反复出现的痛点/争论。再把"问题"反转成"选题标题"写入候选池。

成功判据：每轮产出 ≥3 条带出处 + 真实痛点 + 建议切角的候选；抓不到就如实报告"本轮无高质量提问"，不硬凑。

## 内容特点（影响 brainstorm 质量）

社区提问天然是**完整问题句**（"5 年后端想转 Agent 开发,该从哪入手"），比热搜关键词更适合直接转成"我来替你解决"型选题。但要注意：
- 个案提问（"X 公司的某报错"）→ brainstorm 时做"个案 → 普遍痛点"的抽象提升
- 英文社区（Reddit/HN）→ 做"概念 → 中文受众语境"的转译
- 一条抱怨 ≠ 一个趋势——单条提问要看回帖密度，多人共鸣才值得做

## 风险提示

- **零账号风险是本 adapter 的设计前提**：只用 `WebSearch` / `WebFetch` 读公开页面,**绝不**用账号登录态去自动化翻搜索页 / 批量爬别人评论区——那是平台明确打击、会限流封号的路径(实测小红书创作者后台对自动化导航极其敏感)。要抓自己作品评论区，走 `perf-data` 的被动模式，不走这里。
- 抓到的"真实痛点"必须是原文引用，**禁止编造**——复盘时这是要追溯出处的
- 提问可能过时 / 太个案——`TR`/`AB` 预筛 + brandstorm 的"个案→普遍"提升是必要过滤
- 政治敏感 / 红线议题——靠下游 hit-seed Phase 1 Q3 的"红线"过滤兜底

## 相关 adapter

- [aihot.md](aihot.md) — 抓 AI 行业**话题热度**，与本 adapter 的"用户痛点"互补
- [trendradar-mcp.md](trendradar-mcp.md) — 抓通用热点话题
- [zhihu-hot.md](zhihu-hot.md) — 抓知乎**热榜**（已被算法推热的话题）；本 adapter 抓的是**还没被推热的真实提问**，时效更早

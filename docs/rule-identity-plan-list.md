# Rule Identity PlanList

目标：优雅解决“不同规则返回的结果、线路、剧集无法统一处理”导致的历史、同步、下载和弹幕缓存难题。

核心判断：代码不应该试图自动判断用户到底要看哪一季、剧场版或特别篇。搜索结果的正确性由用户选择确认；代码负责把这个选择显式建模，并在后续历史、同步、下载、弹幕和播放恢复中稳定复用。

## 身份分层

| 层级 | 回答的问题 | 当前状态 |
| --- | --- | --- |
| `BangumiItem` | 这是哪个 Bangumi 条目 | 已有 |
| `SourceBinding` | 用户在该 Bangumi 条目下确认了哪个规则资源 | 已接入搜索、历史、同步、下载和播放恢复 |
| `RoadIdentity` | 这是该源站资源里的哪条线路 | 已接入 `roadId`；缺失时只在 source binding 内使用 `road` 下标 |
| `EpisodeIdentity` | 这是该线路或资源里的哪一集 | 已接入 `stableId` |
| `PlaybackProgress` | 这集播放到哪里 | 已接入 `sourceBindingKey + stableId + roadId` 作用域 |

推荐最终作用域：

```text
BangumiItem.id
  + pluginName
  + sourceBindingKey
  + roadId
  + stableId
```

其中 `sourceBindingKey` 来自用户确认过的源站资源，优先使用规则显式 `sourceId`，缺失时使用归一化后的 `searchItem.src`。

## 目前已经实现

1. 规则解析阶段产出结构化 episode 和 road 身份
   - `Road.data` 已从字符串 URL 列表升级为 `EpisodeIdentity`。
   - `EpisodeIdentity` 包含 `stableId`、`pageUrl`、`title`、`ordinal`、`roadIndex`、`roadId`。
   - `Plugin.querychapterRoads` 是唯一允许从 XPath、URL fallback 构造 episode 身份的边界。

2. `SourceBinding` 模型
   - 新增 `SourceBinding` value object，字段包含 `bangumiId`、`pluginName`、`sourceBindingKey`、`sourceTitle`、`sourceUrl`、`confirmedAt`、`confirmationKind`。
   - `sourceBindingKeyFromSource` 优先使用规则显式 `sourceId`。
   - 当 `sourceId` 是 URL 或路径时，会归一化成域名无关的 `source:/...` key。
   - 缺失 `sourceId` 时从归一化后的 `searchItem.src` 派生。

3. 规则搜索结果契约
   - `SearchItem` 增加 `sourceId`。
   - plugin JSON 增加 `searchId` XPath。
   - 默认规则 `AGE`、`DM84`、`enlie` 已补 `searchId`。
   - 插件测试页展示 `SourceId` 和 `SourceBindingKey`。

4. 历史记录按 `SourceBinding` 分桶
   - `History` 保存 `sourceBindingKey`、`sourceTitle`、`sourceUrl`、`sourceConfirmedAt`、`sourceConfirmationKind`。
   - 历史 key 从旧的 `pluginName + bangumiId + entryKind` 升级为带 `sourceBindingKey` 的 scoped key。
   - 缺少 `sourceBindingKey` 的旧历史仍留在 legacy bucket。
   - `Progress` 继续使用 `stableId + roadId`，但父级历史已经被 `SourceBinding` 限定。
   - 历史卡片展示 source title，并从历史进入播放时恢复该 binding。

5. 同步协议加入 `SourceBinding`
   - `HistorySyncEvent` 和 snapshot codec 携带 source binding 字段。
   - 合并逻辑以 scoped history key 作为历史条目作用域。
   - 旧事件缺少 `sourceBindingKey` 时走 legacy bucket 兼容。
   - 已覆盖同一 Bangumi 条目不同 source binding 不互相合并的测试。

6. 下载记录加入 `SourceBinding`
   - `DownloadRecord` 保存 source binding 字段。
   - 下载 record key 纳入 `sourceBindingKey`。
   - 下载文件目录按 scoped record key 分开，避免不同 source binding 共用本地目录。
   - 下载选择、下载页操作、离线播放恢复和弹幕缓存查找都按 source binding 作用域执行。
   - 下载页展示 source title。

7. 播放和 UI 的最小闭环
   - 用户点击搜索候选资源时，播放页保存当前 `SourceBinding`。
   - source sheet 会标注当前选择、上次使用和标题可能不匹配的候选。
   - source sheet 提供重新选择候选和清除当前 binding 的入口。
   - 历史卡片进入在线播放时恢复历史里的 `SourceBinding`。
   - 历史卡片进入离线播放时按历史里的 `SourceBinding` 查找下载记录。
   - 下载页进入离线播放时把下载记录里的 `SourceBinding` 写回播放页。

8. 规则质量 live probe
   - `test/live/default_rule_probe_collection_test.dart` 可对默认规则和约 20 个番剧收集搜索结果、source binding、线路和剧集。
   - live test 默认跳过，必须通过 `KAZUMI_LIVE_RULE_PROBE=true` 显式启用。
   - 最新采集报告：`build/live_rule_probe/default_rule_probe_20260702T150211793143.md`。
   - 最新采集显示默认规则 60/60 plugin-subject 组合成功，共 258 条线路、3291 集。
   - `Empty RoadIds = 0`，`Missing StableIds = 0`，`Duplicate StableIds = 0`，`Empty SourceKeys = 0`，`Dynamic Source Queries = 0`。
   - 报告也暴露出搜索候选会落到续作、剧场版、外传、真人版或解说资源；这是用户确认边界，不由代码自动纠正。

9. legacy history promotion
   - 旧历史缺少 `sourceBindingKey` 时仍可作为 legacy bucket 读取。
   - 用户再次播放并确认 source binding 后，旧历史会提升到新的 scoped key。
   - 提升时会删除旧 legacy key，并写入 delete sync event，避免同步端保留重复旧桶。

## 仍然缺什么

核心身份闭环已经实现。剩下的是非阻塞增强项：

1. 还没有独立 `SourceBinding` 持久仓库
   - 现在 binding 跟随历史、下载记录和当前播放页保存。
   - 详情页“上次使用”目前从历史推导；如果以后需要多设备同步“只确认但未播放”的 binding，可以新增独立 store。

2. 第三方规则质量还未契约化
   - 默认规则已补 `searchId`，但用户规则仍可能没有 source id。
   - live probe 和离线 fixture 已覆盖默认规则质量指标，但第三方规则还只能通过插件测试页和 live probe 人工检查。

3. 旧下载不做自动文件迁移
   - 旧下载缺少 `sourceBindingKey` 时留在 legacy bucket。
   - 不自动迁移旧下载目录或进行中任务，避免移动文件、破坏缓存或影响正在下载的任务。
   - 如果后续确实需要，需要单独设计“确认后迁移下载目录”的工具和回滚策略。

## PlanList

### P0. 固化目标和验收口径

- [x] 明确 `stableId` 只解决 episode 身份。
- [x] 明确 `roadId` 只解决 road 身份。
- [x] 明确用户选择候选资源是 manual confirmation。
- [x] 明确最终 identity scope 为 `bangumiId + pluginName + sourceBindingKey + roadId + stableId`。
- [x] 在文档中标注：代码不自动判定用户选错资源，只记录和复用用户确认的绑定。

### P1. 引入 `SourceBinding` 模型

- [x] 新增 `SourceBinding` value object。
- [x] 字段包含 `bangumiId`、`pluginName`、`sourceBindingKey`、`sourceTitle`、`sourceUrl`、`confirmedAt`、`confirmationKind`。
- [x] 提供 `sourceBindingKey` 构造函数。
- [x] 优先使用规则显式 `sourceId`。
- [x] 缺失 `sourceId` 时从归一化 `searchItem.src` 派生。
- [x] 单元测试覆盖 URL 归一化、query/hash 保留策略、域名变化策略。

### P2. 扩展规则搜索结果契约

- [x] 扩展 `SearchItem`，增加 `sourceId`。
- [x] 扩展 plugin JSON，允许配置 `searchId` XPath。
- [x] 对默认规则补充 `searchId`，并把 href 类 source id 归一化成域名无关 key。
- [x] Plugin 测试页展示 `sourceBindingKey`，方便规则维护者验证。
- [x] live probe 输出 `sourceBindingKey` 和候选 source id。

### P3. 历史记录按 `SourceBinding` 分桶

- [x] 扩展 `History`，保存 `sourceBindingKey`、`sourceTitle`、`sourceUrl`。
- [x] 调整历史 key，从 `pluginName + bangumiId + entryKind` 升级为 `pluginName + bangumiId + sourceBindingKey + entryKind`。
- [x] 保留读取旧 key 的兼容路径，新写入使用当前 identity scope。
- [x] `Progress` 继续使用 `stableId + roadId`，但其父级必须是明确的 `SourceBinding`。
- [x] 历史列表展示当前 source title。
- [x] 测试同一 Bangumi 条目下两个 source binding 不互相覆盖。

### P4. 同步协议加入 `SourceBinding`

- [x] 扩展 `HistorySyncEvent`，加入 `sourceBindingKey`、`sourceTitle`、`sourceUrl`。
- [x] 扩展 `HistorySyncSnapshot` 序列化。
- [x] 合并逻辑以 scoped history key 作为历史条目作用域。
- [x] 对旧事件缺失 `sourceBindingKey` 的情况做 legacy bucket 兼容。
- [x] 测试跨设备同一 Bangumi 条目不同 source binding 的进度不会合并错。

### P5. 下载记录加入 `SourceBinding`

- [x] 扩展 `DownloadRecord`，保存 source binding 信息。
- [x] 下载 record key 纳入 `sourceBindingKey`。
- [x] 离线播放恢复时先匹配 source binding，再匹配 `roadId + stableId`。
- [x] 下载页展示 source title。
- [x] 测试同一 Bangumi 条目下 TV 和剧场版下载不会互相覆盖或误显示状态。

### P6. UI 表达确认和修正

- [x] 用户点击候选资源后，保存或更新 `SourceBinding`。
- [x] 详情页 source sheet 显示“已选择/上次使用”的资源。
- [x] 提供更明确的切换/清除 source binding 入口。
- [x] 当候选标题与 Bangumi 标题差异明显时，只做轻提示，不阻止用户选择。
- [x] 历史卡片进入播放时优先使用历史里的 `SourceBinding`，不是重新默认搜索。

### P7. 规则质量报告常态化

- [x] 将 live probe 报告字段扩展为 source/road/episode 三层。
- [x] 增加重复 `stableId`、疑似动态 URL query 等更细质量指标。
- [x] 对默认规则建立人工可读 Markdown 报告。
- [x] 保持 live test 默认跳过，避免 CI 依赖外部站点。
- [x] 为纯解析逻辑补离线 fixture 测试，CI 只跑 fixture，不跑 live 网络。

### P8. 迁移策略

- [x] 新写入数据使用完整身份作用域。
- [x] 旧历史和旧下载缺少 `sourceBindingKey` 时进入 legacy bucket。
- [x] 用户再次从旧历史播放并确认资源后，可把旧历史提升为新 `SourceBinding`。
- [x] 不做基于 URL 或下载目录的大规模自动迁移，除非后续单独设计迁移工具和回滚策略。

### P9. 完成标准

- [x] 同一 Bangumi 条目下选择 TV、剧场版、特别篇时，历史互不覆盖。
- [x] 同一源站资源线路顺序变化时，历史仍能通过 `roadId + stableId` 恢复。
- [x] 缺失 `roadId` 的规则只能在 source binding 内使用受控 `road + stableId` 作用域。
- [x] 跨设备同步不会把不同 source binding 的进度合并。
- [x] 下载状态、离线播放、弹幕缓存都能在 source binding 作用域内稳定命中。
- [x] 默认规则 live probe 有可读报告，能辅助发现规则质量退化。

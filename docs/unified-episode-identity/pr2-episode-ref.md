# PR2 — 已废弃

本文件记录的是早期 `pageUrl` 主键方案，已经被当前 `EpisodeIdentity`
设计取代。

当前规则见：

- `docs/episode-identity-design.md`
- `docs/stableId-design.md`

现行实现要求订阅规则在抓取阶段产出 `stableId`、`roadId`、`title`、
`ordinal` 和 `pageUrl`。播放器、历史、下载、弹幕缓存和 SyncPlay 只用
`stableId + roadId` 做身份匹配；`pageUrl` 只用于请求，`ordinal` 只用于
排序、展示和弹幕集号。

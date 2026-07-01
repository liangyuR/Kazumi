# PR3 — 已废弃：pageUrl 主键方案

这份旧 PR 计划已被当前 stable identity 方案取代。现行设计不再把 `pageUrl` 作为历史主键，也不再维护 URL 回填/迁移路径。

当前实现以 `EpisodeIdentity.stableId + roadId` 为身份货币：

- `History.progresses` 使用稳定字符串 key，不使用集号作为持久 bucket。
- `pageUrl` 只作为请求地址快照，不参与匹配。
- 恢复播放、下载查重、弹幕缓存和 SyncPlay 都按 `stableId + roadId` 消歧。

请以 `docs/episode-identity-design.md` 和 `docs/stableId-design.md` 为准。

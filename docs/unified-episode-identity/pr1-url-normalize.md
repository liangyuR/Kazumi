# PR1 — 已废弃

本文件记录的是早期 URL 归一化主键方案，已经被当前 `EpisodeIdentity`
设计取代。

当前规则见：

- `docs/episode-identity-design.md`
- `docs/stableId-design.md`

URL 归一化现在只作为 Plugin 边界的 fallback：当规则没有显式
`episodeId` 时，可以从归一化后的相对 URL 派生 `stableId`。该 fallback
只发生在抓取阶段；播放器、历史、下载和弹幕缓存不再用 URL 反查身份。

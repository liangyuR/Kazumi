# PR5 — 已废弃

本文件记录的是早期 `pageUrl` 主键系列中的 sort 锚定计划，已经被当前
`EpisodeIdentity` 设计取代。

当前规则见：

- `docs/episode-identity-design.md`
- `docs/stableId-design.md`

现行实现中，`EpisodeIdentity.ordinal` 是规则产出的排序/弹幕集号语义。
播放器可把 Bangumi sort 或列表位置作为运行时展示/弹幕降级，但不会把这些
降级值写回持久 episode 身份；持久匹配仍只使用 `stableId + roadId`。

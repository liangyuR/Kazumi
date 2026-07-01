# PR4 — 已废弃

本文件记录的是早期“通用 URL matcher”方案，已经被当前
`EpisodeIdentity` 设计取代。

当前规则见：

- `docs/episode-identity-design.md`
- `docs/stableId-design.md`

现行实现不再抽出 `pageUrl`、数字集号或标题名称的通用后验 matcher。
身份必须由订阅规则在抓取阶段产出；下游只按 `stableId + roadId` 匹配。

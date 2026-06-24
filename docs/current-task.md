# Current Task

## Branch

`split/download-episode-matching`

## 目标

改进下载模块的**集数匹配**与**下载状态识别**，解决仅靠 `episodeNumber` 查找下载记录时容易误判的问题（例如集数重排、旧记录缺少 `episodePageUrl`、不同插件集数编号不一致等），让播放页与下载面板能更准确地显示「已下载 / 下载中」状态，并避免重复发起下载。

## 背景问题

此前下载状态主要依赖 `bangumiId + pluginName + episodeNumber` 定位单集。当以下情况出现时，UI 可能找不到已有下载、或匹配到错误的集：

- 旧下载记录未保存 `episodePageUrl`
- 同一番剧存在多集同名或集数编号不可靠
- 需要按播放页 URL 才能唯一确定某一集

## 实现方向

1. **多级匹配策略**（`DownloadEpisodeMatcher`）
   - 优先按 `episodePageUrl` 匹配
   - 其次按 `episodeNumber` 匹配
   - 最后在集名唯一时按 `episodeName` 回退
   - 集名不唯一时不做模糊匹配，避免误绑

2. **下载状态认领判断**（`DownloadController.isEpisodeDownloadClaimed`）
   - 将 `completed` / `downloading` / `pending` / `resolving` 视为已认领
   - 供下载入口与 UI 判断是否应显示进行中或已完成状态

3. **仓储层扩展**（`DownloadRepository`）
   - 新增 `findEpisode`、`getEpisodeByUrl` 等查询能力
   - 支持在已有记录上补全缺失的 `episodePageUrl`

4. **UI 接入**
   - `VideoPage`：用新的匹配逻辑获取当前集下载状态图标
   - `DownloadEpisodeSheet`：用统一匹配方法处理下载状态展示与操作

5. **测试**
   - `test/download_episode_matcher_test.dart` 覆盖 URL 优先、集数回退、集名回退及歧义场景

## 涉及文件

| 文件 | 变更说明 |
|------|----------|
| `lib/repositories/download_repository.dart` | 匹配器与仓储查询 API |
| `lib/pages/download/download_controller.dart` | 对外暴露查找与认领判断方法 |
| `lib/pages/download/download_episode_sheet.dart` | 下载面板接入新匹配逻辑 |
| `lib/pages/video/video_page.dart` | 播放页下载状态图标接入新匹配逻辑 |
| `test/download_episode_matcher_test.dart` | 单元测试 |

## 状态

功能实现与测试已提交（`feat(download): enhance episode matching and download status tracking`）。分支已合并 `main` 最新变更，可作为独立 PR 向上游提交。

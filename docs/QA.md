1. 每个番剧的信息是怎么来的？

答：
按当前代码看，Kazumi 里“番剧信息”的主来源是 **Bangumi API**，本地只缓存 `BangumiItem`。

核心流向是：

1. 列表/搜索/时间表拿到 `BangumiItem`
   搜索走 `BangumiApi.bangumiSearch()` 或按 ID 走 `getBangumiInfoByID()`；时间表、趋势、热门也都在 `BangumiApi` 里请求 Bangumi 或 Kazumi 的 Bangumi 镜像缓存。见 [bangumi_api.dart](D:/project/Kazumi/lib/request/apis/bangumi_api.dart:21)、[search_controller.dart](D:/project/Kazumi/lib/pages/search/search_controller.dart:58)、[popular_controller.dart](D:/project/Kazumi/lib/pages/popular/popular_controller.dart:43)、[timeline_controller.dart](D:/project/Kazumi/lib/pages/timeline/timeline_controller.dart:55)。

2. 详情页按 Bangumi ID 补全/刷新
   卡片点进详情时把已有的 `BangumiItem` 传给 `/info/`，如果简介或评分分布不完整，详情页再调用 `BangumiApi.getBangumiInfoByID(id)` 拉 `/p1/subjects/{id}`。见 [bangumi_card.dart](D:/project/Kazumi/lib/bean/card/bangumi_card.dart:29)、[info_page.dart](D:/project/Kazumi/lib/pages/info/info_page.dart:197)、[info_controller.dart](D:/project/Kazumi/lib/pages/info/info_controller.dart:84)。

3. 字段解析在 `BangumiItem.fromJson`
   名称、中文名、简介、开播日期、封面、标签、别名、排名、评分、评分人数等都从 Bangumi 返回 JSON 转成 `BangumiItem`。解析逻辑兼容 `api.bgm.tv /v0` 和 `next.bgm.tv /p1`。见 [bangumi_item.dart](D:/project/Kazumi/lib/modules/bangumi/bangumi_item.dart:61)。

4. 本地收藏只是缓存副本
   收藏页从 Hive 里的 `collectibles` 读 `BangumiItem`；详情页刷新后也会尝试把收藏里的本地副本更新。Bangumi 同步开启时，远端收藏也会从 Bangumi 收藏接口拉回并转换成本地 `BangumiItem`。见 [collect_crud_repository.dart](D:/project/Kazumi/lib/repositories/collect_crud_repository.dart:62)、[collect_controller.dart](D:/project/Kazumi/lib/pages/collect/collect_controller.dart:216)、[bangumi_collection.dart](D:/project/Kazumi/lib/modules/bangumi/bangumi_collection.dart:57)。

5. 播放源不是 Bangumi 信息
   详情页底部“来源”用番剧中文名/原名作为关键词，交给已安装插件去各视频站搜索；插件按规则里的 XPath 解析搜索结果、线路和剧集。见 [source_sheet.dart](D:/project/Kazumi/lib/pages/info/source_sheet.dart:51)、[plugin_search_service.dart](D:/project/Kazumi/lib/services/plugin/plugin_search_service.dart:66)、[plugins.dart](D:/project/Kazumi/lib/plugins/plugins.dart:199)。

所以一句话：**番剧资料来自 Bangumi/Next Bangumi API 或 Kazumi 的 Bangumi 镜像缓存；本地只保存副本；播放地址和剧集播放列表来自 KazumiRules 插件解析的视频站页面。**

2. 是通过什么拿到这个番剧的信息？

3. 是怎么通过规则获取某个番剧的源的？又是通过什么来拿到播放链接，下载连接的？

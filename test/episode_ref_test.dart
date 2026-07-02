import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/download/download_episode_sheet.dart';
import 'package:kazumi/pages/player/controller/player_models.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/plugins/plugins.dart';

EpisodeIdentity _identity(
  String stableId,
  String title, {
  int? ordinal,
  int roadIndex = 0,
  String? roadId,
  String? pageUrl,
}) {
  return EpisodeIdentity(
    stableId: stableId,
    pageUrl: pageUrl ?? stableId,
    title: title,
    ordinal: ordinal,
    roadIndex: roadIndex,
    roadId: roadId ?? 'road-$roadIndex',
  );
}

void main() {
  group('EpisodeRef', () {
    test('online keeps list index for history and uses ordinal for danmaku',
        () {
      final episode = EpisodeRef.online(
        listIndex: 1,
        identity: _identity('/episode/13', '第13话', ordinal: 13, roadIndex: 0),
      );

      expect(episode.historyEpisodeNumber, 1);
      expect(episode.danmakuEpisodeNumber, 13);
      expect(episode.sortNumber, 13);
      expect(episode.originalRoadIndex, 0);
      expect(episode.pageUrl, '/episode/13');
      expect(episode.stableId, '/episode/13');
    });

    test('online prefers rule ordinal over Bangumi anchored sort number', () {
      final episode = EpisodeRef.online(
        listIndex: 2,
        identity: _identity('/episode/13', '第13话', ordinal: 13, roadIndex: 0),
        anchoredSortNumber: 12,
      );

      expect(episode.historyEpisodeNumber, 2);
      expect(episode.danmakuEpisodeNumber, 13);
      expect(episode.sortNumber, 13);
    });

    test('online falls back to list index when rule provides no ordinal', () {
      final episode = EpisodeRef.online(
        listIndex: 2,
        identity: _identity('/ova', 'OVA', ordinal: null, roadIndex: 1),
      );

      expect(episode.historyEpisodeNumber, 2);
      expect(episode.danmakuEpisodeNumber, 2);
      expect(episode.sortNumber, 2);
      expect(episode.originalRoadIndex, 1);
    });

    test('offline uses downloaded episode number for history and danmaku', () {
      final episode = EpisodeRef.offline(
        listIndex: 1,
        identity: _identity('/episode/13', '第13话', ordinal: 13, roadIndex: 0),
        originalRoadIndex: 2,
      );

      expect(episode.historyEpisodeNumber, 13);
      expect(episode.danmakuEpisodeNumber, 13);
      expect(episode.sortNumber, 13);
      expect(episode.originalRoadIndex, 2);
      expect(episode.listIndex, 1);
      expect(episode.pageUrl, '/episode/13');
      expect(episode.stableId, '/episode/13');
    });
  });

  group('Bangumi sort anchor', () {
    test('maps list positions to positive integer Bangumi sort numbers', () {
      final mapping = bangumiSortByListIndex([
        EpisodeInfo(id: 1, episode: 1, type: 0, name: '', nameCn: ''),
        EpisodeInfo(id: 2, episode: 3.0, type: 0, name: '', nameCn: ''),
        EpisodeInfo(id: 3, episode: 1.5, type: 0, name: '', nameCn: ''),
        EpisodeInfo(id: 4, episode: 0, type: 0, name: '', nameCn: ''),
      ]);

      expect(mapping, {1: 1, 2: 3});
    });

    test('prefers rule ordinal then Bangumi sort then list index', () {
      expect(
        episodeSortNumberForPlayback(
          listIndex: 1,
          anchoredSortNumber: 12,
          ruleOrdinal: 13,
        ),
        13,
      );
      expect(
        episodeSortNumberForPlayback(
          listIndex: 1,
          anchoredSortNumber: 12,
        ),
        12,
      );
      expect(
        episodeSortNumberForPlayback(
          listIndex: 2,
          ruleOrdinal: 13,
        ),
        13,
      );
      expect(
        episodeSortNumberForPlayback(
          listIndex: 3,
        ),
        3,
      );
    });
  });

  group('findEpisodeSelectionByStableId', () {
    test('locates the current road position after source reorder', () {
      final roads = [
        Road(
          name: '播放线路1',
          roadId: 'road-0',
          data: [
            _identity('/episode/3', '第三话', ordinal: 3),
            _identity('/episode/1', '第一话', ordinal: 1),
          ],
        ),
        Road(
          name: '播放线路2',
          roadId: 'road-1',
          data: [
            _identity('/episode/2', '第二话', ordinal: 2, roadIndex: 1),
          ],
        ),
      ];

      final selection = findEpisodeSelectionByStableId(roads, '/episode/1');

      expect(selection, isNotNull);
      expect(selection!.road, 0);
      expect(selection.episode, 2);
      expect(findEpisodeSelectionByStableId(roads, ''), isNull);
      expect(findEpisodeSelectionByStableId(roads, '/missing'), isNull);
    });

    test('honors preferred road when stableId appears in multiple roads', () {
      final roads = [
        Road(
          name: '播放线路1',
          roadId: 'road-0',
          data: [
            _identity('/episode/1', '第一话', ordinal: 1),
          ],
        ),
        Road(
          name: '播放线路2',
          roadId: 'road-1',
          data: [
            _identity('/episode/1', '第一话', ordinal: 1, roadIndex: 1),
          ],
        ),
      ];

      final selection = findEpisodeSelectionByStableId(
        roads,
        '/episode/1',
        preferredRoad: 1,
      );

      expect(selection, isNotNull);
      expect(selection!.road, 1);
      expect(selection.episode, 1);
    });

    test('history restore honors saved road for duplicate stableId', () {
      final roads = [
        Road(
          name: '播放线路1',
          roadId: 'road-0',
          data: [
            _identity('/episode/1', '线路1 第1话', ordinal: 1),
          ],
        ),
        Road(
          name: '播放线路2',
          roadId: 'road-1',
          data: [
            _identity('/episode/1', '线路2 第1话', ordinal: 1, roadIndex: 1),
          ],
        ),
      ];

      final selection = findEpisodeSelectionForHistoryProgress(
        roads,
        stableId: '/episode/1',
        roadId: 'road-1',
        preferredRoad: 1,
      );

      expect(selection, isNotNull);
      expect(selection!.road, 1);
      expect(selection.episode, 1);
    });

    test('history restore does not fall back to index when stableId is known',
        () {
      final roads = [
        Road(
          name: '播放线路1',
          roadId: 'road-0',
          data: [
            _identity('/episode/3', '第三话', ordinal: 3),
            _identity('/episode/1', '第一话', ordinal: 1),
          ],
        ),
      ];

      expect(
        findEpisodeSelectionForHistoryProgress(
          roads,
          stableId: '/missing',
          roadId: 'road-0',
          preferredRoad: 0,
        ),
        isNull,
      );
    });

    test('history restore rejects progress without stableId', () {
      final roads = [
        Road(
          name: '播放线路1',
          roadId: 'road-0',
          data: [
            _identity('/episode/3', '第三话', ordinal: 3),
            _identity('/episode/1', '第一话', ordinal: 1),
          ],
        ),
      ];

      final selection = findEpisodeSelectionForHistoryProgress(
        roads,
        stableId: '',
        roadId: '',
        preferredRoad: 0,
      );

      expect(selection, isNull);
    });
  });

  test('PlaybackInitParams carries danmaku episode independently', () {
    const params = PlaybackInitParams(
      videoUrl: 'file:///tmp/video.mp4',
      offset: 0,
      isLocalPlayback: true,
      bangumiId: 1,
      pluginName: 'plugin',
      episode: 1,
      danmakuEpisodeNumber: 13,
      httpHeaders: {},
      adBlockerEnabled: false,
      episodeTitle: '第13话',
      referer: '',
      currentRoad: 0,
    );

    expect(params.episode, 1);
    expect(params.danmakuEpisodeNumber, 13);
  });

  group('SyncPlayEpisodeIdentity', () {
    test('round-trips stableId file names', () {
      final fileName = SyncPlayEpisodeIdentity.fileNameFor(
        bangumiId: 123,
        road: 2,
        episode: 5,
        stableId: '/play/1?part=a',
        roadId: 'source-main',
      );

      final identity = SyncPlayEpisodeIdentity.parse(fileName);

      expect(identity, isNotNull);
      expect(identity!.bangumiId, 123);
      expect(identity.roadId, 'source-main');
      expect(identity.stableId, '/play/1?part=a');
      expect(identity.episode, isNull);
    });

    test('rejects new playlist-position file names without stableId', () {
      expect(
        () => SyncPlayEpisodeIdentity.fileNameFor(
          bangumiId: 123,
          road: 2,
          episode: 5,
          stableId: '',
        ),
        throwsArgumentError,
      );
    });

    test('parses legacy playlist-position file names without targeting them',
        () {
      final identity = SyncPlayEpisodeIdentity.parse('123[5]');

      expect(identity, isNotNull);
      expect(identity!.bangumiId, 123);
      expect(identity.episode, 5);
      expect(identity.hasStableId, isFalse);
    });

    test('detects road changes for the same stableId', () {
      final identity = SyncPlayEpisodeIdentity.parse(
        SyncPlayEpisodeIdentity.fileNameFor(
          bangumiId: 123,
          road: 1,
          episode: 1,
          stableId: 'shared-episode',
          roadId: 'source-b',
        ),
      );

      expect(identity, isNotNull);
      expect(
        identity!.targetsStableEpisode(
          currentStableId: 'shared-episode',
          currentRoadId: 'source-a',
          currentRoad: 0,
        ),
        isFalse,
      );
      expect(
        identity.targetsStableEpisode(
          currentStableId: 'shared-episode',
          currentRoadId: 'source-b',
          currentRoad: 1,
        ),
        isTrue,
      );
    });
  });

  group('OfflineRoadListSnapshot', () {
    test('groups downloaded episodes by original road', () {
      final snapshot = buildOfflineRoadListSnapshot([
        _episode(2, '第二话', 2),
        _episode(1, '第一话', 0, stableId: 'rule-episode-1'),
        _episode(4, '第四话', 2),
        _episode(3, '第三话', 0),
      ]);

      expect(snapshot.roads.length, 2);
      expect(snapshot.roads[0].name, '播放列表1');
      expect(snapshot.roads[0].data.map((e) => e.ordinal).toList(), [1, 3]);
      expect(
          snapshot.roads[0].data.map((e) => e.title).toList(), ['第一话', '第三话']);
      expect(snapshot.roads[0].data.map((e) => e.stableId).toList(),
          ['rule-episode-1', '']);
      expect(snapshot.roads[1].name, '播放列表3');
      expect(snapshot.roads[1].data.map((e) => e.ordinal).toList(), [2, 4]);
      expect(
          snapshot.roads[1].data.map((e) => e.title).toList(), ['第二话', '第四话']);
      expect(snapshot.displayRoadToOriginalRoad, {0: 0, 1: 2});
      expect(snapshot.originalRoadToDisplayRoad, {0: 0, 2: 1});
    });

    test('finds stableId match on the preferred original road', () {
      final snapshot = buildOfflineRoadListSnapshot([
        _episode(1, '线路1 第1话', 0, stableId: 'shared-episode'),
        _episode(1, '线路2 第1话', 1, stableId: 'shared-episode'),
      ]);

      final selectedIdentity = snapshot.roads[1].data[0];
      final episode = snapshot.episodeForIdentity(selectedIdentity, 1);

      expect(episode, isNotNull);
      expect(episode!.episodeName, '线路2 第1话');
      expect(episode.road, 1);
    });

    test('does not fall back to another road when roadId is known', () {
      final snapshot = buildOfflineRoadListSnapshot([
        _episode(1, '线路1 第1话', 0,
            stableId: 'shared-episode', roadId: 'source-a'),
        _episode(1, '线路2 第1话', 1,
            stableId: 'shared-episode', roadId: 'source-b'),
      ]);

      final missingRoadIdentity = _identity(
        'shared-episode',
        '线路3 第1话',
        ordinal: 1,
        roadId: 'source-c',
      );
      final episode = snapshot.episodeForIdentity(missingRoadIdentity, 0);

      expect(episode, isNull);
    });

    test('uses stableId before ordinal when downloaded numbers collide', () {
      final snapshot = buildOfflineRoadListSnapshot([
        _episode(1, '正片 第1话', 0, stableId: 'main-1'),
        _episode(1, '特别篇', 0, stableId: 'special-1'),
      ]);

      final specialIdentity = _identity(
        'special-1',
        '特别篇',
        ordinal: 1,
        roadId: 'source-0',
      );
      final episode = snapshot.episodeForIdentity(specialIdentity, 0);

      expect(episode, isNotNull);
      expect(episode!.episodeName, '特别篇');
    });
  });

  group('download episode identity', () {
    test('download resolution does not prefix normalized absolute urls', () {
      final plugin = Plugin.fromTemplate()..baseUrl = 'http://www.example.com';

      expect(
        downloadResolvePageUrl(plugin, 'https://www.example.com/play/1'),
        'https://www.example.com/play/1',
      );
      expect(
        downloadResolvePageUrl(plugin, '/play/1'),
        'https://www.example.com/play/1',
      );
    });

    test('uses rule ordinal as stored download episode ordinal', () {
      final identity = _identity('/episode/13', '第13话', ordinal: 13);

      expect(
        downloadEpisodeOrdinalForSelection(identity),
        13,
      );
    });

    test('keeps download ordinal empty when rule provides no ordinal', () {
      final identity = _identity('/ova', 'OVA', ordinal: null);

      expect(
        downloadEpisodeOrdinalForSelection(identity),
        isNull,
      );
    });

    test('detects downloaded episodes by stableId and roadId', () {
      final identity = _identity(
        '/play/1',
        '第1话',
        ordinal: 1,
        roadId: 'source-a',
        pageUrl: 'https://new.example.com/play/1',
      );

      expect(
        isDownloadedEpisodeIdentity(
          identity,
          downloadedStableIdsByRoadId: {
            (stableId: '/play/1', roadId: 'source-a')
          },
          downloadedStableIdsByRoad: const {},
        ),
        isTrue,
      );
    });

    test('scopes downloaded stableId checks by road', () {
      final identity = _identity(
        'shared-episode',
        '线路2 第1话',
        ordinal: 1,
        roadIndex: 1,
        roadId: 'source-b',
      );

      expect(
        isDownloadedEpisodeIdentity(
          identity,
          downloadedStableIdsByRoadId: {
            (stableId: 'shared-episode', roadId: 'source-a')
          },
          downloadedStableIdsByRoad: const {},
        ),
        isFalse,
      );
      expect(
        isDownloadedEpisodeIdentity(
          identity,
          downloadedStableIdsByRoadId: {
            (stableId: 'shared-episode', roadId: 'source-b')
          },
          downloadedStableIdsByRoad: const {},
        ),
        isTrue,
      );
    });

    test('scopes downloaded stableId by road index when roadId is empty', () {
      final road0Identity = _identity(
        'shared-episode',
        '线路1 第1话',
        ordinal: 1,
        roadIndex: 0,
        roadId: '',
      );
      final road1Identity = _identity(
        'shared-episode',
        '线路2 第1话',
        ordinal: 1,
        roadIndex: 1,
        roadId: '',
      );

      expect(
        isDownloadedEpisodeIdentity(
          road0Identity,
          downloadedStableIdsByRoadId: const {},
          downloadedStableIdsByRoad: {(stableId: 'shared-episode', road: 0)},
        ),
        isTrue,
      );
      expect(
        isDownloadedEpisodeIdentity(
          road1Identity,
          downloadedStableIdsByRoadId: const {},
          downloadedStableIdsByRoad: {(stableId: 'shared-episode', road: 0)},
        ),
        isFalse,
      );
    });

    test('uses stableId-derived keys for downloaded episodes', () {
      final record = DownloadRecord(
        1,
        'subject',
        '',
        'plugin',
        {},
        DateTime(2026),
      );

      final mainKey = downloadKeyForEpisodeIdentity(
        record,
        road: 0,
        roadId: 'source-a',
        stableId: 'main-1',
      );
      record.episodes[mainKey] = _episode(1, '正片 第1话', 0, stableId: 'main-1');

      final specialKey = downloadKeyForEpisodeIdentity(
        record,
        road: 0,
        roadId: 'source-a',
        stableId: 'special-1',
      );
      record.episodes[specialKey] =
          _episode(1, '特别篇', 0, stableId: 'special-1');

      expect(mainKey, isNot(specialKey));
      expect(record.episodes, hasLength(2));
      expect(record.episodes[mainKey]!.episodeName, '正片 第1话');
      expect(record.episodes[specialKey]!.episodeName, '特别篇');
    });

    test('scopes download record keys by source binding', () {
      final legacy = DownloadRecord(
        1,
        'subject',
        '',
        'plugin',
        {},
        DateTime(2026),
      );
      final sourceBound = DownloadRecord(
        1,
        'subject',
        '',
        'plugin',
        {},
        DateTime(2026),
        sourceBindingKey: 'source:/movie',
      );

      expect(legacy.key, 'plugin_1');
      expect(sourceBound.key, isNot(legacy.key));
      expect(
          sourceBound.key,
          DownloadRecord.scopedKey(
            'plugin',
            1,
            sourceBindingKey: 'source:/movie',
          ));
      expect(sourceBound.legacyKey, legacy.key);
    });

    test('source binding participates in new download keys', () {
      final tv = DownloadRecord(
        1,
        'subject',
        '',
        'plugin',
        {},
        DateTime(2026),
        sourceBindingKey: 'source:/tv',
      );
      final movie = DownloadRecord(
        1,
        'subject',
        '',
        'plugin',
        {},
        DateTime(2026),
        sourceBindingKey: 'source:/movie',
      );

      final tvKey = downloadKeyForEpisodeIdentity(
        tv,
        road: 0,
        roadId: 'main',
        stableId: 'episode-1',
      );
      final movieKey = downloadKeyForEpisodeIdentity(
        movie,
        road: 0,
        roadId: 'main',
        stableId: 'episode-1',
      );

      expect(tvKey, isNot(movieKey));
    });

    test('uses road-scoped keys for duplicated stableIds', () {
      final record = DownloadRecord(
        1,
        'subject',
        '',
        'plugin',
        {},
        DateTime(2026),
      );

      final road0Key = downloadKeyForEpisodeIdentity(
        record,
        road: 0,
        roadId: 'source-a',
        stableId: 'shared-episode',
      );
      record.episodes[road0Key] = _episode(1, '线路1 第1话', 0,
          stableId: 'shared-episode', roadId: 'source-a');

      final road1Key = downloadKeyForEpisodeIdentity(
        record,
        road: 1,
        roadId: 'source-b',
        stableId: 'shared-episode',
      );
      record.episodes[road1Key] = _episode(1, '线路2 第1话', 1,
          stableId: 'shared-episode', roadId: 'source-b');

      expect(road0Key, isNot(road1Key));
      expect(record.episodes, hasLength(2));
      expect(
        downloadEpisodeEntryByStableId(
          record,
          'shared-episode',
          road: 1,
          roadId: 'source-b',
        )!
            .value
            .episodeName,
        '线路2 第1话',
      );
    });

    test('finds downloaded episode entries by stableId', () {
      final record = DownloadRecord(
        1,
        'subject',
        '',
        'plugin',
        {
          1: _episode(1, '第一话', 0, stableId: 'episode-1'),
        },
        DateTime(2026),
      );

      final entry =
          downloadEpisodeEntryByStableId(record, 'episode-1', road: 0);

      expect(entry, isNotNull);
      expect(entry!.key, 1);
      expect(entry.value.episodeName, '第一话');
      expect(downloadEpisodeEntryByStableId(record, '', road: 0), isNull);
      expect(
        downloadEpisodeEntryByStableId(record, 'episode-1', road: 1),
        isNull,
      );
      expect(
          downloadEpisodeEntryByStableId(record, 'missing', road: 0), isNull);
    });

    test('prefers saved road when restoring offline history by stableId', () {
      final episodes = [
        _episode(1, '线路1 第1话', 0, stableId: 'shared-episode'),
        _episode(1, '线路2 第1话', 1, stableId: 'shared-episode'),
      ];

      final episode = downloadedEpisodeForHistoryPlayback(
        episodes,
        stableId: 'shared-episode',
        preferredRoad: 1,
      );

      expect(episode, isNotNull);
      expect(episode!.road, 1);
      expect(episode.episodeName, '线路2 第1话');
    });

    test('does not fall back to another downloaded roadId', () {
      final episodes = [
        _episode(1, '线路1 第1话', 0,
            stableId: 'shared-episode', roadId: 'source-a'),
        _episode(1, '线路2 第1话', 1,
            stableId: 'shared-episode', roadId: 'source-b'),
      ];

      final episode = downloadedEpisodeForHistoryPlayback(
        episodes,
        stableId: 'shared-episode',
        preferredRoad: 0,
        preferredRoadId: 'source-c',
      );

      expect(episode, isNull);
    });

    test('does not fall back to numeric episode after stableId miss', () {
      final episodes = [
        _episode(1, '第一话', 0, stableId: 'episode-1'),
        _episode(2, '第二话', 0, stableId: 'episode-2'),
      ];

      final episode = downloadedEpisodeForHistoryPlayback(
        episodes,
        stableId: 'missing-stable-id',
        preferredRoad: 0,
      );

      expect(episode, isNull);
    });

    test('rejects offline history without stableId', () {
      final episodes = [
        _episode(2, '第二话', 0),
        _episode(3, '第三话', 0),
      ];

      final episode = downloadedEpisodeForHistoryPlayback(
        episodes,
        stableId: '',
        preferredRoad: 1,
      );

      expect(episode, isNull);
    });

    test('rejects download keys without stableId', () {
      final record = DownloadRecord(
        1,
        'subject',
        '',
        'plugin',
        {},
        DateTime(2026),
      );

      expect(
        () => downloadKeyForEpisodeIdentity(
          record,
          road: 2,
          roadId: '',
          stableId: '',
        ),
        throwsArgumentError,
      );
    });
  });
}

DownloadEpisode _episode(
  int ordinal,
  String name,
  int road, {
  String stableId = '',
  String? roadId,
  String? pageUrl,
}) {
  return DownloadEpisode(
    ordinal,
    name,
    road,
    DownloadStatus.completed,
    1.0,
    0,
    0,
    '',
    '',
    '',
    DateTime(2026),
    '',
    0,
    pageUrl ?? '/episode/$ordinal',
    stableId: stableId,
    roadId: roadId ?? 'source-$road',
  );
}

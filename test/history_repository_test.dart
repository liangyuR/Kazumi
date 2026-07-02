import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/bangumi_tag.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/repositories/history_repository.dart';

void main() {
  late Directory tempDir;
  late Box<History> historiesBox;
  late bool privateMode;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('kazumi_history_test_');
    Hive.init(tempDir.path);
    _registerAdapters();
    historiesBox = await Hive.openBox<History>('histories');
  });

  setUp(() async {
    privateMode = false;
    await historiesBox.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('HistoryRepository source metadata', () {
    test('keeps online source isolated from offline history', () async {
      final repository = _repository(historiesBox, () => privateMode);
      final item = _item(1);

      await repository.updateHistory(
        identity: PlaybackHistoryIdentity.online(
          bangumiItem: item,
          pluginName: 'plugin',
          episodeNumber: 1,
          episodeTitle: 'EP1',
          road: 0,
          onlineBangumiSrc: 'https://example.com/source',
          episodePageUrl: '/online/1',
          stableId: 'online-ep-1',
          roadId: 'online-road',
        ),
        progress: const Duration(seconds: 10),
      );

      await repository.updateHistory(
        identity: PlaybackHistoryIdentity.offline(
          bangumiItem: item,
          pluginName: 'plugin',
          episodeNumber: 1,
          episodeTitle: 'EP1 local',
          road: 0,
          episodePageUrl: '/offline/1',
          stableId: 'offline-ep-1',
          roadId: 'offline-road',
        ),
        progress: const Duration(seconds: 20),
      );

      final online = repository.getHistory(
        'plugin',
        item,
        entryKind: HistoryEntryKind.online,
      );
      final offline = repository.getHistory(
        'plugin',
        item,
        entryKind: HistoryEntryKind.offline,
      );

      expect(online, isNotNull);
      expect(offline, isNotNull);
      expect(online!.lastSrc, 'https://example.com/source');
      expect(online.episodePageUrl, '/online/1');
      expect(online.stableId, 'online-ep-1');
      expect(online.roadId, 'online-road');
      expect(_progressByEpisode(online, 1).progress.inSeconds, 10);
      expect(offline!.lastSrc, isEmpty);
      expect(offline.episodePageUrl, '/offline/1');
      expect(offline.stableId, 'offline-ep-1');
      expect(offline.roadId, 'offline-road');
      expect(_progressByEpisode(offline, 1).progress.inSeconds, 20);
      expect(online.key, History.getKey('plugin', item));
      expect(
        offline.key,
        History.getKey(
          'plugin',
          item,
          entryKind: HistoryEntryKind.offline,
        ),
      );
    });

    test('does not overwrite existing online source with an empty value',
        () async {
      final repository = _repository(historiesBox, () => privateMode);
      final item = _item(2);

      await repository.updateHistory(
        identity: PlaybackHistoryIdentity.online(
          bangumiItem: item,
          pluginName: 'plugin',
          episodeNumber: 1,
          episodeTitle: 'EP1',
          road: 0,
          onlineBangumiSrc: 'https://example.com/source',
          episodePageUrl: '/online/1',
          stableId: 'ep-1',
          roadId: 'road-a',
        ),
        progress: const Duration(seconds: 10),
      );

      await repository.updateHistory(
        identity: PlaybackHistoryIdentity.online(
          bangumiItem: item,
          pluginName: 'plugin',
          episodeNumber: 2,
          episodeTitle: 'EP2',
          road: 1,
          onlineBangumiSrc: '',
          episodePageUrl: '/online/2',
          stableId: 'ep-2',
          roadId: 'road-b',
        ),
        progress: const Duration(seconds: 30),
      );

      final history = repository.getHistory(
        'plugin',
        item,
        entryKind: HistoryEntryKind.online,
      );

      expect(history, isNotNull);
      expect(history!.lastSrc, 'https://example.com/source');
      expect(history.lastWatchEpisode, 2);
      expect(history.lastWatchEpisodeName, 'EP2');
      expect(history.episodePageUrl, '/online/2');
      expect(history.stableId, 'ep-2');
      expect(history.roadId, 'road-b');
      final episode2Progress = _progressByEpisode(history, 2);
      expect(episode2Progress.episodePageUrl, '/online/2');
      expect(episode2Progress.stableId, 'ep-2');
      expect(episode2Progress.roadId, 'road-b');
      expect(episode2Progress.progress.inSeconds, 30);
    });

    test('does not record history when private mode is enabled', () async {
      privateMode = true;
      final repository = _repository(historiesBox, () => privateMode);
      final item = _item(3);

      await repository.updateHistory(
        identity: PlaybackHistoryIdentity.online(
          bangumiItem: item,
          pluginName: 'plugin',
          episodeNumber: 1,
          episodeTitle: 'EP1',
          road: 0,
          onlineBangumiSrc: 'https://example.com/source',
          episodePageUrl: '/online/1',
          stableId: 'ep-1',
          roadId: 'road-a',
        ),
        progress: const Duration(seconds: 10),
      );

      expect(historiesBox.values, isEmpty);
      expect(repository.getHistory('plugin', item), isNull);
    });

    test('does not record history without stable episode identity', () async {
      final repository = _repository(historiesBox, () => privateMode);
      final item = _item(4);

      await repository.updateHistory(
        identity: PlaybackHistoryIdentity.online(
          bangumiItem: item,
          pluginName: 'plugin',
          episodeNumber: 1,
          episodeTitle: 'EP1',
          road: 0,
          onlineBangumiSrc: 'https://example.com/source',
          episodePageUrl: '/online/1',
        ),
        progress: const Duration(seconds: 10),
      );

      expect(historiesBox.values, isEmpty);
      expect(repository.getHistory('plugin', item), isNull);
    });

    test('keeps histories separate by source binding', () async {
      final repository = _repository(historiesBox, () => privateMode);
      final item = _item(5);

      await repository.updateHistory(
        identity: PlaybackHistoryIdentity.online(
          bangumiItem: item,
          pluginName: 'plugin',
          episodeNumber: 1,
          episodeTitle: 'TV EP1',
          road: 0,
          onlineBangumiSrc: 'https://example.com/tv',
          episodePageUrl: '/tv/1',
          stableId: 'episode-1',
          roadId: 'road-main',
          sourceBindingKey: 'source:/tv',
          sourceTitle: 'TV',
          sourceUrl: 'https://example.com/tv',
          sourceConfirmedAt: 1000,
        ),
        progress: const Duration(seconds: 10),
      );

      await repository.updateHistory(
        identity: PlaybackHistoryIdentity.online(
          bangumiItem: item,
          pluginName: 'plugin',
          episodeNumber: 1,
          episodeTitle: 'Movie',
          road: 0,
          onlineBangumiSrc: 'https://example.com/movie',
          episodePageUrl: '/movie',
          stableId: 'movie',
          roadId: 'road-main',
          sourceBindingKey: 'source:/movie',
          sourceTitle: 'Movie',
          sourceUrl: 'https://example.com/movie',
          sourceConfirmedAt: 2000,
        ),
        progress: const Duration(seconds: 20),
      );

      final tv = repository.getHistory(
        'plugin',
        item,
        sourceBindingKey: 'source:/tv',
      );
      final movie = repository.getHistory(
        'plugin',
        item,
        sourceBindingKey: 'source:/movie',
      );

      expect(repository.getHistory('plugin', item), isNull);
      expect(repository.getAllHistories(), hasLength(2));
      expect(tv, isNotNull);
      expect(movie, isNotNull);
      expect(tv!.key, isNot(movie!.key));
      expect(tv.sourceTitle, 'TV');
      expect(tv.sourceUrl, 'https://example.com/tv');
      expect(tv.sourceConfirmedAt, 1000);
      expect(movie.sourceTitle, 'Movie');
      expect(_progressByEpisode(tv, 1).progress.inSeconds, 10);
      expect(_progressByEpisode(movie, 1).progress.inSeconds, 20);

      expect(
        repository
            .findProgress(
              item,
              'plugin',
              1,
              stableId: 'episode-1',
              roadId: 'road-main',
              sourceBindingKey: 'source:/tv',
            )!
            .progress
            .inSeconds,
        10,
      );
      expect(
        repository.findProgress(
          item,
          'plugin',
          1,
          stableId: 'episode-1',
          roadId: 'road-main',
          sourceBindingKey: 'source:/movie',
        ),
        isNull,
      );
    });

    test('promotes legacy history after source binding confirmation', () async {
      final deletedHistories = <History>[];
      final repository = HistoryRepository(
        historiesBox: historiesBox,
        privateModeReader: () => privateMode,
        progressSyncAppender: _noopHistorySync,
        deleteSyncAppender: (history) async => deletedHistories.add(history),
        clearSyncAppender: _noopClearSync,
      );
      final item = _item(6);

      await repository.updateHistory(
        identity: PlaybackHistoryIdentity.online(
          bangumiItem: item,
          pluginName: 'plugin',
          episodeNumber: 1,
          episodeTitle: 'Legacy EP1',
          road: 0,
          onlineBangumiSrc: 'https://example.com/legacy',
          episodePageUrl: '/legacy/1',
          stableId: 'episode-1',
          roadId: 'road-main',
        ),
        progress: const Duration(seconds: 10),
      );

      await repository.updateHistory(
        identity: PlaybackHistoryIdentity.online(
          bangumiItem: item,
          pluginName: 'plugin',
          episodeNumber: 2,
          episodeTitle: 'TV EP2',
          road: 0,
          onlineBangumiSrc: 'https://example.com/tv',
          episodePageUrl: '/tv/2',
          stableId: 'episode-2',
          roadId: 'road-main',
          sourceBindingKey: 'source:/tv',
          sourceTitle: 'TV',
          sourceUrl: 'https://example.com/tv',
          sourceConfirmedAt: 2000,
        ),
        progress: const Duration(seconds: 20),
      );

      final promoted = repository.getHistory(
        'plugin',
        item,
        sourceBindingKey: 'source:/tv',
      );

      expect(repository.getHistory('plugin', item), isNull);
      expect(historiesBox.values, hasLength(1));
      expect(promoted, isNotNull);
      expect(promoted!.sourceTitle, 'TV');
      expect(promoted.progresses, hasLength(2));
      expect(_progressByEpisode(promoted, 1).progress.inSeconds, 10);
      expect(_progressByEpisode(promoted, 2).progress.inSeconds, 20);
      expect(deletedHistories, hasLength(1));
      expect(deletedHistories.single.key, History.getKey('plugin', item));
    });
  });

  group('HistoryRepository stable identity matching', () {
    test('reuses the same bucket after a domain change', () async {
      final repository = _repository(historiesBox, () => privateMode);
      final item = _item(30);

      await repository.updateHistory(
        identity: PlaybackHistoryIdentity.online(
          bangumiItem: item,
          pluginName: 'plugin',
          episodeNumber: 1,
          episodeTitle: 'EP1',
          road: 0,
          onlineBangumiSrc: 'https://example.com/source',
          episodePageUrl: 'https://old.example.com/play/1',
          stableId: 'episode-1',
          roadId: 'road-main',
        ),
        progress: const Duration(seconds: 10),
      );

      await repository.updateHistory(
        identity: PlaybackHistoryIdentity.online(
          bangumiItem: item,
          pluginName: 'plugin',
          episodeNumber: 1,
          episodeTitle: 'EP1',
          road: 0,
          onlineBangumiSrc: 'https://example.com/source',
          episodePageUrl: 'https://new-mirror.example.org/play/1',
          stableId: 'episode-1',
          roadId: 'road-main',
        ),
        progress: const Duration(seconds: 42),
      );

      final history = repository.getHistory('plugin', item)!;
      expect(history.progresses, hasLength(1));
      expect(history.stableId, 'episode-1');
      expect(history.roadId, 'road-main');
      final progress = history.progresses.values.single;
      expect(progress.progress.inSeconds, 42);
      expect(progress.stableId, 'episode-1');
      expect(progress.roadId, 'road-main');
      expect(progress.episodePageUrl, 'https://new-mirror.example.org/play/1');
    });

    test('findProgress matches by stableId and roadId', () async {
      final repository = _repository(historiesBox, () => privateMode);
      final item = _item(31);

      await repository.updateHistory(
        identity: PlaybackHistoryIdentity.online(
          bangumiItem: item,
          pluginName: 'plugin',
          episodeNumber: 1,
          episodeTitle: 'EP1',
          road: 0,
          onlineBangumiSrc: 'https://example.com/source',
          episodePageUrl: 'https://old.example.com/play/1',
          stableId: 'episode-1',
          roadId: 'road-main',
        ),
        progress: const Duration(seconds: 15),
      );

      final progress = repository.findProgress(
        item,
        'plugin',
        1,
        stableId: 'episode-1',
        roadId: 'road-main',
      );

      expect(progress, isNotNull);
      expect(progress!.progress.inSeconds, 15);
    });

    test('getLastWatchingProgress matches by top-level stable identity',
        () async {
      final repository = _repository(historiesBox, () => privateMode);
      final item = _item(34);

      final history = History(
        item,
        1,
        'plugin',
        DateTime.fromMillisecondsSinceEpoch(1000),
        'https://example.com/source',
        'EP1',
        episodePageUrl: 'https://old.example.com/play/1',
        stableId: 'episode-1',
        roadId: 'road-main',
      );
      history.progresses[historyProgressKey(
        stableId: 'episode-1',
        episode: 1,
        road: 0,
        roadId: 'road-main',
      )] = Progress(
        1,
        0,
        25 * 1000,
        episodePageUrl: 'https://new.example.com/play/1',
        stableId: 'episode-1',
        roadId: 'road-main',
      );
      await historiesBox.put(history.key, history);

      final progress = repository.getLastWatchingProgress(item, 'plugin');

      expect(progress, isNotNull);
      expect(progress!.progress.inSeconds, 25);
      expect(progress.stableId, 'episode-1');
      expect(progress.roadId, 'road-main');
    });

    test('keeps different stableIds separate even when page url matches',
        () async {
      final repository = _repository(historiesBox, () => privateMode);
      final item = _item(33);

      await repository.updateHistory(
        identity: PlaybackHistoryIdentity.online(
          bangumiItem: item,
          pluginName: 'plugin',
          episodeNumber: 1,
          episodeTitle: 'EPA',
          road: 0,
          onlineBangumiSrc: 'https://example.com/source',
          episodePageUrl: 'https://example.com/shared',
          stableId: 'source-a',
          roadId: 'road-main',
        ),
        progress: const Duration(seconds: 10),
      );
      await repository.updateHistory(
        identity: PlaybackHistoryIdentity.online(
          bangumiItem: item,
          pluginName: 'plugin',
          episodeNumber: 1,
          episodeTitle: 'EPB',
          road: 0,
          onlineBangumiSrc: 'https://example.com/source',
          episodePageUrl: 'https://example.com/shared',
          stableId: 'source-b',
          roadId: 'road-main',
        ),
        progress: const Duration(seconds: 20),
      );

      final progresses =
          repository.getHistory('plugin', item)!.progresses.values;
      expect(progresses, hasLength(2));
      expect(
        progresses
            .singleWhere((progress) => progress.stableId == 'source-a')
            .progress
            .inSeconds,
        10,
      );
      expect(
        progresses
            .singleWhere((progress) => progress.stableId == 'source-b')
            .progress
            .inSeconds,
        20,
      );
    });

    test('keeps the same stableId separate by roadId', () async {
      final repository = _repository(historiesBox, () => privateMode);
      final item = _item(35);

      await repository.updateHistory(
        identity: PlaybackHistoryIdentity.online(
          bangumiItem: item,
          pluginName: 'plugin',
          episodeNumber: 1,
          episodeTitle: '线路1 第1话',
          road: 0,
          onlineBangumiSrc: 'https://example.com/source',
          episodePageUrl: 'https://example.com/road-0/play/1',
          stableId: 'shared-episode',
          roadId: 'source-a',
        ),
        progress: const Duration(seconds: 10),
      );
      await repository.updateHistory(
        identity: PlaybackHistoryIdentity.online(
          bangumiItem: item,
          pluginName: 'plugin',
          episodeNumber: 1,
          episodeTitle: '线路2 第1话',
          road: 1,
          onlineBangumiSrc: 'https://example.com/source',
          episodePageUrl: 'https://example.com/road-1/play/1',
          stableId: 'shared-episode',
          roadId: 'source-b',
        ),
        progress: const Duration(seconds: 20),
      );

      final history = repository.getHistory('plugin', item)!;
      expect(history.progresses, hasLength(2));

      final roadAProgress = repository.findProgress(
        item,
        'plugin',
        1,
        stableId: 'shared-episode',
        roadId: 'source-a',
      );
      final roadBProgress = repository.findProgress(
        item,
        'plugin',
        1,
        stableId: 'shared-episode',
        roadId: 'source-b',
      );
      expect(roadAProgress!.progress.inSeconds, 10);
      expect(roadBProgress!.progress.inSeconds, 20);

      await repository.clearProgress(
        item,
        'plugin',
        1,
        stableId: 'shared-episode',
        roadId: 'source-b',
      );

      final refreshed = repository.getHistory('plugin', item)!;
      expect(
        refreshed.progresses.values
            .singleWhere((progress) => progress.roadId == 'source-a')
            .progress
            .inSeconds,
        10,
      );
      expect(
        refreshed.progresses.values
            .singleWhere((progress) => progress.roadId == 'source-b')
            .progress,
        Duration.zero,
      );
    });

    test('does not fall back to page url when stableId differs', () async {
      final repository = _repository(historiesBox, () => privateMode);
      final item = _item(36);

      await repository.updateHistory(
        identity: PlaybackHistoryIdentity.online(
          bangumiItem: item,
          pluginName: 'plugin',
          episodeNumber: 1,
          episodeTitle: 'EP1',
          road: 0,
          onlineBangumiSrc: 'https://example.com/source',
          episodePageUrl: 'https://example.com/shared',
          stableId: 'episode-old',
          roadId: 'road-main',
        ),
        progress: const Duration(seconds: 10),
      );

      final progress = repository.findProgress(
        item,
        'plugin',
        1,
        stableId: 'episode-new',
        roadId: 'road-main',
      );

      expect(progress, isNull);
    });

    test('does not fall back to road index when roadId differs', () async {
      final repository = _repository(historiesBox, () => privateMode);
      final item = _item(37);

      await repository.updateHistory(
        identity: PlaybackHistoryIdentity.online(
          bangumiItem: item,
          pluginName: 'plugin',
          episodeNumber: 1,
          episodeTitle: 'EP1',
          road: 0,
          onlineBangumiSrc: 'https://example.com/source',
          episodePageUrl: 'https://example.com/play/1',
          stableId: 'episode-1',
          roadId: 'road-a',
        ),
        progress: const Duration(seconds: 10),
      );

      final progress = repository.findProgress(
        item,
        'plugin',
        1,
        road: 0,
        stableId: 'episode-1',
        roadId: 'road-b',
      );

      expect(progress, isNull);
    });
  });
}

HistoryRepository _repository(
  Box<History> historiesBox,
  bool Function() privateModeReader,
) {
  return HistoryRepository(
    historiesBox: historiesBox,
    privateModeReader: privateModeReader,
    progressSyncAppender: _noopHistorySync,
    deleteSyncAppender: _noopDeleteSync,
    clearSyncAppender: _noopClearSync,
  );
}

Future<void> _noopHistorySync({
  required History history,
  required int episode,
  required int road,
  required int progressMs,
  required int updatedAt,
  required String episodePageUrl,
  required String stableId,
  required String roadId,
}) async {}

Future<void> _noopDeleteSync(History history) async {}

Future<void> _noopClearSync() async {}

Progress _progressByEpisode(History history, int episode) {
  return history.progresses.values
      .singleWhere((progress) => progress.episode == episode);
}

void _registerAdapters() {
  if (!Hive.isAdapterRegistered(1)) {
    Hive.registerAdapter(HistoryAdapter());
  }
  if (!Hive.isAdapterRegistered(2)) {
    Hive.registerAdapter(ProgressAdapter());
  }
  if (!Hive.isAdapterRegistered(3)) {
    Hive.registerAdapter(BangumiItemAdapter());
  }
  if (!Hive.isAdapterRegistered(6)) {
    Hive.registerAdapter(BangumiTagAdapter());
  }
}

BangumiItem _item(int id) {
  return BangumiItem(
    id: id,
    type: 2,
    name: 'subject $id',
    nameCn: '条目 $id',
    summary: '',
    airDate: '2026-01-01',
    airWeekday: 4,
    rank: 0,
    images: const {
      'large': '',
      'common': '',
      'medium': '',
      'small': '',
      'grid': '',
    },
    tags: const <BangumiTag>[],
    alias: const [],
    ratingScore: 0,
    votes: 0,
    votesCount: const [],
    info: '',
  );
}

// ignore_for_file: avoid_print

// Live collection probe for default bundled plugin rules.
//
// Run manually when network access and plugin sites are acceptable:
// flutter test test/live/default_rule_probe_collection_test.dart --dart-define=KAZUMI_LIVE_RULE_PROBE=true

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/request/config/api_endpoints.dart';

const _liveProbeEnabled = bool.fromEnvironment('KAZUMI_LIVE_RULE_PROBE');
const _subjectLimit =
    int.fromEnvironment('KAZUMI_LIVE_RULE_PROBE_LIMIT', defaultValue: 20);
const _timeoutSeconds = int.fromEnvironment(
  'KAZUMI_LIVE_RULE_PROBE_TIMEOUT_SECONDS',
  defaultValue: 12,
);
const _pluginDir = String.fromEnvironment(
  'KAZUMI_LIVE_RULE_PROBE_PLUGIN_DIR',
  defaultValue: 'assets/plugins',
);
const _pluginNamesCsv =
    String.fromEnvironment('KAZUMI_LIVE_RULE_PROBE_PLUGINS');
const _outputDir = String.fromEnvironment(
  'KAZUMI_LIVE_RULE_PROBE_OUTPUT_DIR',
  defaultValue: 'build/live_rule_probe',
);
const _maxKeywords =
    int.fromEnvironment('KAZUMI_LIVE_RULE_PROBE_MAX_KEYWORDS', defaultValue: 5);
const _maxSearchResults = int.fromEnvironment(
  'KAZUMI_LIVE_RULE_PROBE_MAX_SEARCH_RESULTS',
  defaultValue: 5,
);
const _maxEpisodeSamples = int.fromEnvironment(
  'KAZUMI_LIVE_RULE_PROBE_MAX_EPISODE_SAMPLES',
  defaultValue: 5,
);

const _subjectSeeds = <String>[
  '葬送的芙莉莲',
  '孤独摇滚！',
  '鬼灭之刃',
  '咒术回战',
  '进击的巨人',
  '间谍过家家',
  '无职转生',
  'Re：从零开始的异世界生活',
  '关于我转生变成史莱姆这档事',
  '莉可丽丝',
  '电锯人',
  '【我推的孩子】',
  '药屋少女的呢喃',
  '迷宫饭',
  '青春猪头少年不会梦到兔女郎学姐',
  '刀剑神域',
  '轻音少女',
  '命运石之门',
  '夏日重现',
  '辉夜大小姐想让我告白',
];

void main() {
  test(
    'collect default plugin search, road, and episode records',
    () async {
      final options = _ProbeOptions(
        subjectLimit: _subjectLimit,
        timeoutSeconds: _timeoutSeconds,
        pluginDir: _pluginDir,
        pluginNames: _parsePluginNames(_pluginNamesCsv),
        outputDir: _outputDir,
        maxKeywords: _maxKeywords,
        maxSearchResults: _maxSearchResults,
        maxEpisodeSamples: _maxEpisodeSamples,
      );

      final dio = Dio(
        BaseOptions(
          connectTimeout: Duration(seconds: options.timeoutSeconds),
          receiveTimeout: Duration(seconds: options.timeoutSeconds),
          sendTimeout: Duration(seconds: options.timeoutSeconds),
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
          headers: {
            'user-agent':
                'Predidit/Kazumi/${ApiEndpoints.version} (DefaultRuleProbe)',
            'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
          },
        ),
      );
      addTearDown(() => dio.close(force: true));

      final collector = _DefaultRuleProbeCollector(dio: dio, options: options);
      final report = await collector.run();
      final outputs = await report.writeFiles(options.outputDir);
      report.printSummary(outputs);

      expect(report.plugins, isNotEmpty);
      expect(report.subjects, isNotEmpty);
      expect(report.totalPluginSubjectPairs, greaterThan(0));
    },
    skip: _liveProbeEnabled
        ? false
        : 'Set --dart-define=KAZUMI_LIVE_RULE_PROBE=true to run this live collection probe.',
    timeout: const Timeout(Duration(minutes: 12)),
  );

  test('quality metrics flag duplicate identities and dynamic source query',
      () {
    final row = _PluginSubjectProbe(
      subjectSeed: 'seed',
      bangumiId: 1,
      subjectName: 'subject',
      pluginName: 'plugin',
      status: 'success',
      keyword: 'subject',
      searchUrl: 'https://example.test/search?q=subject',
      searchResults: [
        _SearchHitRecord(
          name: 'dynamic',
          src: '/detail/1?token=abc',
          absoluteUrl: 'https://example.test/detail/1?token=abc',
          sourceId: '',
          sourceBindingKey: 'source:/detail/1?token=abc',
        ),
        _SearchHitRecord(
          name: 'missing source',
          src: '',
          absoluteUrl: '',
          sourceId: '',
          sourceBindingKey: '',
        ),
      ],
      selected: null,
      roads: [
        _RoadRecord.fromRoad(
          0,
          Road(
            name: 'road',
            data: const [
              EpisodeIdentity(
                stableId: 'episode-1',
                pageUrl: '/play/1',
                title: '1',
                roadIndex: 0,
              ),
              EpisodeIdentity(
                stableId: 'episode-1',
                pageUrl: '/play/1-copy',
                title: '1 copy',
                roadIndex: 0,
              ),
              EpisodeIdentity(
                stableId: '',
                pageUrl: '/play/missing',
                title: 'missing',
                roadIndex: 0,
              ),
            ],
          ),
          3,
        ),
      ],
      attempts: const [],
      error: '',
    );

    expect(row.emptyRoadIdCount, 1);
    expect(row.missingStableIdCount, 1);
    expect(row.duplicateStableIdCount, 1);
    expect(row.emptySourceBindingKeyCount, 1);
    expect(row.dynamicSourceQueryCount, 1);
  });
}

class _DefaultRuleProbeCollector {
  _DefaultRuleProbeCollector({
    required this.dio,
    required this.options,
  });

  final Dio dio;
  final _ProbeOptions options;

  Future<_ProbeReport> run() async {
    final plugins = _loadPlugins();
    final subjects = <_SubjectRecord>[];
    for (final seed in _subjectSeeds.take(options.subjectLimit)) {
      subjects.add(await _fetchBangumiSubject(seed));
    }

    final rows = <_PluginSubjectProbe>[];
    for (final subject in subjects) {
      print('Subject ${subjects.indexOf(subject) + 1}/${subjects.length}: '
          '${subject.displayName}');
      for (final plugin in plugins) {
        final row = await _probePluginSubject(plugin, subject);
        rows.add(row);
        print('  ${plugin.name}: ${row.status} '
            'results=${row.searchResultCount} roads=${row.roadCount} '
            'episodes=${row.episodeCount}');
      }
    }

    return _ProbeReport(
      generatedAt: DateTime.now(),
      options: options,
      plugins: plugins.map(_PluginRecord.fromPlugin).toList(),
      subjects: subjects,
      rows: rows,
    );
  }

  List<Plugin> _loadPlugins() {
    final dir = Directory(options.pluginDir);
    if (!dir.existsSync()) {
      throw StateError('Plugin directory not found: ${options.pluginDir}');
    }

    final plugins = dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        .map((file) {
          final json = jsonDecode(file.readAsStringSync());
          return Plugin.fromJson(Map<String, dynamic>.from(json));
        })
        .where((plugin) =>
            options.pluginNames.isEmpty ||
            options.pluginNames.contains(plugin.name))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (plugins.isEmpty) {
      throw StateError('No plugins loaded from ${options.pluginDir}');
    }
    return plugins;
  }

  Future<_SubjectRecord> _fetchBangumiSubject(String seed) async {
    try {
      final url = ApiEndpoints.formatUrl(
        ApiEndpoints.bangumiAPIDomain + ApiEndpoints.bangumiRankSearch,
        [5, 0],
      );
      final response = await dio.post<dynamic>(
        url,
        data: {
          'keyword': seed,
          'sort': 'heat',
          'filter': {
            'type': [2],
            'nsfw': true,
          },
        },
        options: Options(headers: const {'content-type': 'application/json'}),
      );

      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      final items =
          (data as Map<String, dynamic>)['data'] as List<dynamic>? ?? [];
      final candidates = items.whereType<Map<String, dynamic>>().toList()
        ..sort(
            (a, b) => _subjectScore(b, seed).compareTo(_subjectScore(a, seed)));
      if (candidates.isNotEmpty) {
        return _SubjectRecord.fromBangumiJson(seed, candidates.first);
      }
    } catch (error) {
      print('Bangumi subject lookup failed for "$seed": $error');
    }
    return _SubjectRecord.fallback(seed);
  }

  int _subjectScore(Map<String, dynamic> json, String seed) {
    final normalizedSeed = _normalizeText(seed);
    final name = _normalizeText((json['name'] ?? '').toString());
    final nameCn = _normalizeText((json['name_cn'] ?? '').toString());
    var score = 0;
    if (nameCn == normalizedSeed) score += 100;
    if (name == normalizedSeed) score += 90;
    if (nameCn.isNotEmpty &&
        (nameCn.contains(normalizedSeed) || normalizedSeed.contains(nameCn))) {
      score += 35;
    }
    if (name.isNotEmpty &&
        (name.contains(normalizedSeed) || normalizedSeed.contains(name))) {
      score += 25;
    }
    final rank = json['rating'] is Map ? json['rating']['rank'] as int? : null;
    if (rank != null && rank > 0) score += max(0, 20 - (rank ~/ 500));
    return score;
  }

  Future<_PluginSubjectProbe> _probePluginSubject(
    Plugin plugin,
    _SubjectRecord subject,
  ) async {
    final attempts = <_SearchAttemptRecord>[];
    _PluginSubjectProbe? bestNoRoadProbe;

    for (final keyword in subject.keywords.take(options.maxKeywords)) {
      final searchUrl = plugin.searchURL
          .replaceAll('@keyword', Uri.encodeQueryComponent(keyword));
      try {
        final searchHtml = await _fetchPluginSearchHtml(plugin, keyword);
        final captcha = _detectCaptcha(plugin, searchHtml);
        final searchResponse = plugin.testQueryBangumi(searchHtml);
        final searchResults = searchResponse.data
            .take(options.maxSearchResults)
            .map((item) => _SearchHitRecord.fromSearchItem(plugin, item))
            .toList();
        attempts.add(
          _SearchAttemptRecord(
            keyword: keyword,
            searchUrl: searchUrl,
            status: captcha ? 'captcha' : 'parsed',
            resultCount: searchResponse.data.length,
            results: searchResults,
          ),
        );

        if (captcha) {
          return _PluginSubjectProbe(
            subjectSeed: subject.seed,
            bangumiId: subject.id,
            subjectName: subject.displayName,
            pluginName: plugin.name,
            status: 'captcha',
            keyword: keyword,
            searchUrl: searchUrl,
            searchResults: searchResults,
            selected: null,
            roads: const [],
            attempts: attempts,
            error: '',
          );
        }
        if (searchResponse.data.isEmpty) {
          continue;
        }

        final hit = searchResponse.data.first;
        final selected = _SearchHitRecord.fromSearchItem(plugin, hit);
        try {
          final roadHtml = await _fetchPluginRoadHtml(plugin, hit.src);
          final roads = plugin.testQueryChapterRoads(roadHtml);
          final roadRecords = roads
              .asMap()
              .entries
              .map(
                (entry) => _RoadRecord.fromRoad(
                  entry.key,
                  entry.value,
                  options.maxEpisodeSamples,
                ),
              )
              .toList();
          final probe = _PluginSubjectProbe(
            subjectSeed: subject.seed,
            bangumiId: subject.id,
            subjectName: subject.displayName,
            pluginName: plugin.name,
            status: roadRecords.isEmpty ? 'no_roads' : 'success',
            keyword: keyword,
            searchUrl: searchUrl,
            searchResults: searchResults,
            selected: selected,
            roads: roadRecords,
            attempts: attempts,
            error: '',
          );
          if (roadRecords.isNotEmpty) {
            return probe;
          }
          bestNoRoadProbe ??= probe;
        } catch (error) {
          bestNoRoadProbe = _PluginSubjectProbe(
            subjectSeed: subject.seed,
            bangumiId: subject.id,
            subjectName: subject.displayName,
            pluginName: plugin.name,
            status: 'road_error',
            keyword: keyword,
            searchUrl: searchUrl,
            searchResults: searchResults,
            selected: selected,
            roads: const [],
            attempts: attempts,
            error: error.toString(),
          );
        }
      } catch (error) {
        attempts.add(
          _SearchAttemptRecord(
            keyword: keyword,
            searchUrl: searchUrl,
            status: 'search_error',
            resultCount: 0,
            results: const [],
            error: error.toString(),
          ),
        );
      }
    }

    return bestNoRoadProbe ??
        _PluginSubjectProbe(
          subjectSeed: subject.seed,
          bangumiId: subject.id,
          subjectName: subject.displayName,
          pluginName: plugin.name,
          status: attempts.any((attempt) => attempt.status == 'search_error')
              ? 'search_error'
              : 'no_result',
          keyword: attempts.isEmpty ? '' : attempts.last.keyword,
          searchUrl: attempts.isEmpty ? '' : attempts.last.searchUrl,
          searchResults: const [],
          selected: null,
          roads: const [],
          attempts: attempts,
          error: attempts.isEmpty ? '' : attempts.last.error,
        );
  }

  bool _detectCaptcha(Plugin plugin, String html) {
    try {
      return plugin.detectsCaptchaChallenge(html);
    } catch (_) {
      return false;
    }
  }

  Future<String> _fetchPluginSearchHtml(Plugin plugin, String keyword) async {
    final queryUrl = plugin.searchURL
        .replaceAll('@keyword', Uri.encodeQueryComponent(keyword));
    if (plugin.usePost) {
      final uri = Uri.parse(queryUrl);
      final postUri = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: uri.path,
      );
      final response = await dio.post<String>(
        postUri.toString(),
        data: uri.queryParameters,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'referer': '${plugin.baseUrl}/',
            'content-type': 'application/x-www-form-urlencoded',
          },
        ),
      );
      return response.data ?? '';
    }

    final response = await dio.get<String>(
      queryUrl,
      options: Options(
        responseType: ResponseType.plain,
        headers: {'referer': '${plugin.baseUrl}/'},
      ),
    );
    return response.data ?? '';
  }

  Future<String> _fetchPluginRoadHtml(Plugin plugin, String src) async {
    final response = await dio.get<String>(
      _buildPluginUrl(plugin, src),
      options: Options(
        responseType: ResponseType.plain,
        headers: {'referer': '${plugin.baseUrl}/'},
      ),
    );
    return response.data ?? '';
  }
}

class _ProbeOptions {
  const _ProbeOptions({
    required this.subjectLimit,
    required this.timeoutSeconds,
    required this.pluginDir,
    required this.pluginNames,
    required this.outputDir,
    required this.maxKeywords,
    required this.maxSearchResults,
    required this.maxEpisodeSamples,
  });

  final int subjectLimit;
  final int timeoutSeconds;
  final String pluginDir;
  final Set<String> pluginNames;
  final String outputDir;
  final int maxKeywords;
  final int maxSearchResults;
  final int maxEpisodeSamples;

  Map<String, dynamic> toJson() {
    return {
      'subjectLimit': subjectLimit,
      'timeoutSeconds': timeoutSeconds,
      'pluginDir': pluginDir,
      'pluginNames': pluginNames.toList()..sort(),
      'outputDir': outputDir,
      'maxKeywords': maxKeywords,
      'maxSearchResults': maxSearchResults,
      'maxEpisodeSamples': maxEpisodeSamples,
    };
  }
}

class _PluginRecord {
  _PluginRecord({
    required this.name,
    required this.baseUrl,
    required this.searchUrl,
    required this.roadIdXPath,
    required this.episodeIdXPath,
    required this.episodeOrdinalXPath,
  });

  factory _PluginRecord.fromPlugin(Plugin plugin) {
    return _PluginRecord(
      name: plugin.name,
      baseUrl: plugin.baseUrl,
      searchUrl: plugin.searchURL,
      roadIdXPath: plugin.roadId,
      episodeIdXPath: plugin.episodeId,
      episodeOrdinalXPath: plugin.episodeOrdinal,
    );
  }

  final String name;
  final String baseUrl;
  final String searchUrl;
  final String roadIdXPath;
  final String episodeIdXPath;
  final String episodeOrdinalXPath;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'baseUrl': baseUrl,
      'searchUrl': searchUrl,
      'roadIdXPath': roadIdXPath,
      'episodeIdXPath': episodeIdXPath,
      'episodeOrdinalXPath': episodeOrdinalXPath,
    };
  }
}

class _SubjectRecord {
  _SubjectRecord({
    required this.seed,
    required this.id,
    required this.name,
    required this.nameCn,
    required this.aliases,
  });

  factory _SubjectRecord.fromBangumiJson(
    String seed,
    Map<String, dynamic> json,
  ) {
    return _SubjectRecord(
      seed: seed,
      id: json['id'] as int? ?? 0,
      name: (json['name'] ?? '').toString(),
      nameCn: (json['name_cn'] ?? '').toString(),
      aliases: _parseAliases(json['infobox']),
    );
  }

  factory _SubjectRecord.fallback(String seed) {
    return _SubjectRecord(
      seed: seed,
      id: 0,
      name: seed,
      nameCn: seed,
      aliases: const [],
    );
  }

  final String seed;
  final int id;
  final String name;
  final String nameCn;
  final List<String> aliases;

  String get displayName => seed;
  String get bangumiDisplayName => nameCn.isNotEmpty ? nameCn : name;

  List<String> get keywords {
    final values = <String>[
      seed,
      nameCn,
      name,
      ...aliases,
      ..._keywordVariants(seed),
      ..._keywordVariants(nameCn),
      ..._keywordVariants(name),
    ];
    final seen = <String>{};
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && seen.add(value))
        .toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'seed': seed,
      'id': id,
      'name': name,
      'nameCn': nameCn,
      'bangumiDisplayName': bangumiDisplayName,
      'aliases': aliases,
      'keywords': keywords,
    };
  }
}

class _PluginSubjectProbe {
  _PluginSubjectProbe({
    required this.subjectSeed,
    required this.bangumiId,
    required this.subjectName,
    required this.pluginName,
    required this.status,
    required this.keyword,
    required this.searchUrl,
    required this.searchResults,
    required this.selected,
    required this.roads,
    required this.attempts,
    required this.error,
  });

  final String subjectSeed;
  final int bangumiId;
  final String subjectName;
  final String pluginName;
  final String status;
  final String keyword;
  final String searchUrl;
  final List<_SearchHitRecord> searchResults;
  final _SearchHitRecord? selected;
  final List<_RoadRecord> roads;
  final List<_SearchAttemptRecord> attempts;
  final String error;

  int get searchResultCount => searchResults.length;
  int get roadCount => roads.length;
  int get episodeCount => roads.fold(0, (sum, road) => sum + road.episodeCount);
  int get nonEmptyRoadIdCount =>
      roads.where((road) => road.roadId.isNotEmpty).length;
  int get emptyRoadIdCount => roadCount - nonEmptyRoadIdCount;
  int get missingStableIdCount =>
      roads.fold(0, (sum, road) => sum + road.emptyStableIdCount);
  int get duplicateStableIdCount =>
      roads.fold(0, (sum, road) => sum + road.duplicateStableIdCount);
  int get emptySourceBindingKeyCount =>
      searchResults.where((result) => result.sourceBindingKey.isEmpty).length;
  int get dynamicSourceQueryCount =>
      searchResults.where((result) => result.hasDynamicSourceQuery).length;

  Map<String, dynamic> toJson() {
    return {
      'subjectSeed': subjectSeed,
      'bangumiId': bangumiId,
      'subjectName': subjectName,
      'pluginName': pluginName,
      'status': status,
      'keyword': keyword,
      'searchUrl': searchUrl,
      'searchResults': searchResults.map((result) => result.toJson()).toList(),
      'selected': selected?.toJson(),
      'roads': roads.map((road) => road.toJson()).toList(),
      'attempts': attempts.map((attempt) => attempt.toJson()).toList(),
      'error': error,
      'summary': {
        'searchResults': searchResultCount,
        'roads': roadCount,
        'episodes': episodeCount,
        'nonEmptyRoadIds': nonEmptyRoadIdCount,
        'emptyRoadIds': emptyRoadIdCount,
        'missingStableIds': missingStableIdCount,
        'duplicateStableIds': duplicateStableIdCount,
        'emptySourceBindingKeys': emptySourceBindingKeyCount,
        'dynamicSourceQueries': dynamicSourceQueryCount,
      },
    };
  }
}

class _SearchAttemptRecord {
  _SearchAttemptRecord({
    required this.keyword,
    required this.searchUrl,
    required this.status,
    required this.resultCount,
    required this.results,
    this.error = '',
  });

  final String keyword;
  final String searchUrl;
  final String status;
  final int resultCount;
  final List<_SearchHitRecord> results;
  final String error;

  Map<String, dynamic> toJson() {
    return {
      'keyword': keyword,
      'searchUrl': searchUrl,
      'status': status,
      'resultCount': resultCount,
      'results': results.map((result) => result.toJson()).toList(),
      'error': error,
    };
  }
}

class _SearchHitRecord {
  _SearchHitRecord({
    required this.name,
    required this.src,
    required this.absoluteUrl,
    required this.sourceId,
    required this.sourceBindingKey,
  });

  factory _SearchHitRecord.fromSearchItem(Plugin plugin, SearchItem item) {
    return _SearchHitRecord(
      name: item.name,
      src: item.src,
      absoluteUrl: _buildPluginUrl(plugin, item.src),
      sourceId: item.sourceId,
      sourceBindingKey: item.sourceBindingKey(plugin.baseUrl),
    );
  }

  final String name;
  final String src;
  final String absoluteUrl;
  final String sourceId;
  final String sourceBindingKey;

  bool get hasDynamicSourceQuery =>
      _hasDynamicQuery(src) || _hasDynamicQuery(sourceBindingKey);

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'src': src,
      'absoluteUrl': absoluteUrl,
      'sourceId': sourceId,
      'sourceBindingKey': sourceBindingKey,
      'hasDynamicSourceQuery': hasDynamicSourceQuery,
    };
  }
}

class _RoadRecord {
  _RoadRecord({
    required this.index,
    required this.name,
    required this.roadId,
    required this.episodeCount,
    required this.emptyStableIdCount,
    required this.duplicateStableIdCount,
    required this.ordinalCount,
    required this.samples,
  });

  factory _RoadRecord.fromRoad(int index, Road road, int maxEpisodeSamples) {
    final stableIds = <String>{};
    var duplicateStableIds = 0;
    var emptyStableIds = 0;
    var ordinalCount = 0;
    for (final episode in road.data) {
      if (episode.stableId.trim().isEmpty) {
        emptyStableIds++;
      } else if (!stableIds.add(episode.stableId)) {
        duplicateStableIds++;
      }
      if (episode.ordinal != null) {
        ordinalCount++;
      }
    }

    return _RoadRecord(
      index: index,
      name: road.name,
      roadId: road.roadId,
      episodeCount: road.data.length,
      emptyStableIdCount: emptyStableIds,
      duplicateStableIdCount: duplicateStableIds,
      ordinalCount: ordinalCount,
      samples: road.data
          .take(maxEpisodeSamples)
          .toList()
          .asMap()
          .entries
          .map((entry) => _EpisodeSample.fromEpisode(entry.key, entry.value))
          .toList(),
    );
  }

  final int index;
  final String name;
  final String roadId;
  final int episodeCount;
  final int emptyStableIdCount;
  final int duplicateStableIdCount;
  final int ordinalCount;
  final List<_EpisodeSample> samples;

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'name': name,
      'roadId': roadId,
      'episodeCount': episodeCount,
      'emptyStableIdCount': emptyStableIdCount,
      'duplicateStableIdCount': duplicateStableIdCount,
      'ordinalCount': ordinalCount,
      'samples': samples.map((sample) => sample.toJson()).toList(),
    };
  }
}

class _EpisodeSample {
  _EpisodeSample({
    required this.index,
    required this.title,
    required this.ordinal,
    required this.stableId,
    required this.roadId,
    required this.pageUrl,
  });

  factory _EpisodeSample.fromEpisode(int index, EpisodeIdentity episode) {
    return _EpisodeSample(
      index: index,
      title: episode.title,
      ordinal: episode.ordinal,
      stableId: episode.stableId,
      roadId: episode.roadId,
      pageUrl: episode.pageUrl,
    );
  }

  final int index;
  final String title;
  final int? ordinal;
  final String stableId;
  final String roadId;
  final String pageUrl;

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'title': title,
      'ordinal': ordinal,
      'stableId': stableId,
      'roadId': roadId,
      'pageUrl': pageUrl,
    };
  }
}

class _ProbeReport {
  _ProbeReport({
    required this.generatedAt,
    required this.options,
    required this.plugins,
    required this.subjects,
    required this.rows,
  });

  final DateTime generatedAt;
  final _ProbeOptions options;
  final List<_PluginRecord> plugins;
  final List<_SubjectRecord> subjects;
  final List<_PluginSubjectProbe> rows;

  int get totalPluginSubjectPairs => rows.length;
  int get successCount => rows.where((row) => row.status == 'success').length;
  int get totalRoads => rows.fold(0, (sum, row) => sum + row.roadCount);
  int get totalEpisodes => rows.fold(0, (sum, row) => sum + row.episodeCount);

  Future<_OutputFiles> writeFiles(String outputDir) async {
    final dir = Directory(outputDir);
    await dir.create(recursive: true);
    final stamp = generatedAt
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '')
        .replaceAll('-', '');
    final jsonPath = '${dir.path}/default_rule_probe_$stamp.json';
    final mdPath = '${dir.path}/default_rule_probe_$stamp.md';
    await File(jsonPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(toJson()),
    );
    await File(mdPath).writeAsString(toMarkdown());
    return _OutputFiles(jsonPath: jsonPath, markdownPath: mdPath);
  }

  Map<String, dynamic> toJson() {
    return {
      'generatedAt': generatedAt.toIso8601String(),
      'options': options.toJson(),
      'summary': {
        'plugins': plugins.length,
        'subjects': subjects.length,
        'pluginSubjectPairs': totalPluginSubjectPairs,
        'successes': successCount,
        'roads': totalRoads,
        'episodes': totalEpisodes,
        'duplicateStableIds': rows.fold(
          0,
          (sum, row) => sum + row.duplicateStableIdCount,
        ),
        'emptySourceBindingKeys': rows.fold(
          0,
          (sum, row) => sum + row.emptySourceBindingKeyCount,
        ),
        'dynamicSourceQueries': rows.fold(
          0,
          (sum, row) => sum + row.dynamicSourceQueryCount,
        ),
      },
      'plugins': plugins.map((plugin) => plugin.toJson()).toList(),
      'subjects': subjects.map((subject) => subject.toJson()).toList(),
      'pluginStats': _pluginStats().map((stat) => stat.toJson()).toList(),
      'rows': rows.map((row) => row.toJson()).toList(),
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Default Rule Probe')
      ..writeln()
      ..writeln('- Generated: ${generatedAt.toIso8601String()}')
      ..writeln('- Plugins: ${plugins.map((plugin) => plugin.name).join(', ')}')
      ..writeln('- Subjects: ${subjects.length}')
      ..writeln('- Successful plugin/subject pairs: '
          '$successCount/$totalPluginSubjectPairs')
      ..writeln('- Roads: $totalRoads')
      ..writeln('- Episodes: $totalEpisodes')
      ..writeln('- Duplicate stable IDs: '
          '${rows.fold(0, (sum, row) => sum + row.duplicateStableIdCount)}')
      ..writeln('- Empty source binding keys: '
          '${rows.fold(0, (sum, row) => sum + row.emptySourceBindingKeyCount)}')
      ..writeln('- Dynamic source queries: '
          '${rows.fold(0, (sum, row) => sum + row.dynamicSourceQueryCount)}')
      ..writeln()
      ..writeln('## Plugin Summary')
      ..writeln()
      ..writeln(
        '| Plugin | Success | No Result | No Roads | Search Error | Road Error | Captcha | Roads | Episodes | Empty RoadIds | Missing StableIds | Duplicate StableIds | Empty SourceKeys | Dynamic Source Queries |',
      )
      ..writeln(
          '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
    for (final stat in _pluginStats()) {
      buffer.writeln(
        '| ${stat.pluginName} | ${stat.success} | ${stat.noResult} | '
        '${stat.noRoads} | ${stat.searchError} | ${stat.roadError} | '
        '${stat.captcha} | ${stat.roads} | ${stat.episodes} | '
        '${stat.emptyRoadIds} | ${stat.missingStableIds} | '
        '${stat.duplicateStableIds} | ${stat.emptySourceBindingKeys} | '
        '${stat.dynamicSourceQueries} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Rows')
      ..writeln()
      ..writeln(
        '| Subject | Plugin | Status | Keyword | Selected Result | SourceBindingKey | Search Results | Roads | Episodes | Empty RoadIds | Missing StableIds | Duplicate StableIds | Empty SourceKeys | Dynamic Source Queries | First Episode Samples |',
      )
      ..writeln(
          '| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |');
    for (final row in rows) {
      buffer.writeln(
        '| ${_md(row.subjectName)} | ${_md(row.pluginName)} | '
        '${_md(row.status)} | ${_md(row.keyword)} | '
        '${_md(row.selected?.name ?? '')} | '
        '${_md(row.selected?.sourceBindingKey ?? '')} | '
        '${row.searchResultCount} | '
        '${row.roadCount} | ${row.episodeCount} | ${row.emptyRoadIdCount} | '
        '${row.missingStableIdCount} | ${row.duplicateStableIdCount} | '
        '${row.emptySourceBindingKeyCount} | ${row.dynamicSourceQueryCount} | '
        '${_md(_sampleSummary(row))} |',
      );
    }
    return buffer.toString();
  }

  void printSummary(_OutputFiles outputs) {
    print('');
    print('Default rule probe');
    print('  plugins: ${plugins.map((plugin) => plugin.name).join(', ')}');
    print('  subjects: ${subjects.length}');
    print('  successes: $successCount/$totalPluginSubjectPairs');
    print('  roads: $totalRoads');
    print('  episodes: $totalEpisodes');
    print('  json: ${outputs.jsonPath}');
    print('  markdown: ${outputs.markdownPath}');
  }

  List<_PluginStats> _pluginStats() {
    return plugins.map((plugin) {
      final pluginRows = rows.where((row) => row.pluginName == plugin.name);
      return _PluginStats(
        pluginName: plugin.name,
        success: pluginRows.where((row) => row.status == 'success').length,
        noResult: pluginRows.where((row) => row.status == 'no_result').length,
        noRoads: pluginRows.where((row) => row.status == 'no_roads').length,
        searchError:
            pluginRows.where((row) => row.status == 'search_error').length,
        roadError: pluginRows.where((row) => row.status == 'road_error').length,
        captcha: pluginRows.where((row) => row.status == 'captcha').length,
        roads: pluginRows.fold(0, (sum, row) => sum + row.roadCount),
        episodes: pluginRows.fold(0, (sum, row) => sum + row.episodeCount),
        emptyRoadIds:
            pluginRows.fold(0, (sum, row) => sum + row.emptyRoadIdCount),
        missingStableIds:
            pluginRows.fold(0, (sum, row) => sum + row.missingStableIdCount),
        duplicateStableIds:
            pluginRows.fold(0, (sum, row) => sum + row.duplicateStableIdCount),
        emptySourceBindingKeys: pluginRows.fold(
          0,
          (sum, row) => sum + row.emptySourceBindingKeyCount,
        ),
        dynamicSourceQueries:
            pluginRows.fold(0, (sum, row) => sum + row.dynamicSourceQueryCount),
      );
    }).toList();
  }

  String _sampleSummary(_PluginSubjectProbe row) {
    final samples = row.roads
        .expand((road) => road.samples)
        .take(3)
        .map((sample) => sample.ordinal == null
            ? sample.title
            : '${sample.title}(${sample.ordinal})')
        .where((sample) => sample.trim().isNotEmpty)
        .toList();
    return samples.join(', ');
  }
}

class _PluginStats {
  _PluginStats({
    required this.pluginName,
    required this.success,
    required this.noResult,
    required this.noRoads,
    required this.searchError,
    required this.roadError,
    required this.captcha,
    required this.roads,
    required this.episodes,
    required this.emptyRoadIds,
    required this.missingStableIds,
    required this.duplicateStableIds,
    required this.emptySourceBindingKeys,
    required this.dynamicSourceQueries,
  });

  final String pluginName;
  final int success;
  final int noResult;
  final int noRoads;
  final int searchError;
  final int roadError;
  final int captcha;
  final int roads;
  final int episodes;
  final int emptyRoadIds;
  final int missingStableIds;
  final int duplicateStableIds;
  final int emptySourceBindingKeys;
  final int dynamicSourceQueries;

  Map<String, dynamic> toJson() {
    return {
      'pluginName': pluginName,
      'success': success,
      'noResult': noResult,
      'noRoads': noRoads,
      'searchError': searchError,
      'roadError': roadError,
      'captcha': captcha,
      'roads': roads,
      'episodes': episodes,
      'emptyRoadIds': emptyRoadIds,
      'missingStableIds': missingStableIds,
      'duplicateStableIds': duplicateStableIds,
      'emptySourceBindingKeys': emptySourceBindingKeys,
      'dynamicSourceQueries': dynamicSourceQueries,
    };
  }
}

class _OutputFiles {
  const _OutputFiles({
    required this.jsonPath,
    required this.markdownPath,
  });

  final String jsonPath;
  final String markdownPath;
}

List<String> _parseAliases(dynamic infobox) {
  if (infobox is! List) return const [];
  for (final item in infobox) {
    if (item is! Map || item['key'] != '别名') continue;
    final raw = item['values'] ?? item['value'];
    if (raw is List) {
      return raw
          .map((value) {
            if (value is Map && value.containsKey('v')) {
              return value['v'].toString();
            }
            return value.toString();
          })
          .where((value) => value.trim().isNotEmpty)
          .toList();
    }
    if (raw == null) return const [];
    final value = raw.toString().trim();
    return value.isEmpty ? const [] : [value];
  }
  return const [];
}

Set<String> _parsePluginNames(String value) {
  return value
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toSet();
}

List<String> _keywordVariants(String value) {
  final variants = <String>[];
  final withoutPunctuation =
      value.replaceAll(RegExp(r'[【】\[\]（）()!！?？:：·・\s]'), '').trim();
  if (withoutPunctuation != value.trim()) {
    variants.add(withoutPunctuation);
  }
  final asciiColon = value.replaceAll('：', ':').trim();
  if (asciiColon != value.trim()) {
    variants.add(asciiColon);
  }
  final xVariant = value.replaceAll('×', 'x').trim();
  if (xVariant != value.trim()) {
    variants.add(xVariant);
  }
  return variants;
}

String _buildPluginUrl(Plugin plugin, String src) {
  final trimmed = src.trim();
  if (trimmed.isEmpty) return trimmed;
  var url = trimmed;
  if (!url.contains('https')) {
    url = url.replaceAll('http', 'https');
  }
  if (url.contains(plugin.baseUrl)) {
    return url;
  }
  return plugin.baseUrl + url;
}

String _normalizeText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[【】\[\]（）()!！?？:：·・\s]'), '')
      .replaceAll('×', 'x')
      .trim();
}

bool _hasDynamicQuery(String value) {
  final normalized =
      value.startsWith('source:') ? value.substring('source:'.length) : value;
  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.queryParameters.isEmpty) {
    return false;
  }
  const exactDynamicKeys = {
    '_',
    'expire',
    'expires',
    'nonce',
    'random',
    'rnd',
    'sign',
    'signature',
    't',
    'time',
    'timestamp',
    'token',
    'ts',
  };
  for (final key in uri.queryParameters.keys) {
    final normalizedKey = key.toLowerCase();
    if (exactDynamicKeys.contains(normalizedKey) ||
        normalizedKey.contains('token') ||
        normalizedKey.contains('time') ||
        normalizedKey.contains('sign')) {
      return true;
    }
  }
  return false;
}

String _md(String value) {
  return value
      .replaceAll('|', r'\|')
      .replaceAll('\r', ' ')
      .replaceAll('\n', ' ')
      .trim();
}

// ignore_for_file: avoid_print

// Live smoke for Scheme A roadId semantics.
//
// Run manually when network access and plugin sites are acceptable:
// flutter test test/live/season_road_id_smoke_test.dart --dart-define=KAZUMI_LIVE_ROAD_ID=true
//
// Empty roadId is tolerated only below the stable-subject coverage gate. This
// test always fails on synthetic fallback values such as episodes:/road-index:
// and on Road/Episode roadId mismatch. Add
// --dart-define=KAZUMI_LIVE_ROAD_ID_STRICT=true to require non-empty explicit
// roadId for every parsed road.
// KAZUMI_LIVE_ROAD_ID_MIN_STABLE_SUBJECTS defaults to 16 for a 20-subject
// sample, which encodes the "most current-season subjects" coverage gate.

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/utils/anime_season.dart';

const _liveRoadIdEnabled = bool.fromEnvironment('KAZUMI_LIVE_ROAD_ID');
const _subjectLimit =
    int.fromEnvironment('KAZUMI_LIVE_ROAD_ID_LIMIT', defaultValue: 20);
const _subjectOffset =
    int.fromEnvironment('KAZUMI_LIVE_ROAD_ID_OFFSET', defaultValue: 0);
const _timeoutSeconds = int.fromEnvironment(
    'KAZUMI_LIVE_ROAD_ID_TIMEOUT_SECONDS',
    defaultValue: 10);
const _pluginDir = String.fromEnvironment(
  'KAZUMI_LIVE_ROAD_ID_PLUGIN_DIR',
  defaultValue: 'assets/plugins',
);
const _pluginNamesCsv = String.fromEnvironment('KAZUMI_LIVE_ROAD_ID_PLUGINS');
const _strictRoadId =
    bool.fromEnvironment('KAZUMI_LIVE_ROAD_ID_STRICT', defaultValue: false);
const _minSubjectsWithRoads = int.fromEnvironment(
  'KAZUMI_LIVE_ROAD_ID_MIN_SUBJECTS_WITH_ROADS',
  defaultValue: 1,
);
const _minStableSubjects = int.fromEnvironment(
  'KAZUMI_LIVE_ROAD_ID_MIN_STABLE_SUBJECTS',
  defaultValue: 16,
);
const _verboseRoadIdSmoke =
    bool.fromEnvironment('KAZUMI_LIVE_ROAD_ID_VERBOSE', defaultValue: false);

void main() {
  test(
    'current season plugins provide stable roadId coverage',
    () async {
      final options = _Options(
        limit: _subjectLimit,
        offset: _subjectOffset,
        timeoutSeconds: _timeoutSeconds,
        pluginDir: _pluginDir,
        pluginNames: _parsePluginNames(_pluginNamesCsv),
        strictRoadId: _strictRoadId,
        minSubjectsWithRoads: _minSubjectsWithRoads,
        minStableSubjects: _minStableSubjects,
        verbose: _verboseRoadIdSmoke,
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
                'Predidit/Kazumi/${ApiEndpoints.version} (RoadIdSmokeTest)',
            'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
          },
        ),
      );
      addTearDown(() => dio.close(force: true));

      final runner = _RoadIdSmokeRunner(dio: dio, options: options);
      final report = await runner.run();
      report.printSummary();

      expect(report.passed, isTrue, reason: report.failureReason);
    },
    skip: _liveRoadIdEnabled
        ? false
        : 'Set --dart-define=KAZUMI_LIVE_ROAD_ID=true to run this live smoke test.',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

class _RoadIdSmokeRunner {
  _RoadIdSmokeRunner({
    required this.dio,
    required this.options,
  });

  final Dio dio;
  final _Options options;

  Future<_SmokeReport> run() async {
    final season = AnimeSeason(DateTime.now());
    final range = season.toSeasonStartAndEnd().map(_dateOnly).toList();
    final plugins = _loadPlugins();
    final subjects = await _fetchSeasonSubjects(range);
    final rows = <_ProbeRow>[];

    for (var index = 0; index < subjects.length; index++) {
      final subject = subjects[index];
      final row = await _probeSubject(index + 1, subject, plugins);
      rows.add(row);
      if (options.verbose) {
        row.printLine();
      }
    }

    return _SmokeReport(
      seasonLabel: season.toString(),
      range: range,
      requestedSubjects: options.limit,
      subjects: subjects,
      plugins: plugins,
      rows: rows,
      strictRoadId: options.strictRoadId,
      minSubjectsWithRoads: options.minSubjectsWithRoads,
      minStableSubjects: options.minStableSubjects,
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

  Future<List<_SeasonSubject>> _fetchSeasonSubjects(List<String> range) async {
    final url = ApiEndpoints.formatUrl(
      ApiEndpoints.bangumiAPIDomain + ApiEndpoints.bangumiRankSearch,
      [options.limit, options.offset],
    );
    final response = await dio.post<dynamic>(
      url,
      data: {
        'keyword': '',
        'sort': 'heat',
        'filter': {
          'type': [2],
          'tag': ['日本'],
          'air_date': ['>=${range[0]}', '<${range[1]}'],
          'rank': ['>=0', '<=99999'],
          'nsfw': true,
        },
      },
      options: Options(
        headers: const {
          'content-type': 'application/json',
          'referer': '',
        },
      ),
    );

    final data = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
    final items =
        (data as Map<String, dynamic>)['data'] as List<dynamic>? ?? [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(_SeasonSubject.fromJson)
        .take(options.limit)
        .toList();
  }

  Future<_ProbeRow> _probeSubject(
    int index,
    _SeasonSubject subject,
    List<Plugin> plugins,
  ) async {
    final attempts = <String>[];
    _ProbeRow? bestRow;

    for (final plugin in plugins) {
      for (final keyword in subject.keywords) {
        try {
          final searchHtml = await _fetchPluginSearchHtml(plugin, keyword);
          final searchResult = plugin.testQueryBangumi(searchHtml);
          if (searchResult.data.isEmpty) {
            attempts.add('${plugin.name}: no search result for "$keyword"');
            continue;
          }

          final hit = searchResult.data.first;
          final roadHtml = await _fetchPluginRoadHtml(plugin, hit.src);
          final roads = plugin.testQueryChapterRoads(roadHtml);
          final row = _ProbeRow.fromRoads(
            index: index,
            subject: subject,
            pluginName: plugin.name,
            keyword: keyword,
            searchTitle: hit.name,
            roads: roads,
            strictRoadId: options.strictRoadId,
          );
          if (roads.isNotEmpty) {
            return row;
          }
          attempts.add('${plugin.name}: no roads for "${hit.name}"');
          bestRow ??= row;
        } catch (error) {
          attempts.add('${plugin.name}: ${error.runtimeType}');
        }
      }
    }

    return bestRow ??
        _ProbeRow.noRoads(
          index: index,
          subject: subject,
          attempts: attempts,
        );
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
        headers: {
          'referer': '${plugin.baseUrl}/',
        },
      ),
    );
    return response.data ?? '';
  }

  Future<String> _fetchPluginRoadHtml(Plugin plugin, String src) async {
    var url = src;
    if (!url.contains('https')) {
      url = url.replaceAll('http', 'https');
    }
    final queryUrl = url.contains(plugin.baseUrl) ? url : plugin.baseUrl + url;
    final response = await dio.get<String>(
      queryUrl,
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'referer': '${plugin.baseUrl}/',
        },
      ),
    );
    return response.data ?? '';
  }
}

class _SeasonSubject {
  _SeasonSubject({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.aliases,
  });

  factory _SeasonSubject.fromJson(Map<String, dynamic> json) {
    return _SeasonSubject(
      id: json['id'] as int? ?? 0,
      name: (json['name'] ?? '').toString(),
      nameCn: (json['name_cn'] ?? '').toString(),
      aliases: _parseAliases(json['infobox']),
    );
  }

  final int id;
  final String name;
  final String nameCn;
  final List<String> aliases;

  String get displayName => nameCn.isNotEmpty ? nameCn : name;

  List<String> get keywords {
    final values = <String>[
      nameCn,
      name,
      ...aliases,
    ];
    final seen = <String>{};
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && seen.add(value))
        .take(3)
        .toList();
  }

  static List<String> _parseAliases(dynamic infobox) {
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
}

class _ProbeRow {
  _ProbeRow({
    required this.index,
    required this.subject,
    required this.pluginName,
    required this.keyword,
    required this.searchTitle,
    required this.roads,
    required this.episodes,
    required this.emptyRoadIds,
    required this.explicitRoadIds,
    required this.syntheticRoadIds,
    required this.inconsistentEpisodeRoadIds,
    required this.strictFailures,
    required this.attempts,
  });

  factory _ProbeRow.fromRoads({
    required int index,
    required _SeasonSubject subject,
    required String pluginName,
    required String keyword,
    required String searchTitle,
    required List<dynamic> roads,
    required bool strictRoadId,
  }) {
    var episodes = 0;
    var emptyRoadIds = 0;
    var explicitRoadIds = 0;
    var syntheticRoadIds = 0;
    var inconsistentEpisodeRoadIds = 0;
    var strictFailures = 0;

    for (final road in roads) {
      final roadId = road.roadId as String;
      if (roadId.isEmpty) {
        emptyRoadIds++;
        if (strictRoadId) strictFailures++;
      } else {
        explicitRoadIds++;
      }
      if (roadId.startsWith('episodes:') || roadId.startsWith('road-index:')) {
        syntheticRoadIds++;
      }
      for (final episode in road.data) {
        episodes++;
        if (episode.roadId != roadId) {
          inconsistentEpisodeRoadIds++;
        }
      }
    }

    return _ProbeRow(
      index: index,
      subject: subject,
      pluginName: pluginName,
      keyword: keyword,
      searchTitle: searchTitle,
      roads: roads.length,
      episodes: episodes,
      emptyRoadIds: emptyRoadIds,
      explicitRoadIds: explicitRoadIds,
      syntheticRoadIds: syntheticRoadIds,
      inconsistentEpisodeRoadIds: inconsistentEpisodeRoadIds,
      strictFailures: strictFailures,
      attempts: const [],
    );
  }

  factory _ProbeRow.noRoads({
    required int index,
    required _SeasonSubject subject,
    required List<String> attempts,
  }) {
    return _ProbeRow(
      index: index,
      subject: subject,
      pluginName: '',
      keyword: '',
      searchTitle: '',
      roads: 0,
      episodes: 0,
      emptyRoadIds: 0,
      explicitRoadIds: 0,
      syntheticRoadIds: 0,
      inconsistentEpisodeRoadIds: 0,
      strictFailures: 0,
      attempts: attempts,
    );
  }

  final int index;
  final _SeasonSubject subject;
  final String pluginName;
  final String keyword;
  final String searchTitle;
  final int roads;
  final int episodes;
  final int emptyRoadIds;
  final int explicitRoadIds;
  final int syntheticRoadIds;
  final int inconsistentEpisodeRoadIds;
  final int strictFailures;
  final List<String> attempts;

  bool get hasRoads => roads > 0;
  bool get hasStableRoadIdentity =>
      hasRoads &&
      emptyRoadIds == 0 &&
      syntheticRoadIds == 0 &&
      inconsistentEpisodeRoadIds == 0;

  void printLine() {
    if (!hasRoads) {
      print(
        '[$index] ${subject.displayName} (#${subject.id}): no roads (${attempts.take(3).join('; ')})',
      );
      return;
    }
    print(
      '[$index] ${subject.displayName} (#${subject.id}): $pluginName "$searchTitle", '
      'keyword="$keyword", '
      'roads=$roads episodes=$episodes roadId(explicit=$explicitRoadIds empty=$emptyRoadIds)',
    );
  }
}

class _SmokeReport {
  _SmokeReport({
    required this.seasonLabel,
    required this.range,
    required this.requestedSubjects,
    required this.subjects,
    required this.plugins,
    required this.rows,
    required this.strictRoadId,
    required this.minSubjectsWithRoads,
    required this.minStableSubjects,
  });

  final String seasonLabel;
  final List<String> range;
  final int requestedSubjects;
  final List<_SeasonSubject> subjects;
  final List<Plugin> plugins;
  final List<_ProbeRow> rows;
  final bool strictRoadId;
  final int minSubjectsWithRoads;
  final int minStableSubjects;

  int get subjectsWithRoads => rows.where((row) => row.hasRoads).length;
  int get roadsChecked => rows.fold(0, (sum, row) => sum + row.roads);
  int get episodesChecked => rows.fold(0, (sum, row) => sum + row.episodes);
  int get emptyRoadIds => rows.fold(0, (sum, row) => sum + row.emptyRoadIds);
  int get explicitRoadIds =>
      rows.fold(0, (sum, row) => sum + row.explicitRoadIds);
  int get syntheticRoadIds =>
      rows.fold(0, (sum, row) => sum + row.syntheticRoadIds);
  int get inconsistentEpisodeRoadIds =>
      rows.fold(0, (sum, row) => sum + row.inconsistentEpisodeRoadIds);
  int get strictFailures =>
      rows.fold(0, (sum, row) => sum + row.strictFailures);
  int get stableRoadIdentitySubjects =>
      rows.where((row) => row.hasStableRoadIdentity).length;

  bool get passed {
    return subjects.length >= requestedSubjects &&
        subjectsWithRoads >= minSubjectsWithRoads &&
        stableRoadIdentitySubjects >= minStableSubjects &&
        roadsChecked > 0 &&
        syntheticRoadIds == 0 &&
        inconsistentEpisodeRoadIds == 0 &&
        strictFailures == 0;
  }

  String get failureReason {
    final reasons = <String>[];
    if (subjects.length < requestedSubjects) {
      reasons.add(
        'Bangumi returned ${subjects.length}/$requestedSubjects current-season subjects.',
      );
    }
    if (subjectsWithRoads < minSubjectsWithRoads) {
      reasons.add(
        'Only $subjectsWithRoads subjects produced roads; required $minSubjectsWithRoads.',
      );
    }
    if (roadsChecked == 0) {
      reasons.add('No roads were parsed from plugin results.');
    }
    if (stableRoadIdentitySubjects < minStableSubjects) {
      reasons.add(
        'Only $stableRoadIdentitySubjects subjects have stable road identity; required $minStableSubjects.',
      );
    }
    if (syntheticRoadIds > 0) {
      reasons.add(
        'Found $syntheticRoadIds synthetic roadIds with episodes:/road-index: fallback.',
      );
    }
    if (inconsistentEpisodeRoadIds > 0) {
      reasons.add(
        'Found $inconsistentEpisodeRoadIds episodes whose roadId differs from their Road.roadId.',
      );
    }
    if (strictFailures > 0) {
      reasons.add(
        'Found $strictFailures empty roadIds while strict roadId mode is enabled.',
      );
    }
    return reasons.join('\n');
  }

  void printSummary() {
    print('Season roadId smoke test');
    print('Season: $seasonLabel (${range[0]} to ${range[1]})');
    print('Subjects: ${subjects.length}/$requestedSubjects');
    print('Plugins: ${plugins.map((plugin) => plugin.name).join(', ')}');
    print('');
    for (final row in rows) {
      row.printLine();
    }
    print('');
    print('Summary');
    print('  subjectsWithRoads: $subjectsWithRoads');
    print('  stableRoadIdentitySubjects: $stableRoadIdentitySubjects');
    print('  roadsChecked: $roadsChecked');
    print('  episodesChecked: $episodesChecked');
    print('  explicitRoadIds: $explicitRoadIds');
    print('  emptyRoadIds: $emptyRoadIds');
    print('  syntheticRoadIds: $syntheticRoadIds');
    print('  inconsistentEpisodeRoadIds: $inconsistentEpisodeRoadIds');
    if (strictRoadId) {
      print('  strictEmptyRoadIdFailures: $strictFailures');
    }
    if (explicitRoadIds == 0) {
      print(
        '  note: no explicit roadId was produced; this is expected when rules do not define roadId XPath.',
      );
    }
    print('');
    print(passed ? 'PASS' : 'FAIL');
  }
}

class _Options {
  _Options({
    required this.limit,
    required this.offset,
    required this.timeoutSeconds,
    required this.pluginDir,
    required this.pluginNames,
    required this.strictRoadId,
    required this.minSubjectsWithRoads,
    required this.minStableSubjects,
    required this.verbose,
  });

  final int limit;
  final int offset;
  final int timeoutSeconds;
  final String pluginDir;
  final Set<String> pluginNames;
  final bool strictRoadId;
  final int minSubjectsWithRoads;
  final int minStableSubjects;
  final bool verbose;
}

String _dateOnly(String value) {
  return value.length >= 10 ? value.substring(0, 10) : value;
}

Set<String> _parsePluginNames(String value) {
  return value
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toSet();
}

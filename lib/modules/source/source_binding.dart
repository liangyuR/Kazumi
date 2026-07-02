import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/utils/episode_url.dart';

class SourceConfirmationKind {
  static const String manual = 'manual';
  static const String legacy = 'legacy';

  static String normalize(String value) {
    return value == legacy ? legacy : manual;
  }

  SourceConfirmationKind._();
}

class SourceBinding {
  const SourceBinding({
    required this.bangumiId,
    required this.pluginName,
    required this.sourceBindingKey,
    required this.sourceTitle,
    required this.sourceUrl,
    required this.confirmedAt,
    this.confirmationKind = SourceConfirmationKind.manual,
  });

  final int bangumiId;
  final String pluginName;
  final String sourceBindingKey;
  final String sourceTitle;
  final String sourceUrl;
  final int confirmedAt;
  final String confirmationKind;

  bool get isBound =>
      bangumiId > 0 &&
      pluginName.trim().isNotEmpty &&
      sourceBindingKey.trim().isNotEmpty;

  SourceBinding copyWith({
    int? bangumiId,
    String? pluginName,
    String? sourceBindingKey,
    String? sourceTitle,
    String? sourceUrl,
    int? confirmedAt,
    String? confirmationKind,
  }) {
    return SourceBinding(
      bangumiId: bangumiId ?? this.bangumiId,
      pluginName: pluginName ?? this.pluginName,
      sourceBindingKey: sourceBindingKey ?? this.sourceBindingKey,
      sourceTitle: sourceTitle ?? this.sourceTitle,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      confirmationKind: confirmationKind ?? this.confirmationKind,
    );
  }

  factory SourceBinding.manual({
    required BangumiItem bangumiItem,
    required String pluginName,
    required String sourceTitle,
    required String sourceUrl,
    required String baseUrl,
    String sourceId = '',
    DateTime? confirmedAt,
  }) {
    final now = confirmedAt ?? DateTime.now();
    return SourceBinding(
      bangumiId: bangumiItem.id,
      pluginName: pluginName,
      sourceBindingKey: sourceBindingKeyFromSource(
        baseUrl: baseUrl,
        sourceUrl: sourceUrl,
        sourceId: sourceId,
      ),
      sourceTitle: sourceTitle,
      sourceUrl: normalizeEpisodeUrl(baseUrl, sourceUrl),
      confirmedAt: now.millisecondsSinceEpoch,
    );
  }

  factory SourceBinding.fromHistoryFields({
    required BangumiItem bangumiItem,
    required String pluginName,
    required String sourceBindingKey,
    required String sourceTitle,
    required String sourceUrl,
    required int confirmedAt,
    required String confirmationKind,
  }) {
    return SourceBinding(
      bangumiId: bangumiItem.id,
      pluginName: pluginName,
      sourceBindingKey: sourceBindingKey,
      sourceTitle: sourceTitle,
      sourceUrl: sourceUrl,
      confirmedAt: confirmedAt,
      confirmationKind: SourceConfirmationKind.normalize(confirmationKind),
    );
  }
}

String sourceBindingKeyFromSource({
  required String baseUrl,
  required String sourceUrl,
  String sourceId = '',
}) {
  final explicit = sourceId.trim();
  if (explicit.isNotEmpty) {
    final explicitUri = Uri.tryParse(explicit);
    if (explicit.startsWith('/') ||
        (explicitUri != null && explicitUri.hasScheme)) {
      return sourceBindingKeyFromSource(
        baseUrl: baseUrl,
        sourceUrl: explicit,
      );
    }
    return 'sourceId:$explicit';
  }

  final normalized = normalizeEpisodeUrl(baseUrl, sourceUrl);
  if (normalized.isEmpty) {
    return '';
  }

  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.host.isEmpty) {
    return 'source:$normalized';
  }

  final path = uri.path.isEmpty ? '/' : uri.path;
  if (uri.query.isEmpty) {
    return 'source:$path';
  }
  return 'source:${Uri(path: path, query: uri.query)}';
}

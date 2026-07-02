import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/source/source_binding.dart';

class SearchItem {
  String name;
  String src;
  String sourceId;

  SearchItem({
    required this.name,
    required this.src,
    this.sourceId = '',
  });

  factory SearchItem.fromJson(Map<String, dynamic> json) {
    return SearchItem(
      name: json['name'],
      src: json['src'],
      sourceId: json['sourceId'] as String? ?? '',
    );
  }

  String sourceBindingKey(String baseUrl) {
    return sourceBindingKeyFromSource(
      baseUrl: baseUrl,
      sourceUrl: src,
      sourceId: sourceId,
    );
  }

  SourceBinding toSourceBinding({
    required BangumiItem bangumiItem,
    required String pluginName,
    required String baseUrl,
    DateTime? confirmedAt,
  }) {
    return SourceBinding.manual(
      bangumiItem: bangumiItem,
      pluginName: pluginName,
      sourceTitle: name,
      sourceUrl: src,
      sourceId: sourceId,
      baseUrl: baseUrl,
      confirmedAt: confirmedAt,
    );
  }
}

class PluginSearchResponse {
  String pluginName;
  List<SearchItem> data;

  PluginSearchResponse({
    required this.pluginName,
    required this.data,
  });

  factory PluginSearchResponse.fromJson(Map<String, dynamic> json) {
    return PluginSearchResponse(
      pluginName: json['pluginName'],
      data: (json['data'] as List)
          .map((itemJson) => SearchItem.fromJson(itemJson))
          .toList(),
    );
  }
}

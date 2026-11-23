import 'dart:convert';
import 'package:http/http.dart' as http;

class ConfigFetchResult {
  final List<String> configs;
  final List<String> logs;

  ConfigFetchResult({required this.configs, required this.logs});
}

class ConfigService {
  static const List<String> _sources = [
    'https://cdn.jsdelivr.net/gh/barry-far/V2ray-Configs@main/All_Configs_Sub.txt',
    'https://cdn.jsdelivr.net/gh/Epodonios/v2ray-configs@main/All_Configs_Sub.txt',
    'https://cdn.jsdelivr.net/gh/mahdibland/V2RayAggregator@master/sub/sub_merge.txt',
    'https://raw.githubusercontent.com/barry-far/V2ray-Configs/main/All_Configs_Sub.txt',
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/All_Configs_Sub.txt',
  ];

  static Future<List<String>> fetchAutoConfigs() async {
    final result = await fetchWithLogs();
    return result.configs;
  }

  static Future<ConfigFetchResult> fetchWithLogs() async {
    final List<String> configs = [];
    final List<String> logs = [];

    for (int i = 0; i < _sources.length; i++) {
      final url = _sources[i];
      try {
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final parsed = _parseRawConfigs(response.body);
          logs.add('Source ${i + 1}: OK (${parsed.length} configs)');
          configs.addAll(parsed);
          if (configs.length >= 20) break;
        } else {
          logs.add('Source ${i + 1}: HTTP ${response.statusCode}');
        }
      } catch (e) {
        logs.add('Source ${i + 1}: Failed (${e.runtimeType})');
        continue;
      }
    }

    final unique = configs.toSet().toList();
    unique.shuffle();
    return ConfigFetchResult(configs: unique, logs: logs);
  }

  static List<String> _parseRawConfigs(String body) {
    String text = body.trim();
    if (!text.contains('://')) {
      try {
        final normalized =
            base64.normalize(text.replaceAll(RegExp(r'\s+'), ''));
        text = utf8.decode(base64.decode(normalized));
      } catch (_) {}
    }

    const supportedPrefixes = [
      'vless://',
      'vmess://',
      'trojan://',
      'ss://',
    ];

    return text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => supportedPrefixes.any((p) => line.startsWith(p)))
        .toList();
  }
}
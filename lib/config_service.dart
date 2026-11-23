import 'dart:convert';
import 'package:http/http.dart' as http;

class ConfigService {
  static const List<String> _sources = [
    'https://raw.githubusercontent.com/barry-far/V2ray-Configs/main/Sub1.txt',
    'https://raw.githubusercontent.com/yebekhe/TVC/main/subscriptions/xray/normal/mix',
  ];

  static Future<List<String>> fetchAutoConfigs() async {
    final List<String> configs = [];

    for (final url in _sources) {
      try {
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final parsed = _parseRawConfigs(response.body);
          configs.addAll(parsed);
          if (configs.isNotEmpty) break;
        }
      } catch (_) {
        continue;
      }
    }

    return configs.toSet().toList();
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
      'hy2://',
      'tuic://',
    ];

    return text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => supportedPrefixes.any((p) => line.startsWith(p)))
        .toList();
  }
}
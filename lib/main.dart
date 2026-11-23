import 'package:flutter/material.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config_service.dart';

void main() {
  runApp(const NoorVpnApp());
}

class NoorVpnApp extends StatelessWidget {
  const NoorVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NOORVPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5A0),
          secondary: Color(0xFF2F81F7),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<String> cores = ['Smart Auto', 'Sing-box', 'WARP', 'Psiphon'];
  String selectedCore = 'Smart Auto';
  bool isConnected = false;
  bool isConnecting = false;
  bool _cancelRequested = false;
  String statusText = 'Disconnected';
  String _activeRemark = 'NOORVPN';

  late final FlutterV2ray _v2ray;
  V2RayStatus? _v2rayStatus;

  @override
  void initState() {
    super.initState();
    _loadSelectedCore();
    _v2ray = FlutterV2ray(
      onStatusChanged: (status) {
        if (!mounted) return;
        final state = status.state.toUpperCase();
        setState(() {
          _v2rayStatus = status;
          if (state == 'CONNECTED') {
            isConnected = true;
            isConnecting = false;
            statusText = 'Connected ($_activeRemark)';
          } else if (state == 'DISCONNECTED') {
            isConnected = false;
            if (!isConnecting) {
              statusText = 'Disconnected';
            }
          }
        });
      },
    );
    _v2ray.initializeV2Ray();
  }

  Future<void> _loadSelectedCore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('selected_core');
    if (saved != null && cores.contains(saved) && mounted) {
      setState(() => selectedCore = saved);
    }
  }

  Future<void> _selectCore(String core) async {
    if (isConnected || isConnecting) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_core', core);
    if (!mounted) return;
    setState(() => selectedCore = core);
  }

  Future<void> _toggleConnection() async {
    if (isConnected || isConnecting) {
      _cancelRequested = true;
      await _v2ray.stopV2Ray();
      if (!mounted) return;
      setState(() {
        isConnected = false;
        isConnecting = false;
        statusText = 'Disconnected';
      });
      return;
    }

    _cancelRequested = false;
    setState(() {
      isConnecting = true;
      statusText = 'Requesting VPN permission...';
    });

    final bool hasPermission = await _v2ray.requestPermission();
    if (!mounted) return;
    if (!hasPermission) {
      setState(() {
        isConnecting = false;
        statusText = 'VPN permission denied';
      });
      return;
    }

    setState(() => statusText = 'Fetching auto configs...');
    final List<String> allConfigs = await ConfigService.fetchAutoConfigs();
    if (!mounted || _cancelRequested) return;

    final List<String> xrayConfigs = allConfigs
        .where((c) =>
            c.startsWith('vless://') ||
            c.startsWith('vmess://') ||
            c.startsWith('trojan://') ||
            c.startsWith('ss://'))
        .toList();

    if (xrayConfigs.isEmpty) {
      setState(() {
        isConnecting = false;
        statusText = 'No configs found. Check internet.';
      });
      return;
    }

    String? bestConfigJson;
    String bestRemark = 'NOORVPN Auto';
    String? fallbackConfigJson;
    String fallbackRemark = 'NOORVPN Auto';

    final int maxToTest = xrayConfigs.length < 15 ? xrayConfigs.length : 15;
    for (int i = 0; i < maxToTest; i++) {
      if (!mounted || _cancelRequested) return;

      setState(() {
        statusText = 'Testing server ${i + 1}/$maxToTest...';
      });

      try {
        final V2RayURL parser = FlutterV2ray.parseFromURL(xrayConfigs[i]);
        final String fullConfig = parser.getFullConfiguration();
        final String remark =
            parser.remark.trim().isEmpty ? 'NOORVPN #${i + 1}' : parser.remark;

        fallbackConfigJson ??= fullConfig;
        if (fallbackConfigJson == fullConfig) {
          fallbackRemark = remark;
        }

        final int delay = await _v2ray
            .getServerDelay(config: fullConfig)
            .timeout(const Duration(seconds: 4), onTimeout: () => -1);

        if (delay > 0) {
          bestConfigJson = fullConfig;
          bestRemark = '$remark (${delay}ms)';
          break;
        }
      } catch (_) {
        continue;
      }
    }

    if (!mounted || _cancelRequested) return;

    final String? finalConfig = bestConfigJson ?? fallbackConfigJson;
    final String finalRemark =
        bestConfigJson != null ? bestRemark : fallbackRemark;

    if (finalConfig == null) {
      setState(() {
        isConnecting = false;
        statusText = 'No valid server found';
      });
      return;
    }

    setState(() {
      _activeRemark = finalRemark;
      statusText = 'Starting tunnel...';
    });

    try {
      await _v2ray.startV2Ray(
        remark: finalRemark,
        config: finalConfig,
        proxyOnly: false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isConnecting = false;
        statusText = 'Connection failed';
      });
    }
  }

  String _formatSpeed(int bytesPerSec) {
    if (bytesPerSec < 1024) return '$bytesPerSec B/s';
    if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  @override
  Widget build(BuildContext context) {
    final Color activeColor = isConnected
        ? const Color(0xFF00E5A0)
        : (isConnecting ? const Color(0xFFFFB020) : const Color(0xFF30363D));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'NOORVPN',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 2.5,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const Text(
                'SELECT ENGINE CORE',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: cores.map((core) {
                  final bool isSelected = selectedCore == core;
                  return ChoiceChip(
                    label: Text(core),
                    selected: isSelected,
                    selectedColor: const Color(0xFF00E5A0),
                    backgroundColor: const Color(0xFF161B22),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.black : Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) => _selectCore(core),
                  );
                }).toList(),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _toggleConnection,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF161B22),
                    border: Border.all(color: activeColor, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: activeColor.withAlpha(90),
                        blurRadius: isConnected ? 36 : 14,
                        spreadRadius: isConnected ? 6 : 1,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.power_settings_new_rounded,
                        size: 72,
                        color: isConnected
                            ? const Color(0xFF00E5A0)
                            : Colors.white,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isConnected ? 'STOP' : (isConnecting ? 'CANCEL' : 'START'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                statusText,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: isConnected ? const Color(0xFF00E5A0) : Colors.white70,
                ),
              ),
              if (isConnected && _v2rayStatus != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Time: ${_v2rayStatus!.duration}   •   ↓ ${_formatSpeed(_v2rayStatus!.downloadSpeed)}   ↑ ${_formatSpeed(_v2rayStatus!.uploadSpeed)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
              const Spacer(),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Auto Config Mode',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isConnected ? _activeRemark : 'Zero-config engine ready',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                    Icon(
                      Icons.bolt_rounded,
                      color: isConnected
                          ? const Color(0xFF00E5A0)
                          : Colors.white54,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
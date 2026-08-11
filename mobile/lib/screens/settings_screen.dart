import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../design/design.dart';
import '../models/division.dart';
import '../services/settings_service.dart';
import '../services/cache_service.dart';
import '../services/fcm_service.dart';
import '../services/favorites_service.dart';
import '../services/divisions_service.dart';
import 'division_projects_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService.instance;
  String _cacheSize = '계산 중...';
  String _appVersion = '';
  List<Division> _pinned = [];
  bool _loadingPinned = true;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
    _loadVersion();
    _loadPinned();
  }

  Future<void> _loadCacheSize() async {
    final bytes = await CacheService.totalCacheBytes();
    if (mounted) setState(() => _cacheSize = CacheService.format(bytes));
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _appVersion = '${info.version} (${info.buildNumber})');
    }
  }

  Future<void> _loadPinned() async {
    try {
      final divisions = await DivisionsService.fetchAll();
      final favFlags = await Future.wait(
          divisions.map((d) async => (await FavoritesService.isFavorite(d.id)) ? d.id : null));
      final favIds = favFlags.whereType<String>().toSet();
      if (mounted) {
        setState(() {
          _pinned = divisions.where((d) => favIds.contains(d.id)).toList();
          _loadingPinned = false;
        });
      }
    } catch (e) {
      debugPrint('pinned load error: $e');
      if (mounted) setState(() => _loadingPinned = false);
    }
  }

  Future<void> _clearCache() async {
    final freed = await CacheService.clear();
    await _loadCacheSize();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('캐시 ${CacheService.format(freed)} 정리됨')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          _sectionTitle('글꼴 크기'),
          ValueListenableBuilder<double>(
            valueListenable: _settings.fontScale,
            builder: (_, scale, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<double>(
                segments: const [
                  ButtonSegment(value: 0.9, label: Text('작게')),
                  ButtonSegment(value: 1.0, label: Text('보통')),
                  ButtonSegment(value: 1.15, label: Text('크게')),
                ],
                selected: {scale},
                onSelectionChanged: (s) => _settings.setFontScale(s.first),
              ),
            ),
          ),
          const Divider(height: 32),

          _sectionTitle('알림'),
          ValueListenableBuilder<bool>(
            valueListenable: _settings.notificationsEnabled,
            builder: (_, enabled, _) => SwitchListTile(
              title: const Text('전체 알림'),
              value: enabled,
              activeThumbColor: AppColors.headerNavy,
              onChanged: (v) async {
                await _settings.setNotificationsEnabled(v);
                await FcmService.setUpdateTopic(
                    v && _settings.updateNotifEnabled.value);
              },
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _settings.updateNotifEnabled,
            builder: (_, enabled, _) => SwitchListTile(
              title: const Text('업데이트 알림'),
              subtitle: const Text('새 버전 출시 시 알림'),
              value: enabled,
              activeThumbColor: AppColors.headerNavy,
              onChanged: _settings.notificationsEnabled.value
                  ? (v) async {
                      await _settings.setUpdateNotifEnabled(v);
                      await FcmService.setUpdateTopic(v);
                    }
                  : null,
            ),
          ),
          const Divider(height: 32),

          _sectionTitle('고정 사업부 관리'),
          if (_loadingPinned)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_pinned.isEmpty)
            const ListTile(title: Text('고정된 사업부가 없습니다'))
          else
            ..._pinned.map((d) => ListTile(
                  leading: const Icon(Icons.push_pin),
                  title: Text(d.label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => DivisionProjectsScreen(division: d)),
                  ),
                )),
          const Divider(height: 32),

          _sectionTitle('데이터'),
          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('캐시 사용량'),
            subtitle: Text(_cacheSize),
            trailing: TextButton(
              onPressed: _clearCache,
              child: const Text('정리'),
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: _settings.autoRefreshMinutes,
            builder: (_, min, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ListTile(
                  leading: Icon(Icons.refresh),
                  title: Text('자동 새로고침 (앱 실행 중)'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final e in [
                        ('끔', 0), ('1분', 1), ('3분', 3), ('5분', 5), ('10분', 10)
                      ])
                        ChoiceChip(
                          label: Text(e.$1),
                          selected: min == e.$2,
                          onSelected: (_) =>
                              _settings.setAutoRefreshMinutes(e.$2),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const Divider(height: 32),

          _sectionTitle('앱 정보'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('버전'),
            subtitle: Text(_appVersion),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.headerNavy,
          ),
        ),
      );
}

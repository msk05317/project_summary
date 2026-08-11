import 'package:flutter/material.dart';
import '../design/design.dart';
import '../config/app_settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.reportPageBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.headerNavy,
        elevation: 0,
        title: const Text('설정', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===== 표시 =====
          _sectionHeader('표시'),
          _settingCard([
            _fontScaleTile(),
          ]),
          
          const SizedBox(height: 24),
          
          // ===== 알림 =====
          _sectionHeader('알림'),
          _settingCard([
            _switchTile('즉시 확인 알림', '지연/위험 발생 시 푸시', true),
            _switchTile('마감 임박 알림', 'D-3 / D-1 두 번 알림', true),
            _switchTile('새 보고 알림', '주간/일일 보고 등록 시', true),
          ]),
          
          const SizedBox(height: 24),
          
          // ===== 핀 관리 =====
          _sectionHeader('핀 관리'),
          _settingCard([
            _navTile('고정한 사업부', '1개 · 반도체사업부'),
            _navTile('고정한 프로젝트', '3개 · 파워박스 · 프레임 · 메이저모듈'),
          ]),
          
          const SizedBox(height: 24),
          
          // ===== 데이터 =====
          _sectionHeader('데이터'),
          _settingCard([
            _navTile('자동 새로고침', '5분'),
            _navTile('캐시 정리', '현재 12.4MB'),
          ]),
          
          const SizedBox(height: 24),
          
          // ===== 정보 =====
          _sectionHeader('정보'),
          _settingCard([
            _navTile('앱 버전', 'v2.1.4'),
            _navTile('이용약관 · 개인정보', ''),
            _navTile('도움말 · 문의', ''),
          ]),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: AppText.caption.copyWith(
          color: AppColors.reportBody,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _settingCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.dividerSoft),
      ),
      child: Column(children: children),
    );
  }

  Widget _fontScaleTile() {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final scale = AppSettings.instance.fontScale;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.format_size, color: AppColors.reportBody, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('글꼴 크기', style: AppText.bodyStrong),
                  ),
                  Text(
                    _scaleLabel(scale),
                    style: AppText.caption.copyWith(color: AppColors.reportBody),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Slider(
                value: scale,
                min: 0.8,
                max: 1.4,
                divisions: 6,
                onChanged: (v) {
                  AppSettings.instance.setFontScale(v);
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('작게', style: AppText.caption),
                  Text('보통', style: AppText.caption),
                  Text('크게', style: AppText.caption),
                  Text('매우 크게', style: AppText.caption),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _scaleLabel(double scale) {
    if (scale <= 0.9) return '작게';
    if (scale <= 1.1) return '보통';
    if (scale <= 1.3) return '크게';
    return '매우 크게';
  }

  Widget _switchTile(String title, String subtitle, bool value) {
    return SwitchListTile(
      title: Text(title, style: AppText.bodyStrong),
      subtitle: subtitle.isNotEmpty ? Text(subtitle, style: AppText.caption) : null,
      value: value,
      onChanged: (v) {},
      activeThumbColor: AppColors.headerNavy,
    );
  }

  Widget _navTile(String title, String subtitle) {
    return ListTile(
      title: Text(title, style: AppText.bodyStrong),
      subtitle: subtitle.isNotEmpty ? Text(subtitle, style: AppText.caption) : null,
      trailing: const Icon(Icons.chevron_right, color: Color(0xFF7C8594)),
      onTap: () {},
    );
  }
}

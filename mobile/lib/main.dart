// 앱 진입점.
// AppSettings 를 먼저 로드해서 폰트 스케일/마지막 사업부 키 등을 준비한 뒤,
// 첫 화면으로 HomeScreen 을 띄웁니다.
//
// 이전 버전에서는 lastDivisionKey 가 있으면 곧장 DashboardScreen 으로 이동했지만,
// 이번 단계부터는 항상 HomeScreen 에서 시작해 사업부 → 프로젝트 → 보고 상세 흐름을 사용합니다.

import 'package:flutter/material.dart';

import 'config/app_settings.dart';
import 'services/app_updater.dart';
import 'screens/home_screen.dart';
import 'services/fcm_service.dart';
import 'services/settings_service.dart';
import 'services/background_service.dart';
import 'dart:async';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 첫 프레임을 막아도 되는 건 설정 두 개뿐이다. 둘 다 SharedPreferences
  // 라서 같이 기다린다 (폰트 배율을 모르고 그리면 글자 크기가 한 번 튄다).
  await Future.wait([
    SettingsService.instance.load(),
    AppSettings.instance.load(),
  ]);
  runApp(const BriefingApp());

  // 나머지는 화면이 뜬 뒤에 한다.
  //
  // WorkManager 등록은 안드로이드 작업 DB 를 건드려서 콜드 스타트에
  // 수백 ms 가 걸린다. 30분마다 도는 백그라운드 새로고침이라 첫 화면과는
  // 아무 상관이 없는데, 그동안 앱이 흰 화면으로 서 있었다.
  unawaited(Future(() async {
    try {
      await BackgroundService.instance.init();
      await BackgroundService.instance.registerPeriodic(
          SettingsService.instance.backgroundRefreshMinutes.value);
    } catch (_) {
      // 백그라운드 새로고침이 안 걸려도 앱은 돌아가야 한다
    }
  }));
  FcmService.initialize();
  // 앱이 꺼져 있던 사이에 OS 가 받던 업데이트에 다시 붙는다.
  // 이걸 안 하면 다시 켰을 때 '받는 중' 을 모르고 처음부터 또 받는다.
  unawaited(AppUpdater.instance.init());
}

class BriefingApp extends StatefulWidget {
  const BriefingApp({super.key});

  @override
  State<BriefingApp> createState() => _BriefingAppState();
}

class _BriefingAppState extends State<BriefingApp> {
  // 업데이트 안내 다이얼로그를 띄울 때 사용할 글로벌 네비 키.
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // 첫 프레임이 그려진 직후, 잠깐 뒤에 업데이트 안내를 시도합니다.
    FcmService.onUpdateNotificationTap = (data) async {
      await Future.delayed(const Duration(milliseconds: 500));
      final ctx = _navKey.currentContext;
      if (ctx != null && ctx.mounted) {
        await AppUpdater.instance.startDirectUpdateDownload();
      }
    };

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(seconds: 1));
      final ctx = _navKey.currentContext;
      if (ctx != null && ctx.mounted) {
        if (FcmService.pendingOpenData != null) {
          FcmService.pendingOpenData = null;
        }
        await AppUpdater.instance.checkAndPromptUpdate(ctx);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // AppSettings 가 ChangeNotifier 이므로
    // 폰트 스케일 등이 바뀌면 자동으로 다시 빌드됩니다.
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: _navKey,
          title: '사업부 보고',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
            ),
          ),
          builder: (context, child) {
            // 사용자 폰트 배율을 전체 트리에 강제 적용합니다.
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(AppSettings.instance.fontScale),
              ),
              child: SafeArea(
                top: false,
                bottom: true,
                // 업데이트를 받는 동안은 어느 화면에 있든 진행률이 보인다.
                // 팝업을 닫고 딴 데로 갔을 때 받고 있는지 알 길이 없었다.
                child: Stack(children: [child!, const _UpdateBadge()]),
              ),
            );
          },
          // 항상 HomeScreen 으로 시작.
          home: const HomeScreen(),
        );
      },
    );
  }
}

/// 화면 오른쪽 아래에 뜨는 작은 진행률 배지.
///
/// "다운로드 누르면 뭐 앱을 나가도 끄지 않는 이상 알아서 다운 받게끔"
/// — 받는 일은 AppUpdater 가 들고 있어서 화면을 옮겨도 계속된다. 다만
/// 보이는 게 없으면 받고 있는지 알 수가 없어서 배지를 띄운다.
class _UpdateBadge extends StatelessWidget {
  const _UpdateBadge();

  @override
  Widget build(BuildContext context) {
    final up = AppUpdater.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: up.downloading,
      builder: (context, busy, _) {
        return ValueListenableBuilder<String?>(
          valueListenable: up.downloadError,
          builder: (context, err, _) {
            if (!busy && err == null) return const SizedBox.shrink();
            return Positioned(
              right: 12,
              bottom: 92,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: busy ? null : up.retryDownload,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                    decoration: BoxDecoration(
                      color: err != null
                          ? const Color(0xFFB91C1C)
                          : const Color(0xFF0E2841),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 8,
                            offset: Offset(0, 2)),
                      ],
                    ),
                    child: err != null
                        ? const Text('업데이트 실패 · 다시 시도',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700))
                        : ValueListenableBuilder<double>(
                            valueListenable: up.progress,
                            builder: (context, p, _) => Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    value: p > 0 ? p : null,
                                    strokeWidth: 2,
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                            Colors.white),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                    '업데이트 받는 중 ${(p * 100).toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

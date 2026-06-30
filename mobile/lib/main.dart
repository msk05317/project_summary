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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 사용자 설정(폰트 스케일 등)을 디스크에서 로드.
  await AppSettings.instance.load();
  runApp(const BriefingApp());
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(seconds: 1));
      final ctx = _navKey.currentContext;
      if (ctx != null && ctx.mounted) {
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
              child: child!,
            );
          },
          // 항상 HomeScreen 으로 시작.
          home: const HomeScreen(),
        );
      },
    );
  }
}

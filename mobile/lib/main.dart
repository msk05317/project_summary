import 'package:flutter/material.dart';
import 'config/app_settings.dart';
import 'services/app_updater.dart';
import 'screens/dashboard_screen.dart';
import 'screens/division_select_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.load();
  runApp(const BriefingApp());
}

class BriefingApp extends StatefulWidget {
  const BriefingApp({super.key});

  @override
  State<BriefingApp> createState() => _BriefingAppState();
}

class _BriefingAppState extends State<BriefingApp> {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
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
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(AppSettings.instance.fontScale),
              ),
              child: child!,
            );
          },
          home: _resolveHome(),
        );
      },
    );
  }

  Widget _resolveHome() {
    final key = AppSettings.instance.lastDivisionKey;
    if (key == null || key.isEmpty) {
      return const DivisionSelectScreen();
    }
    final found = kFallbackDivisions.where((d) => d.id == key).toList();
    if (found.isEmpty) {
      return const DivisionSelectScreen();
    }
    return DashboardScreen(
      divisionKey: found.first.id,
      divisionLabel: found.first.label,
    );
  }
}

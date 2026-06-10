import 'package:flutter/material.dart';
import 'config/app_settings.dart';
import 'screens/dashboard_screen.dart';
import 'screens/division_select_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.load();
  runApp(const BriefingApp());
}

class BriefingApp extends StatelessWidget {
  const BriefingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        return MaterialApp(
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
    final found = kDivisions.where((d) => d.id == key).toList();
    if (found.isEmpty) {
      return const DivisionSelectScreen();
    }
    return DashboardScreen(
      divisionKey: found.first.id,
      divisionLabel: found.first.label,
    );
  }
}

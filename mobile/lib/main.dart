import 'package:flutter/material.dart';
import 'screens/dashboard_screen.dart';

void main() => runApp(const BriefingApp());

class BriefingApp extends StatelessWidget {
  const BriefingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '사업부 보고',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

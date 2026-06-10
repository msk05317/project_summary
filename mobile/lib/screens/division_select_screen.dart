import 'package:flutter/material.dart';
import '../config/app_settings.dart';
import 'dashboard_screen.dart';

class Division {
  final String id;
  final String label;
  const Division(this.id, this.label);
}

// TODO: 백엔드 /divisions API 연동 (현재는 하드코딩)
const List<Division> kDivisions = [
  Division('semiconductor', '반도체사업부'),
  Division('pcb', 'PCB사업부'),
  Division('network', '네트워크사업부'),
  Division('system', '시스템사업부'),
];

class DivisionSelectScreen extends StatelessWidget {
  const DivisionSelectScreen({super.key});

  Future<void> _select(BuildContext context, Division d) async {
    await AppSettings.instance.setLastDivisionKey(d.id);
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DashboardScreen(
          divisionKey: d.id,
          divisionLabel: d.label,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const Text(
                '사업부 진행현황',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E3A5F),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '확인할 사업부를 선택하세요',
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.separated(
                  itemCount: kDivisions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final d = kDivisions[i];
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      elevation: 1,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _select(context, d),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 22),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  d.label,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E3A5F),
                                  ),
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: Colors.black38),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

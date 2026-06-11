import 'package:flutter/material.dart';
import '../config/app_settings.dart';
import '../services/api_client.dart';
import 'dashboard_screen.dart';

class Division {
  final String id;
  final String label;
  const Division(this.id, this.label);
}

// 백엔드 응답 실패 시 사용할 fallback (오프라인 안전)
const List<Division> kFallbackDivisions = [
  Division('semiconductor', '반도체사업부'),
  Division('pcb', 'PCB사업부'),
  Division('network', '네트워크사업부'),
  Division('system', '시스템사업부'),
  Division('ess', 'ESS사업부'),
  Division('heavy', '중공업사업부'),
  Division('automation', '자동화사업부'),
  Division('automotive', '자동차사업부'),
];

class DivisionSelectScreen extends StatefulWidget {
  const DivisionSelectScreen({super.key});

  @override
  State<DivisionSelectScreen> createState() => _DivisionSelectScreenState();
}

class _DivisionSelectScreenState extends State<DivisionSelectScreen> {
  final ApiClient _api = ApiClient();
  List<Division> _divisions = kFallbackDivisions;
  Map<String, String> _latestUpdates = {};
  final Map<String, String?> _lastSeen = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);

    // 1) 사업부 목록 (실패 시 fallback)
    final raw = await _api.fetchDivisions();
    final List<Division> divs = raw.isNotEmpty
        ? raw.map((m) => Division(m['id']!, m['label']!)).toList()
        : List.of(kFallbackDivisions);

    // 2) 사업부별 최신 업데이트 시각
    final updates = await _api.fetchDivisionUpdates();

    // 3) 로컬 last_seen
    final Map<String, String?> seen = {};
    for (final d in divs) {
      seen[d.id] = await AppSettings.instance.getLastSeenAt(d.id);
    }

    if (!mounted) return;
    setState(() {
      _divisions = divs;
      _latestUpdates = updates;
      _lastSeen
        ..clear()
        ..addAll(seen);
      _loading = false;
    });
  }

  bool _hasNewUpdate(String divisionId) {
    final latest = _latestUpdates[divisionId] ?? '';
    if (latest.isEmpty) return false;
    final seen = _lastSeen[divisionId] ?? '';
    if (seen.isEmpty) return true;
    return latest.compareTo(seen) > 0;
  }

  Future<void> _select(BuildContext context, Division d) async {
    await AppSettings.instance.setLastDivisionKey(d.id);
    await AppSettings.instance.markDivisionSeen(d.id);
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
        child: RefreshIndicator(
          onRefresh: _loadAll,
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
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _divisions.length,
                          separatorBuilder: (_, _b) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, i) {
                            final d = _divisions[i];
                            final hasNew = _hasNewUpdate(d.id);
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
                                        child: Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                d.label,
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF1E3A5F),
                                                ),
                                              ),
                                            ),
                                            if (hasNew) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                width: 10,
                                                height: 10,
                                                decoration: const BoxDecoration(
                                                  color: Color(0xFFEF4444),
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                            ],
                                          ],
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
      ),
    );
  }
}

// 지연·임박 전체 목록.
//
// 홈의 '지금 봐야 할 것' 은 프로젝트로 묶어서 다섯 줄만 보여준다.
// 여기서는 모델 한 건씩, 오래 밀린 것부터 전부 늘어놓는다.
// 홈·프로젝트 화면과 같은 /home/alerts 를 본다 — 세 화면이 같은 값을 쓴다.
import 'package:flutter/material.dart';

import '../design/typography.dart';
import '../services/home_alerts_service.dart';
import 'project_overview_screen.dart';

class AlertListScreen extends StatefulWidget {
  const AlertListScreen({super.key});

  @override
  State<AlertListScreen> createState() => _AlertListScreenState();
}

class _AlertListScreenState extends State<AlertListScreen> {
  late Future<HomeAlerts> _future;
  String _filter = ''; // '' = 전체 · '지연' · '임박'

  @override
  void initState() {
    super.initState();
    _future = HomeAlertsService.fetch(limit: 60);
  }

  Future<void> _refresh() async {
    setState(() => _future = HomeAlertsService.fetch(limit: 60));
    await _future;
  }

  Widget _chip(String label, int n, bool on, VoidCallback tap, Color tint) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: on ? tint : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: on ? tint : const Color(0xFFE5E7EB)),
          ),
          child: Text('$label $n',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: on ? Colors.white : const Color(0xFF4B5563),
              )),
        ),
      ),
    );
  }

  Widget _card(AlertModel m) {
    final late = m.kind == '지연';
    final tint = late ? const Color(0xFFDC2626) : const Color(0xFFE97132);
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProjectOverviewScreen(
          projectKey: m.projectKey,
          projectName: m.project,
        ),
      )),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(children: [
          Container(
            width: 4, height: 44,
            decoration: BoxDecoration(
                color: tint, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(m.project,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        color: Color(0xFF6B7280))),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: late ? const Color(0xFFFEE2E2) : const Color(0xFFFFEDD5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(m.kind,
                      style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w800, color: tint)),
                ),
              ]),
              const SizedBox(height: 3),
              Text(m.model,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyStrong.copyWith(fontSize: 14)),
              const SizedBox(height: 2),
              Text(
                  [
                    if (m.stage.isNotEmpty) m.stage,
                    if (m.expected.isNotEmpty) '완료예정 ${m.expected}',
                    if (m.days != null && m.days! > 0) '${m.days}일 경과',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7280))),
              if (m.note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(m.note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF9CA3AF))),
                ),
            ]),
          ),
          const Icon(Icons.chevron_right, color: Color(0xFFCBD5E1)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text('지연 · 마감임박',
            style: AppText.bodyStrong.copyWith(fontSize: 17)),
        iconTheme: const IconThemeData(color: Color(0xFF111827)),
      ),
      body: FutureBuilder<HomeAlerts>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          final a = snap.data ?? HomeAlerts.empty;
          if (!a.loaded) {
            return const Center(
                child: Text('현황을 불러오지 못했습니다',
                    style: TextStyle(color: Color(0xFFDC2626))));
          }
          final list = a.alerts
              .where((m) => _filter.isEmpty || m.kind == _filter)
              .toList();
          return Column(children: [
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _chip('전체', a.alertsTotal, _filter.isEmpty,
                      () => setState(() => _filter = ''), const Color(0xFF0E2841)),
                  _chip('지연', a.delayed, _filter == '지연',
                      () => setState(() => _filter = '지연'),
                      const Color(0xFFDC2626)),
                  _chip('임박', a.soon, _filter == '임박',
                      () => setState(() => _filter = '임박'),
                      const Color(0xFFE97132)),
                ]),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: list.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 80),
                        Center(
                            child: Text('해당하는 항목이 없습니다',
                                style: TextStyle(color: Color(0xFF9CA3AF)))),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: list.length,
                        itemBuilder: (_, i) => _card(list[i]),
                      ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

// 문제(지연·이슈)·임박·보류·PO 대기 전체 목록.
//
// 홈의 '지금 봐야 할 것' 은 프로젝트로 묶어서 다섯 줄만 보여준다.
// 여기서는 모델 한 건씩, 오래 밀린 것부터 전부 늘어놓는다.
// 홈·프로젝트 화면과 같은 /home/alerts 를 본다 — 세 화면이 같은 값을 쓴다.
import 'package:flutter/material.dart';

import '../design/typography.dart';
import '../services/home_alerts_service.dart';
import '../utils/status_words.dart';
import 'project_overview_screen.dart';

class AlertListScreen extends StatefulWidget {
  /// '문제' = 지연+이슈 (홈에서 들어오는 기본) · '' = 전부
  /// · '지연' · '이슈' · '임박' · '정상' · 'PO 대기'
  /// (화면에 보이는 말은 utils/status_words.dart 에서 정한다)
  final String initialFilter;

  const AlertListScreen({super.key, this.initialFilter = ''});

  @override
  State<AlertListScreen> createState() => _AlertListScreenState();
}

class _AlertListScreenState extends State<AlertListScreen> {
  late Future<HomeAlerts> _future;
  late String _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
    _future = HomeAlertsService.fetch();
  }

  /// 칩 하나가 보여줄 목록. 보류·PO 대기는 지연 목록과 별개다.
  List<AlertModel> _listFor(HomeAlerts a) {
    switch (_filter) {
      case '문제':
        return a.blockers;
      case '지연':
        return a.alerts.where((m) => m.kind == '지연').toList();
      case '이슈':
        return a.alerts.where((m) => m.kind == '이슈').toList();
      case '임박':
        return a.alerts.where((m) => m.kind == '임박').toList();
      case '보류':
        return a.holds;
      case '정상':
        return a.normals;
      case 'PO 대기':
        return a.poWaits;
      default:
        return a.alerts;
    }
  }

  Future<void> _refresh() async {
    setState(() => _future = HomeAlertsService.fetch());
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

  static Color _tintOf(String kind) {
    switch (kind) {
      case '지연':
      case '이슈':
        return const Color(0xFFDC2626);
      case '임박':
        return const Color(0xFFE97132);
      case '정상':
        return const Color(0xFF196B24);
      case 'PO 대기':
        return const Color(0xFFB45309);
      default:
        return const Color(0xFF6B7280); // 보류 · 드롭예정
    }
  }

  static Color _softOf(String kind) {
    switch (kind) {
      case '지연':
      case '이슈':
        return const Color(0xFFFEE2E2);
      case '임박':
        return const Color(0xFFFFEDD5);
      case '정상':
        return const Color(0xFFD1FAE5);
      case 'PO 대기':
        return const Color(0xFFFEF3C7);
      default:
        return const Color(0xFFF3F4F6);
    }
  }

  Widget _card(AlertModel m) {
    final tint = _tintOf(m.kind);
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
                    color: _softOf(m.kind),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(StatusWords.of(m.kind),
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
              // 이슈는 적어 둔 내용이 곧 이유다. 공정·예정일보다 먼저 보여준다.
              if (m.issue.isNotEmpty)
                Text(m.issue,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, height: 1.35, color: Color(0xFF374151)))
              else
                Text(
                    [
                      if (m.stage.isNotEmpty) m.stage,
                      if (m.expected.isNotEmpty) '완료예정 ${m.expected}',
                      if (m.days != null && m.days! > 0) '${m.days}일 경과',
                    ].join(' · '),
                    style:
                        const TextStyle(fontSize: 11.5, color: Color(0xFF6B7280))),
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
        title: Text(
            _filter.isEmpty ? '전체 현황' : StatusWords.of(_filter),
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
          final list = _listFor(a);
          return Column(children: [
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _chip('문제', a.blocked, _filter == '문제',
                      () => setState(() => _filter = '문제'),
                      const Color(0xFFDC2626)),
                  // 칩 글자는 사람이 읽는 말, 걸러내는 값은 서버가 쓰는 말
                  _chip(StatusWords.delayed, a.delayed, _filter == '지연',
                      () => setState(() => _filter = '지연'),
                      const Color(0xFFDC2626)),
                  _chip(StatusWords.issue, a.issue, _filter == '이슈',
                      () => setState(() => _filter = '이슈'),
                      const Color(0xFFDC2626)),
                  _chip(StatusWords.soon, a.soon, _filter == '임박',
                      () => setState(() => _filter = '임박'),
                      const Color(0xFFE97132)),
                  _chip(StatusWords.normal, a.normal, _filter == '정상',
                      () => setState(() => _filter = '정상'),
                      const Color(0xFF196B24)),
                  _chip('PO 대기', a.poWait, _filter == 'PO 대기',
                      () => setState(() => _filter = 'PO 대기'),
                      const Color(0xFFB45309)),
                  _chip('전체', a.alertsTotal, _filter.isEmpty,
                      () => setState(() => _filter = ''),
                      const Color(0xFF0E2841)),
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

// 매출 상세 화면.
//
// 홈의 '이번 달 매출' 카드를 누르면 들어온다.
// 카드에는 총액만 두고, '어디서 나온 매출인지'는 전부 여기서 본다.
//  - 월 선택 (최근 6개월)
//  - 계획 / 실적 / 달성률 / 부족·초과 금액
//  - 출하 수량 계획 → 실적
//  - 프로젝트별 매출 (실적순 · 계획순 정렬)
import 'package:flutter/material.dart';

import '../design/design.dart';
import '../services/overview_service.dart';
import '../utils/format.dart';
import 'project_overview_screen.dart';

class RevenueDetailScreen extends StatefulWidget {
  /// 처음 보여줄 월 ('2026-09'). 비우면 이번 달.
  final String? initialMonth;

  const RevenueDetailScreen({super.key, this.initialMonth});

  @override
  State<RevenueDetailScreen> createState() => _RevenueDetailScreenState();
}

enum _Sort { actual, plan }

class _RevenueDetailScreenState extends State<RevenueDetailScreen> {
  late String _month;
  late Future<OverviewSummary> _future;
  _Sort _sort = _Sort.actual;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final cur = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    _month = (widget.initialMonth != null && widget.initialMonth!.isNotEmpty)
        ? widget.initialMonth!
        : cur;
    _future = OverviewService.fetch(month: _month);
  }

  void _load(String month) {
    setState(() {
      _month = month;
      _future = OverviewService.fetch(month: month);
    });
  }

  /// 매출 데이터가 시작되는 달. 이 앞은 전부 0원이라 보여줄 이유가 없다.
  static const String _startMonth = '2026-08';

  /// 데이터 시작 달 ~ 다음 달까지. (최대 12개)
  List<String> get _months {
    final now = DateTime.now();
    final p = _startMonth.split('-');
    var d = DateTime(int.parse(p[0]), int.parse(p[1]), 1);
    final end = DateTime(now.year, now.month + 1, 1);
    var out = <String>[];
    while (!d.isAfter(end)) {
      out.add('${d.year}-${d.month.toString().padLeft(2, '0')}');
      d = DateTime(d.year, d.month + 1, 1);
    }
    if (out.length > 12) out = out.sublist(out.length - 12);
    if (!out.contains(_month)) out.insert(0, _month);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.reportPageBg,
      appBar: AppBar(
        title: const Text('매출 상세'),
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: () => _load(_month),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _monthBar(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _load(_month),
                child: FutureBuilder<OverviewSummary>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final s = snap.data ?? OverviewSummary.empty;
                    if (!s.loaded) {
                      return _notice(
                        Icons.cloud_off_outlined,
                        '매출 현황을 불러오지 못했습니다.\n네트워크 상태를 확인하고 다시 시도해 주세요.',
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      children: [
                        _totalCard(s),
                        const SizedBox(height: 12),
                        _projectSection(s),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // 월 선택
  // ------------------------------------------------------------------
  Widget _monthBar() {
    final months = _months;
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: months.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final m = months[i];
            final on = m == _month;
            return InkWell(
              onTap: () => _load(m),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: on ? AppColors.headerNavy : AppColors.reportPageBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: on ? AppColors.headerNavy : AppColors.borderDefault,
                  ),
                ),
                child: Text(
                  Fmt.monthShort(m),
                  style: AppText.bodyStrong.copyWith(
                    color: on ? Colors.white : AppColors.reportBody,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // 합계 카드
  // ------------------------------------------------------------------
  Widget _totalCard(OverviewSummary s) {
    final rate = s.achievement;
    final ratio = rate == null ? 0.0 : (rate / 100).clamp(0.0, 1.0);
    final ahead = rate != null && rate >= 100;
    final color = rate == null
        ? AppColors.statusGray
        : (rate >= 100
            ? AppColors.summaryNormal
            : (rate >= 80
                ? AppColors.summaryInProgress
                : AppColors.summaryCaution));

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${Fmt.monthShort(s.month)} 합계', style: AppText.h2),
              const SizedBox(width: 6),
              Text('실적 / 계획',
                  style: AppText.caption.copyWith(color: AppColors.textMute)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                Fmt.moneyShort(s.revenue),
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMain,
                  height: 1.1,
                ),
              ),
              const SizedBox(width: 8),
              Text('/ ${Fmt.moneyShort(s.planRevenue)}',
                  style: AppText.body.copyWith(color: AppColors.textMute)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  rate == null ? '-' : '달성 $rate%',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('실적 ${Fmt.money(s.revenue)} · 계획 ${Fmt.money(s.planRevenue)}',
              style: AppText.caption.copyWith(color: AppColors.textMute)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: AppColors.statusGraySoft,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _stat('출하 (계획 → 실적)',
                    '${Fmt.qty(s.qtyPlan)} → ${Fmt.qty(s.qtyActual)}대'),
              ),
              Container(width: 1, height: 28, color: AppColors.borderSoft),
              Expanded(
                child: _stat(
                  ahead ? '계획 대비 초과' : '계획 대비 부족',
                  Fmt.moneyShort((s.revenue - s.planRevenue).abs()),
                  color: ahead
                      ? AppColors.summaryNormal
                      : AppColors.summaryCaution,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 프로젝트별
  // ------------------------------------------------------------------
  Widget _projectSection(OverviewSummary s) {
    final items = s.items
        .where((e) => e.planRevenue > 0 || e.revenue > 0)
        .toList();
    if (_sort == _Sort.actual) {
      items.sort((a, b) => b.revenue.compareTo(a.revenue));
    } else {
      items.sort((a, b) => b.planRevenue.compareTo(a.planRevenue));
    }
    final noPlan = s.items.length - items.length;

    return _card(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('프로젝트별 매출', style: AppText.h2),
              const Spacer(),
              _sortChip('실적순', _Sort.actual),
              const SizedBox(width: 6),
              _sortChip('계획순', _Sort.plan),
            ],
          ),
          const SizedBox(height: 6),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                '${Fmt.monthShort(s.month)}에 등록된 매출 계획이 없습니다.',
                style: AppText.body.copyWith(color: AppColors.textMute),
              ),
            )
          else
            ...items.map((p) => _projectRow(p)),
          if (noPlan > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
              child: Text('매출 계획이 없는 프로젝트 $noPlan개는 표시하지 않았습니다.',
                  style: AppText.caption.copyWith(color: AppColors.textMute)),
            ),
        ],
      ),
    );
  }

  Widget _sortChip(String label, _Sort v) {
    final on = _sort == v;
    return InkWell(
      onTap: () => setState(() => _sort = v),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on
              ? AppColors.summaryInProgress.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: on ? AppColors.summaryInProgress : AppColors.borderDefault,
          ),
        ),
        child: Text(
          label,
          style: AppText.caption.copyWith(
            color: on ? AppColors.summaryInProgress : AppColors.reportBody,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _projectRow(OverviewProject p) {
    final r = Fmt.rate(p.revenue, p.planRevenue);
    final ratio = r == null ? 0.0 : (r / 100).clamp(0.0, 1.0);
    final color = r == null
        ? AppColors.statusGray
        : (r >= 100
            ? AppColors.summaryNormal
            : (r >= 80
                ? AppColors.summaryInProgress
                : AppColors.summaryCaution));

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProjectOverviewScreen(
              projectKey: p.key,
              projectName: p.label,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(p.label,
                      style: AppText.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                Text(Fmt.moneyShort(p.revenue), style: AppText.bodyStrong),
                Text(' / ${Fmt.moneyShort(p.planRevenue)}',
                    style:
                        AppText.caption.copyWith(color: AppColors.textMute)),
                const SizedBox(width: 6),
                SizedBox(
                  width: 44,
                  child: Text(
                    r == null ? '-' : '$r%',
                    textAlign: TextAlign.right,
                    style: AppText.caption
                        .copyWith(color: color, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 5,
                backgroundColor: AppColors.statusGraySoft,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '출하 ${Fmt.qty(p.qtyPlan)} → ${Fmt.qty(p.qtyActual)}대'
              '${p.progress == null ? '' : ' · 진행률 ${p.progress}%'}',
              style: AppText.caption.copyWith(color: AppColors.textMute),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  Widget _stat(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppText.caption.copyWith(color: AppColors.textMute),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(value,
            style: AppText.bodyStrong.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: child,
    );
  }

  Widget _notice(IconData icon, String text) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 24),
      children: [
        Icon(icon, size: 34, color: AppColors.textMute),
        const SizedBox(height: 10),
        Text(text,
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: AppColors.textMute)),
      ],
    );
  }
}

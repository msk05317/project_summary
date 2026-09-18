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
import '../services/revenue_service.dart';
import '../utils/format.dart';
import 'project_overview_screen.dart';

class RevenueDetailScreen extends StatefulWidget {
  /// 처음 보여줄 월 ('2026-09'). 비우면 이번 달.
  final String? initialMonth;

  /// 특정 사업부로 좁혀서 볼 때. 비우면 전사.
  final String? divisionId;
  final String? divisionLabel;

  const RevenueDetailScreen({
    super.key,
    this.initialMonth,
    this.divisionId,
    this.divisionLabel,
  });

  @override
  State<RevenueDetailScreen> createState() => _RevenueDetailScreenState();
}

enum _Sort { actual, plan }

class _RevenueDetailScreenState extends State<RevenueDetailScreen> {
  late String _month;
  late Future<OverviewSummary> _future;
  // 매출은 엑셀이 원본이다. 홈 카드와 같은 값을 봐야 한다 — 전에는
  // 여기만 모델 판가로 계산해서 홈과 숫자가 달랐다.
  late Future<RevenueMonth> _revFuture;
  // 사업부를 펴 놓았는지. 지금은 반도체 하나지만, 다른 사업부 파일이
  // 들어오면 줄이 늘어난다.
  // 접어 두면 화면이 통째로 빈다. 세부를 보려고 들어온 화면이다.
  bool _openDiv = true;
  _Sort _sort = _Sort.actual;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final cur = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    _month = (widget.initialMonth != null && widget.initialMonth!.isNotEmpty)
        ? widget.initialMonth!
        : cur;
    _future = OverviewService.fetch(
        month: _month, divisionId: widget.divisionId);
    _revFuture = RevenueService.fetch(month: _month);
  }

  void _load(String month) {
    setState(() {
      _month = month;
      _future = OverviewService.fetch(
          month: month, divisionId: widget.divisionId);
      _revFuture = RevenueService.fetch(month: month);
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
        title: Text(
          (widget.divisionLabel ?? '').trim().isEmpty
              ? '매출 상세'
              : '${widget.divisionLabel} 매출',
        ),
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
                child: FutureBuilder<RevenueMonth>(
                  future: _revFuture,
                  builder: (context, rev) {
                    final r = rev.data;
                    // 사업부를 좁혀 보는 경우는 예전 방식(프로젝트별)만 있다.
                    final wide = (widget.divisionId ?? '').trim().isEmpty;
                    if (wide && r != null && r.loaded && r.hasData) {
                      return _excelBody(r);
                    }
                    if (wide && rev.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return _overviewBody(rev.data);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 엑셀에서 받은 매출 — 보고서와 같은 큰 틀로.
  Widget _excelBody(RevenueMonth r) {
    // 총합 카드의 짝은 타겟. 아래 부서별은 예상 기준 그대로다 —
    // 부서별 예상은 Commodity 를 묶음으로 이어 붙여야 나오는 값이라
    // 타겟 금액 하나로는 나눌 수가 없다.
    final est = r.hasTarget;

    // 라벨은 왼쪽, 값은 오른쪽 끝. 셋으로 쪼개 놓으면 넓은 화면에서
    // 값이 죄다 왼쪽에 몰려 보인다.
    Widget kv(String k, String v) => Row(children: [
          Expanded(
            child: Text(k,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: AppColors.textMute)),
          ),
          const SizedBox(width: 10),
          Text(v, maxLines: 1, style: AppText.bodyStrong),
        ]);

    // 부서 한 줄씩 (펴 봤을 때).
    //
    // 예상을 Commodity 별로 넣은 달은 부서마다 제 달성률이 있다.
    // 금액만 넣은 달은 나눌 근거가 없어서 총합 대비 비중만 본다 —
    // 없는 달성률을 지어내지 않는다.
    final byGroup = r.hasEstimateGroups;
    Widget deptRow(RevenueGroup g) {
      final all = r.actual;
      final pc = byGroup
          ? g.rate
          : (all > 0 ? (g.actual * 100 / all).round() : null);
      final tint = g.key == 'internal'
          ? AppColors.statusGray
          : AppColors.summaryInProgress;
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(g.short,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body
                      .copyWith(fontSize: 13.5, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Text(
                byGroup && g.estimate > 0
                    ? '${Fmt.moneyShort(g.actual)} / ${Fmt.moneyShort(g.estimate)}'
                    : Fmt.moneyShort(g.actual),
                style: AppText.caption.copyWith(color: AppColors.textMute)),
            const SizedBox(width: 8),
            SizedBox(
              width: 38,
              child: Text(pc == null ? '-' : '$pc%',
                  textAlign: TextAlign.right,
                  style: AppText.bodyStrong.copyWith(fontSize: 12.5)),
            ),
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pc == null ? 0 : (pc / 100).clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: AppColors.statusGraySoft,
              valueColor: AlwaysStoppedAnimation<Color>(tint),
            ),
          ),
        ]),
      );
    }

    // 사업부 한 줄. 누르면 그 안의 부서가 펴진다 — 데이터 센터도
    // 우주항공도 구미·화성도 결국 반도체 하나 안의 이야기다.
    Widget divisionCard() {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.borderDefault),
        ),
        child: Column(children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: () => setState(() => _openDiv = !_openDiv),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 위 카드에 이미 크게 나온 숫자다. 여기서 또 크게 쌓으면
                    // 같은 말을 두 번 하면서 오른쪽만 비운다. 한 줄에 붙인다.
                    Row(children: [
                      Expanded(
                        child: Text('반도체',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.bodyStrong.copyWith(fontSize: 15.5)),
                      ),
                      const SizedBox(width: 8),
                      Text(Fmt.moneyShort(r.actual),
                          style: AppText.caption
                              .copyWith(color: AppColors.textMute)),
                      // 한동안 여기에 '100%' 가 적혀 있었다. 사업부가
                      // 하나뿐이라 비중이 100 인 것뿐인데 달성률로 읽혔다.
                      // 예상이 들어온 뒤로는 진짜 달성률을 적는다.
                      if (est) ...[
                        const SizedBox(width: 8),
                        Text(r.rate == null ? '-' : '${r.rate}%',
                            style:
                                AppText.bodyStrong.copyWith(fontSize: 13.5)),
                      ],
                      Icon(_openDiv ? Icons.expand_less : Icons.expand_more,
                          size: 20, color: AppColors.textMute),
                    ]),
                  ]),
            ),
          ),
          if (_openDiv)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Divider(height: 8, color: AppColors.borderSoft),
                const SizedBox(height: 4),
                Text(byGroup ? '부서별 실적 / 예상 · 달성' : '부서별 실적 · 비중',
                    style: AppText.caption.copyWith(color: AppColors.textHint)),
                for (final g in r.lines) deptRow(g),
              ]),
            ),
        ]),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.borderDefault),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text('${Fmt.monthShort(r.month)} 총합',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.h2),
              ),
              if (r.asOf.isNotEmpty)
                Text('${r.asOf} 까지',
                    style: AppText.caption.copyWith(color: AppColors.textHint)),
            ]),
            const SizedBox(height: 10),
            Text(est ? '실적 / 타겟' : '실적',
                style: AppText.caption.copyWith(color: AppColors.textHint)),
            const SizedBox(height: 3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(Fmt.moneyShort(r.actual),
                          maxLines: 1,
                          style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              height: 1.1)),
                      if (est) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text('/ ${Fmt.moneyShort(r.target)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body.copyWith(
                                  fontSize: 15, color: AppColors.textMute)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                    est
                        ? (r.targetRate == null ? '-' : '${r.targetRate}%')
                        : '타겟 미등록',
                    style: est
                        ? AppText.bodyStrong.copyWith(fontSize: 15)
                        : AppText.caption
                            .copyWith(color: AppColors.textHint)),
              ],
            ),
            if (est) ...[
              const SizedBox(height: 11),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: r.targetRate == null
                      ? 0
                      : (r.targetRate! / 100).clamp(0.0, 1.0),
                  minHeight: 7,
                  backgroundColor: AppColors.statusGraySoft,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.summaryInProgress),
                ),
              ),
            ],
            const Divider(height: 20, color: AppColors.borderSoft),
            kv('소계 (내부거래 제외)',
                Fmt.moneyShort(r.actual - (r.internal?.actual ?? 0))),
            const SizedBox(height: 7),
            kv('연간 누적', Fmt.moneyShort(r.ytd)),
          ]),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text('사업부',
              style: AppText.caption.copyWith(color: AppColors.textMute)),
        ),
        divisionCard(),
      ],
    );
  }

  /// 엑셀을 아직 안 올렸을 때, 또는 사업부로 좁혀 볼 때.
  /// 프로젝트별 줄은 모델 계산이지만, 맨 위 합계는 반도체면 주간보고
  /// 실적과 타겟을 쓴다 — 같은 달 매출이 화면마다 다르면 둘 다 못 믿는다.
  Widget _overviewBody(RevenueMonth? rev) {
    return FutureBuilder<OverviewSummary>(
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
                        _totalCard(s, rev),
                        const SizedBox(height: 12),
                        _projectSection(s),
                      ],
                    );
                  },
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
  Widget _totalCard(OverviewSummary s, [RevenueMonth? rev]) {
    // 반도체는 주간보고 실적과 사람이 넣은 타겟이 정본이다.
    final sheet = widget.divisionId == 'semiconductor' &&
        rev != null && rev.loaded && rev.hasData;
    final actual = sheet ? rev.actual : s.revenue;
    final plan = sheet ? rev.target : s.planRevenue;
    final pair = sheet ? (rev.hasTarget ? '실적 / 타겟' : '실적') : '실적 / 계획';
    final rate = sheet
        ? (plan > 0 ? (actual * 100 / plan).round() : null)
        : s.achievement;
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
              Text(pair,
                  style: AppText.caption.copyWith(color: AppColors.textMute)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                Fmt.moneyShort(actual),
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMain,
                  height: 1.1,
                ),
              ),
              const SizedBox(width: 8),
              Text('/ ${Fmt.moneyShort(plan)}',
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
          Text('실적 ${Fmt.money(actual)}'
              '${plan > 0 ? ' · ${sheet ? '타겟' : '계획'} ${Fmt.money(plan)}' : ''}',
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
              Container(
                width: 1,
                height: 28,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: AppColors.borderSoft,
              ),
              Expanded(
                child: _stat(
                  sheet
                      ? (ahead ? '타겟 대비 초과' : '남은 타겟')
                      : (ahead ? '계획 대비 초과' : '계획 대비 부족'),
                  Fmt.moneyShort((actual - plan).abs()),
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

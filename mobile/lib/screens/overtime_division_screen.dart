// 사업부 한 곳의 한 주 — 엑셀 사업부 시트 한 장이 그대로 이 화면이다.
//
// 보는 사람이 엑셀과 대조하니 줄 순서를 같게 둔다. 일요일만 특근이라
// 색을 나누고, 잔업 칸은 '—'(해당 없음)로 남긴다. 0 이 아니다.
import 'package:flutter/material.dart';

import '../design/design.dart';
import '../models/overtime.dart';
import '../services/overtime_service.dart';
import 'overtime_screen.dart' show kOtColor, kSpColor, ovPct, ovNum, ovDelta, ovDeltaColor;

class OvertimeDivisionScreen extends StatefulWidget {
  final String divisionKey;
  final String divisionLabel;
  final String week;

  const OvertimeDivisionScreen({
    super.key,
    required this.divisionKey,
    required this.divisionLabel,
    this.week = '',
  });

  @override
  State<OvertimeDivisionScreen> createState() =>
      _OvertimeDivisionScreenState();
}

class _OvertimeDivisionScreenState extends State<OvertimeDivisionScreen> {
  late Future<OvertimeDivision> _future;

  @override
  void initState() {
    super.initState();
    _future = OvertimeService.fetchDivision(widget.divisionKey,
        week: widget.week);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.reportPageBg,
      appBar: AppBar(
        backgroundColor: AppColors.headerNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.divisionLabel,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: FutureBuilder<OvertimeDivision>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snap.data ?? OvertimeDivision.empty;
          if (!d.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text('이 주에는 이 사업부 자료가 없습니다.',
                    style:
                        AppText.caption.copyWith(color: AppColors.reportBody)),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
            children: [
              _weekLine(d),
              const SizedBox(height: 10),
              _dayChart(d),
              const SizedBox(height: 10),
              _people(d),
              const SizedBox(height: 10),
              _splits(d),
              if (d.summary.note.isNotEmpty) ...[
                const SizedBox(height: 10),
                _note(d.summary.note, d.summary.needsCheck),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _weekLine(OvertimeDivision d) => Row(
        children: [
          Text(d.weekLabel,
              style: AppText.bodyStrong
                  .copyWith(fontSize: 14, color: AppColors.textMain)),
          const SizedBox(width: 7),
          Text(d.range,
              style: AppText.caption
                  .copyWith(fontSize: 11.5, color: AppColors.textHint)),
          const Spacer(),
          if (d.summary.needsCheck)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.statusRedSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('확인필요',
                  style: AppText.caption.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFB42318))),
            ),
        ],
      );

  // ── 요일별 막대 ─────────────────────────────────────────
  //
  // 값 라벨을 막대와 같은 칸에 넣었더니 90% 넘는 요일에서 칸 밖으로
  // 넘쳤다(OVERFLOWED BY 5px). 라벨 줄 · 막대 줄 · 요일 줄을 따로 쌓는다.
  // 주 평균은 선만 긋고 글자는 아래 범례로 뺀다 — 선 옆에 두면 제일 높은
  // 막대와 겹친다.
  static const double _plotH = 74;

  Widget _dayChart(OvertimeDivision d) {
    final days = d.byDay;
    var max = 0.0;
    for (final e in days) {
      if ((e.rate ?? 0) > max) max = e.rate ?? 0;
    }
    final top = max <= 0 ? 1.0 : (max * 1.18).clamp(0.05, 1.0);
    final otAvg = d.summary.overtime.rate.total;

    Widget spread(List<Widget> cells) => Row(
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(child: cells[i]),
            ],
          ],
        );

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('요일별 잔업·특근률',
                  style: AppText.bodyStrong
                      .copyWith(fontSize: 13, color: AppColors.textMain)),
              const Spacer(),
              Text('가용 ${ovNum(d.summary.available.total)}명',
                  style: AppText.caption
                      .copyWith(fontSize: 11, color: AppColors.textHint)),
            ],
          ),
          const SizedBox(height: 10),

          // 값 — 막대 위, 따로 한 줄
          spread([
            for (final e in days)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(e.rate == null ? '' : ovPct(e.rate),
                    maxLines: 1,
                    style: AppText.caption.copyWith(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSub)),
              ),
          ]),
          const SizedBox(height: 3),

          // 막대
          SizedBox(
            height: _plotH,
            child: Stack(
              children: [
                spread([for (final e in days) _bar(e, top)]),
                // 평균선은 막대 위에 긋는다 — 뒤에 두면 막대에 가려 안 보인다
                if (otAvg != null && otAvg > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: (otAvg / top * _plotH).clamp(0.0, _plotH - 1),
                    child: Container(height: 1.2, color: const Color(0xFF64748B)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 5),

          // 요일
          spread([
            for (final e in days)
              Text(e.label,
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(
                      fontSize: 10,
                      fontWeight:
                          e.isSunday ? FontWeight.w700 : FontWeight.w500,
                      color: e.isSunday ? kSpColor : AppColors.textHint)),
          ]),
          const SizedBox(height: 10),

          Wrap(
            spacing: 14,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _key(kOtColor, '잔업 (월~토)'),
              _key(kSpColor, '특근 (일)'),
              if (otAvg != null && otAvg > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 11, height: 1, color: const Color(0xFFB0BCCB)),
                    const SizedBox(width: 5),
                    Text('주 평균 ${ovPct(otAvg)}',
                        style: AppText.caption.copyWith(
                            fontSize: 10.5, color: AppColors.textMute)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bar(OvDay d, double top) {
    final h = d.rate == null
        ? 2.0
        : ((d.rate! / top) * _plotH).clamp(2.0, _plotH);
    final color = d.isSunday ? kSpColor : kOtColor;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: h,
        decoration: BoxDecoration(
          color: d.rate == null ? AppColors.statusGray : color,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        ),
      ),
    );
  }

  Widget _key(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                  color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 5),
          Text(label,
              style: AppText.caption
                  .copyWith(fontSize: 10.5, color: AppColors.textMute)),
        ],
      );

  // ── 인원 ────────────────────────────────────────────────
  Widget _people(OvertimeDivision d) {
    final s = d.summary;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('인원',
                  style: AppText.bodyStrong
                      .copyWith(fontSize: 13, color: AppColors.textMain)),
              const Spacer(),
              Text('주간 평균',
                  style: AppText.caption
                      .copyWith(fontSize: 11, color: AppColors.textHint)),
            ],
          ),
          const SizedBox(height: 6),
          _row('총 보유인원', ovNum(s.headcount.total)),
          _row('지원 (+) / (−)',
              '${ovNum(s.support.inbound)} / ${ovNum(s.support.outbound)}',
              dim: true),
          _row('실제 가용인원', ovNum(s.available.total), strong: true),
          _row('주간 / 야간',
              '${ovNum(s.available.day)} / ${ovNum(s.available.night)}',
              dim: true),
          _row('야간비율', ovPct(s.nightRate), dim: true),
          _row('직접 가용', ovNum(s.direct.total)),
          _row('간접 가용', ovNum(s.indirect.total), last: true),
        ],
      ),
    );
  }

  Widget _row(String label, String value,
      {bool dim = false, bool strong = false, bool last = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: strong ? const Color(0xFFF8FAFC) : null,
        border: last
            ? null
            : const Border(
                bottom: BorderSide(color: AppColors.dividerSoft, width: 1)),
      ),
      child: Row(
        children: [
          Text(label,
              style: AppText.caption.copyWith(
                  fontSize: 12,
                  color: dim ? AppColors.textMute : AppColors.textSub)),
          const Spacer(),
          Text(value,
              style: AppText.captionStrong.copyWith(
                  fontSize: 12.5,
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
                  color: dim ? AppColors.textMute : AppColors.textMain,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }

  // ── 직접 · 간접 ─────────────────────────────────────────
  Widget _splits(OvertimeDivision d) {
    final s = d.summary;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('직접 · 간접',
                  style: AppText.bodyStrong
                      .copyWith(fontSize: 13, color: AppColors.textMain)),
              const Spacer(),
              if (d.prevLabel.isNotEmpty)
                Text('${d.prevLabel} 대비',
                    style: AppText.caption
                        .copyWith(fontSize: 11, color: AppColors.textHint)),
            ],
          ),
          const SizedBox(height: 10),
          _splitRow('직접 잔업', s.overtime.rate.direct,
              d.deltaOf('overtime').direct, kOtColor),
          _splitRow('간접 잔업', s.overtime.rate.indirect,
              d.deltaOf('overtime').indirect, kOtColor.withValues(alpha: .38)),
          _splitRow('직접 특근', s.special.rate.direct,
              d.deltaOf('special').direct, kSpColor),
          _splitRow('간접 특근', s.special.rate.indirect,
              d.deltaOf('special').indirect, kSpColor.withValues(alpha: .38)),
        ],
      ),
    );
  }

  Widget _splitRow(String label, double? v, double? delta, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label,
                  style: AppText.caption
                      .copyWith(fontSize: 11.5, color: AppColors.textSub)),
              const Spacer(),
              if (delta != null && delta.abs() >= 0.0005)
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: Text('${ovDelta(delta)}%',
                      style: AppText.caption.copyWith(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: ovDeltaColor(delta))),
                ),
              Text(ovPct(v),
                  style: AppText.captionStrong.copyWith(
                      fontSize: 12,
                      color: AppColors.textMain,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: (v ?? 0).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: const Color(0xFFE6EAF0),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _note(String text, bool warn) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      decoration: BoxDecoration(
        color: warn ? const Color(0xFFFFF7ED) : const Color(0xFFFFFCF5),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
            color: warn ? const Color(0xFFFED7AA) : const Color(0xFFFDE0C0)),
      ),
      child: Text(text,
          style: AppText.caption.copyWith(
              fontSize: 11.5, height: 1.6, color: const Color(0xFF7A4A12))),
    );
  }

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.borderDefault),
        ),
        child: child,
      );
}

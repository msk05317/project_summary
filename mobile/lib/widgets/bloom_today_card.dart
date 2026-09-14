// 블룸 '오늘' 카드 — 사업부 화면 맨 위.
//
// 매일 오전에 파일이 올라온다. 그 시점에는 그날 실적이 아직 비어 있어서,
// 계획만 보여주고 '입력 대기'로 둔 다음 바로 밑에 어제 결과를 붙인다.
// 빈 화면보다 낫고, 0% 로 보여주면 거짓말이 된다.
import 'package:flutter/material.dart';

import '../design/colors.dart';
import '../models/bloom_daily.dart';

const _kCaution = Color(0xFFE97132);

String _dayLabel(String iso) {
  final p = iso.split('-');
  if (p.length != 3) return iso;
  final y = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
  if (y == null || m == null || d == null) return iso;
  const dow = ['월', '화', '수', '목', '금', '토', '일'];
  final w = dow[(DateTime(y, m, d).weekday - 1) % 7];
  return '$m/$d ($w)';
}

class BloomTodayCard extends StatelessWidget {
  final BloomDailyBoard board;
  const BloomTodayCard({super.key, required this.board});

  @override
  Widget build(BuildContext context) {
    if (!board.hasBoard) return const SizedBox.shrink();
    final t = board.today;
    if (t.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TodayBox(summary: t),
        if (board.prev != null) ...[
          const SizedBox(height: 10),
          _PrevBox(summary: board.prev!),
        ],
        if (board.itemsOn(t.date).isNotEmpty) ...[
          const SizedBox(height: 10),
          _ItemsBox(board: board, date: t.date),
        ],
        if (board.blocked.isNotEmpty) ...[
          const SizedBox(height: 10),
          _BlockedBox(board: board),
        ],
      ],
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textMute,
        ),
      );
}

class _TodayBox extends StatelessWidget {
  final BloomDaySummary summary;
  const _TodayBox({required this.summary});

  @override
  Widget build(BuildContext context) {
    final groups = summary.groupsInOrder;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label('오늘 ${_dayLabel(summary.date)} 계획'),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${summary.totalPlan}',
                  style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: AppColors.textMain)),
              const SizedBox(width: 4),
              const Text('개',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMute)),
              const Spacer(),
              if (summary.pending)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.statusGraySoft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text('실적 입력 대기',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _kCaution)),
                )
              else if (summary.pct != null)
                Text('실적 ${summary.totalActual} · ${summary.pct}%',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: (summary.pct ?? 0) >= 100
                            ? AppColors.statusGreen
                            : AppColors.statusRed)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (int i = 0; i < groups.length; i++) ...[
                if (i > 0) const SizedBox(width: 1),
                Expanded(
                  child: _GroupCell(
                    name: groups[i],
                    plan: summary.plan[groups[i]] ?? 0,
                    actual: summary.actual[groups[i]] ?? 0,
                    hasActual: summary.hasActual[groups[i]] ?? false,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _GroupCell extends StatelessWidget {
  final String name;
  final int plan;
  final int actual;
  final bool hasActual;
  const _GroupCell({
    required this.name,
    required this.plan,
    required this.actual,
    required this.hasActual,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.statusGraySoft,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        children: [
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMute)),
          const SizedBox(height: 3),
          Text(hasActual ? '$actual / $plan' : '$plan',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMain)),
        ],
      ),
    );
  }
}

class _PrevBox extends StatelessWidget {
  final BloomDaySummary summary;
  const _PrevBox({required this.summary});

  @override
  Widget build(BuildContext context) {
    final groups = summary.groupsInOrder
        .where((g) => (summary.plan[g] ?? 0) > 0)
        .toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label('${_dayLabel(summary.date)} 달성'),
          const SizedBox(height: 10),
          for (int i = 0; i < groups.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _Bar(
              name: groups[i],
              plan: summary.plan[groups[i]] ?? 0,
              actual: summary.actual[groups[i]] ?? 0,
            ),
          ],
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final String name;
  final int plan;
  final int actual;
  const _Bar({required this.name, required this.plan, required this.actual});

  @override
  Widget build(BuildContext context) {
    final pct = plan > 0 ? (actual * 100 / plan).round() : 0;
    final w = (pct / 100).clamp(0.0, 1.0);
    final color = pct >= 100 ? AppColors.statusGreen : _kCaution;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 46,
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain)),
            ),
            Expanded(
              child: Text('계획 $plan',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textMute)),
            ),
            Text('$actual',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textMain)),
            const SizedBox(width: 6),
            Text('$pct%',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: w,
            minHeight: 6,
            backgroundColor: AppColors.statusGraySoft,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _ItemsBox extends StatelessWidget {
  final BloomDailyBoard board;
  final String date;
  const _ItemsBox({required this.board, required this.date});

  @override
  Widget build(BuildContext context) {
    final rows = board.itemsOn(date);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Label('오늘 품목별'),
          const SizedBox(height: 4),
          for (final it in rows) _ItemRow(item: it, date: date),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final BloomItem item;
  final String date;
  const _ItemRow({required this.item, required this.date});

  @override
  Widget build(BuildContext context) {
    final parts = item
        .plannedOn(date)
        // 공정 이름은 엑셀에 적힌 그대로 길어서, 목록에서는 묶음 이름을 쓴다
        .map((e) => '${e.key.group} ${e.value.plan}')
        .join(' · ');
    final done = item.plannedOn(date).any((e) => e.value.actual != null);
    final actual = item
        .plannedOn(date)
        .fold<int>(0, (a, e) => a + (e.value.actual ?? 0));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(item.item,
                maxLines: 2,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(parts,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textMute, height: 1.35)),
          ),
          const SizedBox(width: 8),
          Text(done ? '$actual / ${item.planOn(date)}' : '${item.planOn(date)}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMain)),
        ],
      ),
    );
  }
}

class _BlockedBox extends StatelessWidget {
  final BloomDailyBoard board;
  const _BlockedBox({required this.board});

  @override
  Widget build(BuildContext context) {
    final rows = board.blocked;
    final notes = board.notes;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 3,
            decoration: const BoxDecoration(
              color: _kCaution,
              borderRadius: BorderRadius.horizontal(left: Radius.circular(12)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 13, 14, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Label('막혀 있는 곳'),
                  const SizedBox(height: 2),
                  const Text('조립은 끝났는데 구매품이 없어 못 나가는 수량',
                      style: TextStyle(
                          fontSize: 11.5, color: AppColors.textHint)),
                  const SizedBox(height: 8),
                  for (final it in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(it.item,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textMain)),
                          ),
                          Text('${it.waitPart}',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.statusRed)),
                        ],
                      ),
                    ),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Divider(height: 1, color: AppColors.borderSoft),
                    const SizedBox(height: 8),
                    for (final n in notes)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 44,
                              child: Text(n.eta.isEmpty ? '미정' : n.eta,
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: _kCaution)),
                            ),
                            Expanded(
                              child: Text(n.text,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.textSub,
                                      height: 1.35)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

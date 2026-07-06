import 'package:flutter/material.dart';
import '../../design/design.dart';
import '../../models/profit_kpi_card.dart';

class ProfitKpiSection extends StatefulWidget {
  final ProfitKpiCard card;
  final List<IssueLine> issues;
  const ProfitKpiSection({
    super.key,
    required this.card,
    this.issues = const [],
  });

  @override
  State<ProfitKpiSection> createState() => _ProfitKpiSectionState();
}

class _ProfitKpiSectionState extends State<ProfitKpiSection> {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6EAF0)),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.card.title, style: AppText.h2),
          const SizedBox(height: 4),
          if (widget.card.metricNote.isNotEmpty)
            Text(widget.card.metricNote,
                style: AppText.caption.copyWith(color: AppColors.textSub)),
          const SizedBox(height: 14),

          // 월별 카드
          SizedBox(
            height: 118,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.card.months.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _MonthCard(
                entry: widget.card.months[i],
                unit: widget.card.unitLabel,
              ),
            ),
          ),

          const SizedBox(height: 16),
          Text('7월 주차별', style: AppText.caption.copyWith(color: AppColors.textSub)),
          const SizedBox(height: 8),

          // 주차별 카드
          SizedBox(
            height: 108,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.card.weeks.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _WeekCard(
                entry: widget.card.weeks[i],
                unit: widget.card.unitLabel,
              ),
            ),
          ),

          const SizedBox(height: 10),
          for (final note in widget.card.footnotes)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(note,
                  style: AppText.caption.copyWith(color: AppColors.textMute)),
            ),

          // 주요 내용 (헤더 없음, pill 유지)
          if (widget.issues.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (int i = 0; i < widget.issues.length; i++) ...[
              _IssueRow(index: i + 1, issue: widget.issues[i]),
              if (i != widget.issues.length - 1) const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _MonthCard extends StatelessWidget {
  final ProfitKpiEntry entry;
  final String unit;
  const _MonthCard({required this.entry, required this.unit});

  @override
  Widget build(BuildContext context) {
    final badgeColor =
        entry.isActual ? AppColors.statusGreen : AppColors.accent;
    return Container(
      width: 156,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6EAF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(entry.label, style: AppText.bodyStrong),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  entry.isActual ? '실적' : '계획',
                  style: AppText.caption
                      .copyWith(color: Colors.white, fontSize: 10),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            '${entry.total.toStringAsFixed(2)} $unit',
            style: AppText.h1.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'EFEM ${entry.efem.toStringAsFixed(2)} · VTM ${entry.vtm.toStringAsFixed(2)}',
            style: AppText.caption.copyWith(color: AppColors.textSub),
          ),
        ],
      ),
    );
  }
}

class _WeekCard extends StatelessWidget {
  final ProfitKpiEntry entry;
  final String unit;
  const _WeekCard({required this.entry, required this.unit});

  @override
  Widget build(BuildContext context) {
    final isWait = !entry.isActual && entry.total == 0;
    return Container(
      width: 114,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6EAF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(entry.label, style: AppText.bodyStrong),
              const SizedBox(width: 4),
              if (entry.isActual)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.statusGreen,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('실적',
                      style: AppText.caption
                          .copyWith(color: Colors.white, fontSize: 9)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text('EFEM ${entry.efem.toStringAsFixed(1)}',
              style: AppText.caption.copyWith(color: AppColors.textSub)),
          Text('VTM  ${entry.vtm.toStringAsFixed(1)}',
              style: AppText.caption.copyWith(color: AppColors.textSub)),
          const Spacer(),
          Text(
            isWait ? '대기' : '${entry.total.toStringAsFixed(2)} $unit',
            style: AppText.bodyStrong.copyWith(
              color: isWait ? AppColors.textMute : const Color(0xFFB4531F),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}


class _IssueRow extends StatelessWidget {
  final int index;
  final IssueLine issue;
  const _IssueRow({required this.index, required this.issue});

  Color get _pillColor {
    switch (issue.severity) {
      case 'high':
        return const Color(0xFFD94841);
      case 'mid':
        return const Color(0xFFE0A11B);
      default:
        return const Color(0xFF6B7280);
    }
  }

  String? _ddayLabel() {
    if (!issue.showDday || issue.dueDate == null) return null;
    final today = DateTime.now();
    final t = DateTime(today.year, today.month, today.day);
    final due = DateTime.tryParse(issue.dueDate!);
    if (due == null) return null;
    final d = due.difference(t).inDays;
    final mm = due.month.toString().padLeft(2, '0');
    final dd = due.day.toString().padLeft(2, '0');
    final dateStr = '$mm/$dd';
    if (d == 0) return 'D-day · $dateStr';
    if (d > 0) return 'D-$d · $dateStr';
    return 'D+${-d} 지남 · $dateStr';
  }

  @override
  Widget build(BuildContext context) {
    final dday = _ddayLabel();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$index)',
              style: AppText.body.copyWith(
                color: AppColors.textSub,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
          Expanded(
            child: Text(
              issue.text,
              style: AppText.body.copyWith(
                color: AppColors.textMain,
                height: 1.4,
              ),
            ),
          ),
          if (dday != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _pillColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                dday,
                style: AppText.captionStrong.copyWith(
                  color: _pillColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


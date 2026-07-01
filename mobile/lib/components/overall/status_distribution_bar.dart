import 'package:flutter/material.dart';

import '../../design/design.dart';

class StatusDistributionBar extends StatelessWidget {
  final int normalCount;
  final int warningCount;
  final int delayedCount;

  const StatusDistributionBar({
    super.key,
    required this.normalCount,
    required this.warningCount,
    required this.delayedCount,
  });

  int get _total => normalCount + warningCount + delayedCount;

  @override
  Widget build(BuildContext context) {
    final total = _total == 0 ? 1 : _total;
    final normalFlex = (normalCount * 100 ~/ total).clamp(1, 100);
    final warningFlex = (warningCount * 100 ~/ total).clamp(1, 100);
    final delayedFlex = (delayedCount * 100 ~/ total).clamp(1, 100);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.reportCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '상태 분포',
                style: AppText.bodyStrong.copyWith(
                  fontSize: 13,
                  color: AppColors.headerNavy,
                ),
              ),
              const Spacer(),
              Text(
                '총 $_total건',
                style: AppText.caption.copyWith(
                  fontSize: 11,
                  color: const Color(0xFF7C8594),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 22,
              child: Row(
                children: [
                  Expanded(
                    flex: normalFlex,
                    child: _segment(
                      color: const Color(0xFF196B24),
                      label: '정상 $normalCount',
                    ),
                  ),
                  Expanded(
                    flex: warningFlex,
                    child: _segment(
                      color: const Color(0xFFE97132),
                      label: '주의 $warningCount',
                    ),
                  ),
                  Expanded(
                    flex: delayedFlex,
                    child: _segment(
                      color: const Color(0xFFFF0000),
                      label: '지연 $delayedCount',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _legendDot(const Color(0xFF196B24), '정상 $normalCount건'),
              const SizedBox(width: 12),
              _legendDot(const Color(0xFFE97132), '주의 $warningCount건'),
              const SizedBox(width: 12),
              _legendDot(const Color(0xFFFF0000), '지연 $delayedCount건'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _segment({required Color color, required String label}) {
    return Container(
      color: color,
      alignment: Alignment.center,
      child: label.isEmpty
          ? const SizedBox.shrink()
          : Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
    );
  }

  Widget _legendDot(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.headerNavy,
          ),
        ),
      ],
    );
  }
}

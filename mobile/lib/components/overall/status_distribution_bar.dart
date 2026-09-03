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
    // 0건인 상태는 조각을 아예 그리지 않는다.
    // (예전엔 clamp(1,100) 때문에 지연 0건에도 빨간 조각이 보여서
    //  '지연이 있나?' 하는 착시를 일으켰다)
    final normalFlex = normalCount == 0 ? 0 : (normalCount * 100 ~/ total).clamp(1, 100);
    final warningFlex = warningCount == 0 ? 0 : (warningCount * 100 ~/ total).clamp(1, 100);
    final delayedFlex = delayedCount == 0 ? 0 : (delayedCount * 100 ~/ total).clamp(1, 100);
    final empty = _total == 0;

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
              height: 14,
              child: empty
                  ? Container(color: AppColors.statusGraySoft)
                  : Row(
                      children: [
                        if (normalFlex > 0)
                          Expanded(
                            flex: normalFlex,
                            child: Container(color: AppColors.summaryNormal),
                          ),
                        if (warningFlex > 0)
                          Expanded(
                            flex: warningFlex,
                            child: Container(color: AppColors.summaryCaution),
                          ),
                        if (delayedFlex > 0)
                          Expanded(
                            flex: delayedFlex,
                            child: Container(color: AppColors.summaryDelayed),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 10),
          // 수치는 범례에서만 읽는다 (막대 안 라벨은 좁으면 잘려서 제거)
          Row(
            children: [
              _legendDot(AppColors.summaryNormal, '정상 $normalCount건'),
              const SizedBox(width: 12),
              _legendDot(AppColors.summaryCaution, '주의 $warningCount건'),
              const SizedBox(width: 12),
              _legendDot(AppColors.summaryDelayed, '지연 $delayedCount건'),
            ],
          ),
        ],
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

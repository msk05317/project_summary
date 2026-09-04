// 사업부 화면 프로젝트 1행 (디자인 A).
//
// 2열 카드에서 1열 행으로 바꾼 이유:
//  - 2열이면 카드 폭이 168px 남짓이라 금액을 무조건 축약해야 한다.
//    (만/억 표기로 바꾼 취지가 깎인다)
//  - 매출 기여순으로 세로 정렬해야 위에서부터 읽는 순서가 곧 중요도가 된다.
import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../../utils/format.dart';

class ProjectRevenueRow extends StatelessWidget {
  final String koreanName;
  final String status;        // '지연' | '주의' | '정상' | ''
  final int revenue;
  final int planRevenue;
  final int qtyPlan;
  final int qtyActual;
  final int modelsTotal;
  final int? progressPercent;
  final bool isFavorite;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  const ProjectRevenueRow({
    super.key,
    required this.koreanName,
    required this.status,
    required this.revenue,
    required this.planRevenue,
    required this.qtyPlan,
    required this.qtyActual,
    required this.modelsTotal,
    required this.progressPercent,
    required this.isFavorite,
    required this.isSelected,
    required this.onTap,
    required this.onToggleFavorite,
  });

  int? get _rate => planRevenue <= 0 ? null : (revenue * 100 / planRevenue).round();

  /// 점·게이지 색. 상태값이 있으면 상태를 우선하고,
  /// 상태가 없으면 계획 대비 달성률로 판단한다.
  Color get _accent {
    switch (status) {
      case '지연':
        return AppColors.statusRed;
      case '주의':
        return AppColors.summaryCaution;
    }
    final r = _rate;
    if (r == null) return AppColors.statusGray;
    if (r >= 80) return AppColors.summaryNormal;
    if (r > 0) return AppColors.summaryInProgress;
    return AppColors.summaryCaution;
  }

  @override
  Widget build(BuildContext context) {
    final rate = _rate;
    final ratio = rate == null ? 0.0 : (rate / 100).clamp(0.0, 1.0);
    final accent = _accent;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.headerNavy : const Color(0xFFE6EAF0),
            width: isSelected ? 1.4 : 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 10,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    koreanName,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.headerNavy,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onToggleFavorite,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(
                      isFavorite
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      size: 16,
                      color: isFavorite
                          ? const Color(0xFFF4B63D)
                          : const Color(0xFFC5CAD3),
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  Fmt.moneyShort(revenue),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textMain,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '/ ${Fmt.moneyShort(planRevenue)}',
                  style: AppText.caption.copyWith(
                    fontSize: 11.5,
                    color: AppColors.textHint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 5,
                backgroundColor: AppColors.dividerSoft,
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _Meta(
                  label: '출하',
                  value: '${Fmt.qty(qtyActual)} / ${Fmt.qty(qtyPlan)}대',
                ),
                const SizedBox(width: 12),
                _Meta(
                  label: '모델',
                  value: '$modelsTotal종',
                ),
                const Spacer(),
                if (progressPercent != null)
                  Text(
                    '진행 ${progressPercent!}%',
                    style: AppText.caption.copyWith(
                      fontSize: 11.5,
                      color: AppColors.textHint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final String label;
  final String value;

  const _Meta({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textMute,
        ),
        children: [
          TextSpan(text: '$label '),
          TextSpan(
            text: value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.textMain,
            ),
          ),
        ],
      ),
    );
  }
}

/// 매출 계획이 없는 프로젝트용 압축 행. 접힌 그룹 안에서만 쓴다.
class ProjectPlainRow extends StatelessWidget {
  final String koreanName;
  final int modelsTotal;
  final int? progressPercent;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  const ProjectPlainRow({
    super.key,
    required this.koreanName,
    required this.modelsTotal,
    required this.progressPercent,
    required this.isFavorite,
    required this.onTap,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE6EAF0)),
        ),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: AppColors.statusGray,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                koreanName,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.headerNavy,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onToggleFavorite,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 15,
                  color: isFavorite
                      ? const Color(0xFFF4B63D)
                      : const Color(0xFFC5CAD3),
                ),
              ),
            ),
            const Spacer(),
            Text(
              modelsTotal > 0 ? '모델 $modelsTotal종' : '모델 없음',
              style: AppText.caption.copyWith(
                fontSize: 11.5,
                color: AppColors.textHint,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (progressPercent != null) ...[
              const SizedBox(width: 10),
              Text(
                '진행 ${progressPercent!}%',
                style: AppText.caption.copyWith(
                  fontSize: 11.5,
                  color: AppColors.textHint,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 16, color: Color(0xFFC5CAD3)),
          ],
        ),
      ),
    );
  }
}

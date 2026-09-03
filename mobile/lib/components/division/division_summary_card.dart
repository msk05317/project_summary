// 사업부 상세 화면 상단의 요약 카드.
// 좌: 진행률 + 전월 대비 + 프로젝트 수
// 우: 프로젝트 현황 (지연/주의/정상)
import 'package:flutter/material.dart';
import '../../design/design.dart';

class DivisionSummaryCard extends StatelessWidget {
  final String divisionLabel;
  final String updatedAt;        // "2026-06-22 09:41"
  final int? progressPercent;    // 68 (null = 집계 가능한 데이터 없음 → '-')
  final int? progressDeltaPp;    // +2 (null = 비교 데이터 없음 → 표시 안 함)
  final int projectCount;        // 7
  final int delayedCount;        // 1
  final int warningCount;        // 1
  final int normalCount;         // 5
  final int noDataCount;         // 데이터 미등록 프로젝트 수
  final String? basisText;       // "집계 모델 71개" 같은 근거 문구

  const DivisionSummaryCard({
    super.key,
    required this.divisionLabel,
    required this.updatedAt,
    required this.progressPercent,
    required this.progressDeltaPp,
    required this.projectCount,
    required this.delayedCount,
    required this.warningCount,
    required this.normalCount,
    this.noDataCount = 0,
    this.basisText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD6E2F2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 좌측: 진행률
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        '$divisionLabel 요약',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodyStrong.copyWith(
                          fontSize: 12,
                          color: AppColors.headerNavy,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      updatedAt,
                      style: AppText.caption.copyWith(
                        fontSize: 9,
                        color: const Color(0xFF7C8594),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  progressPercent == null ? '-' : '$progressPercent%',
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    color: progressPercent == null
                        ? const Color(0xFF9CA3AF)
                        : AppColors.headerNavy,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '전체 진행률',
                  style: AppText.caption.copyWith(
                    fontSize: 10,
                    color: const Color(0xFF7C8594),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (progressDeltaPp != null)
                      '전월 대비 ${progressDeltaPp! >= 0 ? '+' : ''}${progressDeltaPp}p',
                    '프로젝트 $projectCount건',
                    ?basisText,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(
                    fontSize: 10,
                    color: AppColors.headerNavy,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),
          // 구분선
          Container(
            width: 1,
            height: 110,
            color: const Color(0xFFD6E2F2),
          ),
          const SizedBox(width: 12),
          // 우측: 프로젝트 현황
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '프로젝트 현황',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodyStrong.copyWith(
                          fontSize: 12,
                          color: AppColors.headerNavy,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '총 $projectCount건',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        fontSize: 10,
                        color: const Color(0xFF7C8594),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _statusRow(const Color(0xFFFF0000), '지연', delayedCount),
                const SizedBox(height: 8),
                _statusRow(const Color(0xFFE97132), '주의', warningCount),
                const SizedBox(height: 8),
                _statusRow(const Color(0xFF196B24), '정상', normalCount),
                if (noDataCount > 0) ...[
                  const SizedBox(height: 8),
                  _statusRow(const Color(0xFF9CA3AF), '미등록', noDataCount),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusRow(Color dotColor, String label, int count) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppText.caption.copyWith(
            fontSize: 12,
            color: AppColors.headerNavy,
          ),
        ),
        const Spacer(),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: dotColor,
          ),
        ),
      ],
    );
  }
}

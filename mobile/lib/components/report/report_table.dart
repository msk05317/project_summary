// ============================================================
// File: lib/components/report/report_table.dart
// Section: Report / Table
// Figma:  Report / Table (CEFEM 프레임 표)
// 역할:    보고 화면의 표(헤더 + 다중 행) 표시. 가로 스크롤 지원.
// 토큰:    border/default, border/soft, typo/caption, typo/captionStrong
// 사용처:  보고 상세 화면 — 각 섹션(예: CEFEM 프레임) 카드 안
// ============================================================

import 'package:flutter/material.dart';
import '../../design/design.dart';

class ReportTable extends StatelessWidget {
  // 컬럼 헤더 (예: ['랑','5월 실적','W23 계획',...])
  final List<String> headers;

  // 본문 행 — 각 행은 headers 와 같은 길이 권장
  final List<List<String>> rows;

  const ReportTable({
    super.key,
    required this.headers,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border.all(color: AppColors.borderDefault),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeaderRow(headers: headers),
                for (int i = 0; i < rows.length; i++)
                  _BodyRow(
                    cells: _pad(rows[i], headers.length),
                    zebra: i.isOdd,
                    isLast: i == rows.length - 1,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // headers 길이에 맞게 빈 칸은 '-' 채움
  List<String> _pad(List<String> row, int len) {
    if (row.length == len) return row;
    if (row.length > len) return row.sublist(0, len);
    return [...row, ...List.filled(len - row.length, '-')];
  }
}

// ------------------------------------------------------------
// 헤더 한 줄
// ------------------------------------------------------------
class _HeaderRow extends StatelessWidget {
  final List<String> headers;
  const _HeaderRow({required this.headers});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.statusGraySoft,
        border: Border(
          bottom: BorderSide(color: AppColors.borderDefault),
        ),
      ),
      child: Row(
        children: [
          for (int i = 0; i < headers.length; i++)
            _Cell(
              text: headers[i],
              isHeader: true,
              isFirst: i == 0,
              isLast: i == headers.length - 1,
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// 본문 한 줄
// ------------------------------------------------------------
class _BodyRow extends StatelessWidget {
  final List<String> cells;
  final bool zebra;
  final bool isLast;

  const _BodyRow({
    required this.cells,
    required this.zebra,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: zebra ? AppColors.bgPage : AppColors.bgCard,
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : const BorderSide(color: AppColors.borderSoft),
        ),
      ),
      child: Row(
        children: [
          for (int i = 0; i < cells.length; i++)
            _Cell(
              text: cells[i],
              isHeader: false,
              isFirst: i == 0,
              isLast: i == cells.length - 1,
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// 단일 셀 (헤더/본문 공용)
// ------------------------------------------------------------
class _Cell extends StatelessWidget {
  final String text;
  final bool isHeader;
  final bool isFirst;
  final bool isLast;

  const _Cell({
    required this.text,
    required this.isHeader,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final width = isFirst ? 52.0 : 72.0;

    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x2,
        vertical: AppSpacing.x2,
      ),
      decoration: BoxDecoration(
        border: Border(
          right: isLast
              ? BorderSide.none
              : const BorderSide(color: AppColors.borderSoft),
        ),
      ),
      child: Text(
        text.isEmpty ? '-' : text,
        textAlign: TextAlign.center,
        style: isHeader
            ? AppText.captionStrong
            : AppText.caption.copyWith(color: AppColors.textMain),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

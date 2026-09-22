// 블룸 '막혀 있는 곳' 카드 — 계획 대비 실적 카드 밑.
import 'package:flutter/material.dart';

import '../design/colors.dart';
import '../models/bloom_daily.dart';

const _kCaution = Color(0xFFE97132);

class BloomTodayCard extends StatelessWidget {
  final BloomDailyBoard board;
  const BloomTodayCard({super.key, required this.board});

  @override
  Widget build(BuildContext context) {
    // 오늘 계획 · 어제 달성 · 오늘 품목별은 위 '계획 대비 실적' 일별 보기와
    // 겹쳐서 뺐다. 여기엔 거기 없는 '막혀 있는 곳' 만 남긴다.
    if (!board.hasBoard || board.blocked.isEmpty) return const SizedBox.shrink();
    return _BlockedBox(board: board);
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
      // 왼쪽 색 띠가 카드 높이만큼 늘어나게 stretch 를 쓴다. 그런데 이 카드는
      // 스크롤 목록 안이라 높이 제한이 없어서, stretch 가 '무한 높이' 를
      // 강요하다 터졌다 (블룸 화면을 열면 빨간 에러가 줄줄이 났다).
      // IntrinsicHeight 로 내용 높이를 먼저 재고 그 높이로 늘린다 —
      // 이슈 카드 · 캘린더 카드가 이미 이렇게 한다.
      child: IntrinsicHeight(
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
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../models/product_card.dart';

/// 모델 단위 그룹 카드 위젯
/// - 헤더: 신호등 색 dot + 모델명 + 부서 배지
/// - 본문: 이슈마다 색 dot + headline
class GroupedCardTile extends StatefulWidget {
  final GroupedCard group;
  final void Function(GroupedCard group, GroupedIssue issue)? onIssueTap;
  final void Function(GroupedCard group)? onGroupTap;
  final bool compact;

  const GroupedCardTile({
    super.key,
    required this.group,
    this.onGroupTap,
    this.onIssueTap,
    this.compact = false,
  });

  @override
  State<GroupedCardTile> createState() => _GroupedCardTileState();
}

class _GroupedCardTileState extends State<GroupedCardTile> {
  bool _expanded = false;
  static const int _kCollapsedMax = 3;

  // 줄 끝 보조 날짜 제거: (06-17), ( 6/17 ), (6-17) 등
  String _cleanTail(String s) {
    return s
        .replaceAll(RegExp(r'\s*\(\s*\d{1,2}[-/]\d{1,2}\s*\)\s*$'), '')
        .replaceAll(RegExp(r'\s*\(\s*0?\d{1,2}-0?\d{1,2}\s*\)\s*$'), '')
        .trimRight();
  }

  GroupedCard get group => widget.group;

  /// bullets를 렌더링하되, ↪ (그룹 메모)가 있으면
  /// 그 그룹 메모와 직전의 bullet 항목들을 노란 박스로 묶어 표시.
  Widget _buildBulletsWithGroup(List<String> bullets, Color cardColor) {
    // 그룹 단위로 분할: ↪ 가 나오면 그 직전까지의 bullet들과 함께 한 그룹
    final List<List<String>> groups = [];
    final List<String> standalone = [];
    List<String> currentGroup = [];

    for (final b in bullets) {
      if (b.startsWith('↪')) {
        // 그룹 메모 → 현재 누적된 bullets와 함께 그룹 마감
        currentGroup.add(b);
        groups.add(List.of(currentGroup));
        currentGroup = [];
      } else {
        currentGroup.add(b);
      }
    }
    // 남은 항목은 그룹 메모 없는 단독 bullets
    if (currentGroup.isNotEmpty) {
      standalone.addAll(currentGroup);
    }

    final children = <Widget>[];

    // 1) 그룹 박스들
    for (final g in groups) {
      children.add(Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB), // 옅은 노란 배경
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(color: const Color(0xFFF59E0B), width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: g.map((b) {
            final isGroupNote = b.startsWith('↪');
            return Padding(
              padding: EdgeInsets.only(
                top: 3, bottom: 3,
                left: isGroupNote ? 4 : 0,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isGroupNote) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: cardColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                  Expanded(
                    child: Text(
                      b,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: isGroupNote
                            ? const Color(0xFF92400E)
                            : const Color(0xFF374151),
                        fontStyle:
                            isGroupNote ? FontStyle.italic : FontStyle.normal,
                        fontWeight:
                            isGroupNote ? FontWeight.w600 : FontWeight.normal,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ));
    }

    // 2) 그룹에 속하지 않은 단독 bullets
    for (final b in standalone) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: cardColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Expanded(
              child: Text(
                b,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF374151),
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'RED':
        return const Color(0xFFE53935);
      case 'ORANGE':
        return const Color(0xFFEF6C00);
      case 'BLUE':
        return const Color(0xFF1E88E5);
      case 'GRAY':
        return const Color(0xFFBDBDBD);
      default:
        return const Color(0xFF424242);
    }
  }

  String? _ddayLabel(String? due) {
    if (due == null || due.isEmpty) return null;
    try {
      final parts = due.split('-');
      if (parts.length != 3) return null;
      final d = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      final today = DateTime.now();
      final t0 = DateTime(today.year, today.month, today.day);
      final diff = d.difference(t0).inDays;
      if (diff == 0) return 'D-DAY';
      if (diff > 0) return 'D-$diff';
      return 'D+${-diff}'; // 지연
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;

    final cardColor = _statusColor(group.status);
    final dday = _ddayLabel(group.dueDate);
    final badge = dday ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border(left: BorderSide(color: cardColor, width: 5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.onGroupTap == null ? null : () => widget.onGroupTap!(group),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ===== 헤더: 모델명 + 배지 =====
              Row(
                children: [
                  Expanded(
                    child: Text(
                      group.model.isEmpty ? '(이름 없음)' : group.model,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (badge.isNotEmpty)
                    _BadgeChip(label: badge, color: cardColor, emphasize: dday != null),
                ],
              ),
              // ===== 본문: 진행 중 항목 (bullets 우선, 없으면 issues 폴백) =====
              if (group.bullets.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...(() {
                  // 1) 다중 제품 그룹 우선 (__PRODUCT__ 마커 포함 시)
                  final isBloom = (group.divisionId ?? '').toLowerCase() == 'bloom';
                  final hasMarker = group.bullets.any((b) => b.startsWith('__PRODUCT__'));

                  // 1) 블룸 + __PRODUCT__ 마커 → 제품별 멀티 tracker
                  if (hasMarker && isBloom) {
                    final groups = _parseProcessGroups(group.bullets);
                    if (groups.isNotEmpty) {
                      return <Widget>[_buildProcessGroups(groups, compact: compact)];
                    }
                  }

                  // 2) 블룸 외 사업부 → tracker 표시 안 함, bullet 텍스트만
                  if (!isBloom) {
                    final cleanBullets = group.bullets
                        .where((b) => !b.startsWith('__PRODUCT__'))
                        .map(_cleanTail)
                        .toList();
                    return <Widget>[
                      _buildBulletsWithGroup(
                        _expanded
                            ? cleanBullets
                            : cleanBullets.take(_kCollapsedMax).toList(),
                        cardColor,
                      ),
                    ];
                  }

                  // 3) 블룸 단일 4단계 흐름
                  final parsed = _parseProcessBullets(
                    group.bullets.map(_cleanTail).toList(),
                  );
                  if (parsed.stages.isEmpty) {
                    return <Widget>[
                      _buildBulletsWithGroup(
                        _expanded
                            ? group.bullets.map(_cleanTail).toList()
                            : group.bullets.take(_kCollapsedMax).map(_cleanTail).toList(),
                        cardColor,
                      ),
                    ];
                  }
                  final remaining = parsed.remaining;
                  return <Widget>[
                    _buildProcessTracker(parsed.stages, compact: compact),
                    if (!compact && remaining.isNotEmpty)
                      _buildBulletsWithGroup(
                        _expanded
                            ? remaining
                            : remaining.take(_kCollapsedMax).toList(),
                        cardColor,
                      ),
                  ];
                })(),
                if (group.bullets.length > _kCollapsedMax)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: const Color(0xFF1E3A5F),
                      ),
                      onPressed: () => setState(() => _expanded = !_expanded),
                      child: Text(
                        _expanded
                            ? '▴ 접기'
                            : '▾ 더 보기 (${group.bullets.length - _kCollapsedMax}건)',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ] else if (group.issues.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...group.issues.map((it) {
                  final dotColor = _statusColor(it.status);
                  return InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: widget.onIssueTap == null
                        ? null
                        : () => widget.onIssueTap!(group, it),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 6, right: 8),
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: dotColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              _cleanTail(it.headline),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF374151),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}


class _ProcessStageData {
  final String key;
  final String label;
  final double percent;
  final String detail;
  final Color color;
  const _ProcessStageData({
    required this.key,
    required this.label,
    required this.percent,
    required this.detail,
    required this.color,
  });
}

class _ProcessParseResult {
  final List<_ProcessStageData> stages;
  final List<String> remaining;
  const _ProcessParseResult({
    required this.stages,
    required this.remaining,
  });
}

String? _detectProcessStage(String line) {
  final text = line.trim();
  final patterns = <String, List<String>>{
    '원자재': ['[원자재]', '원자재', '[원자재발주]', '원자재발주'],
    '입고': ['[입고]', '입고'],
    '생산': ['[생산]', '생산', '[생산일정]', '생산일정'],
    '납기': ['[납기]', '납기', '[출하]', '출하'],
  };
  for (final entry in patterns.entries) {
    for (final token in entry.value) {
      final normalized = text.replaceFirst(RegExp(r'^[\-\*\•]\s*'), '');
      if (normalized.startsWith(token)) return entry.key;
    }
  }
  return null;
}

String _stripProcessPrefix(String line, String stage) {
  var text = line.trim();
  text = text.replaceFirst(RegExp(r'^[\-\*\•]\s*'), '');
  text = text.replaceFirst(RegExp(r'^\[' + RegExp.escape(stage) + r'\]\s*'), '');
  if (stage == '원자재') {
    text = text.replaceFirst(RegExp(r'^\[원자재발주\]\s*'), '');
    text = text.replaceFirst(RegExp(r'^원자재발주\s*[:：-]?\s*'), '');
  }
  if (stage == '생산') {
    text = text.replaceFirst(RegExp(r'^\[생산일정\]\s*'), '');
    text = text.replaceFirst(RegExp(r'^생산일정\s*[:：-]?\s*'), '');
  }
  if (stage == '납기') {
    text = text.replaceFirst(RegExp(r'^\[출하\]\s*'), '');
    text = text.replaceFirst(RegExp(r'^출하\s*[:：-]?\s*'), '');
  }
  text = text.replaceFirst(RegExp(r'^' + RegExp.escape(stage) + r'\s*[:：-]?\s*'), '');
  return text.trim();
}

double _extractStagePercent(String text) {
  // 1) 명시적 퍼센티지 우선
  final explicit = RegExp(r'(\d+(?:\.\d+)?)\s*%').firstMatch(text);
  if (explicit != null) {
    return double.tryParse(explicit.group(1) ?? '') ?? 0;
  }

  // 2) 납기/출하 패턴: "출하완료 N", "총 PO M", "잔량 K" → N / M
  final shipped = RegExp(r'출하\s*완료\s*([\d,]+)').firstMatch(text);
  final total = RegExp(r'(?:총\s*PO|PO|총수량|총)\s*([\d,]+)').firstMatch(text);
  if (shipped != null && total != null) {
    final a = double.tryParse((shipped.group(1) ?? '0').replaceAll(',', '')) ?? 0;
    final b = double.tryParse((total.group(1) ?? '0').replaceAll(',', '')) ?? 0;
    if (b > 0) return ((a / b) * 100.0).clamp(0, 100);
  }

  // 3) 일반 비율 (생산 N/M 등)
  final ratio = RegExp(r'(\d[\d,]*)\s*/\s*(\d[\d,]*)').firstMatch(text);
  if (ratio != null) {
    final a = double.tryParse((ratio.group(1) ?? '0').replaceAll(',', '')) ?? 0;
    final b = double.tryParse((ratio.group(2) ?? '0').replaceAll(',', '')) ?? 0;
    if (b > 0) {
      final v = (a / b) * 100.0;
      return v.clamp(0, 100);
    }
    return 0;
  }

  // 4) 키워드 기반
  if (text.contains('완료') && !text.contains('미완')) return 100;
  if (text.contains('진행')) return 50;
  if (text.contains('예정') || text.contains('대기')) return 0;
  return 0;
}

Color _stageColor(String detail, double percent) {
  final d = detail.toLowerCase();
  if (d.contains('지연') || d.contains('부족') || d.contains('불량') || d.contains('문제')) {
    return const Color(0xFFDC2626);
  }
  if (percent >= 100) return const Color(0xFF16A34A);
  if (percent > 0) return const Color(0xFFF59E0B);
  return const Color(0xFFCBD5E1);
}

String _percentLabel(double value) {
  if (value == value.roundToDouble()) return '${value.toInt()}%';
  return '${value.toStringAsFixed(1)}%';
}

class _ProcessGroup {
  final String title;
  final List<_ProcessStageData> stages;
  const _ProcessGroup({required this.title, required this.stages});
}

List<_ProcessGroup> _parseProcessGroups(List<String> bullets) {
  // __PRODUCT__N) 제품명 헤더로 분할
  final groups = <_ProcessGroup>[];
  String currentTitle = '';
  List<String> currentBullets = [];

  void flush() {
    if (currentTitle.isEmpty && currentBullets.isEmpty) return;
    final parsed = _parseProcessBullets(currentBullets);
    if (parsed.stages.isNotEmpty) {
      groups.add(_ProcessGroup(title: currentTitle, stages: parsed.stages));
    }
    currentTitle = '';
    currentBullets = [];
  }

  for (final raw in bullets) {
    if (raw.startsWith('__PRODUCT__')) {
      flush();
      currentTitle = raw.substring('__PRODUCT__'.length).trim();
    } else {
      currentBullets.add(raw);
    }
  }
  flush();
  return groups;
}

Widget _buildProcessGroups(List<_ProcessGroup> groups, {bool compact = false}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (int i = 0; i < groups.length; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        if (groups[i].title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4, top: 2),
            child: Text(
              groups[i].title,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
          ),
        _buildProcessTracker(groups[i].stages, compact: compact),
      ],
    ],
  );
}

_ProcessParseResult _parseProcessBullets(List<String> bullets) {
  final found = <String, _ProcessStageData>{};
  final remaining = <String>[];

  for (final raw in bullets) {
    final stage = _detectProcessStage(raw);
    if (stage == null) {
      remaining.add(raw);
      continue;
    }
    final detail = _stripProcessPrefix(raw, stage);
    final percent = _extractStagePercent(detail);
    found[stage] = _ProcessStageData(
      key: stage,
      label: stage,
      percent: percent,
      detail: detail,
      color: _stageColor(detail, percent),
    );
  }

  if (found.isEmpty) {
    return _ProcessParseResult(stages: const [], remaining: bullets);
  }

  const order = ['원자재', '입고', '생산', '납기'];
  final stages = <_ProcessStageData>[
    for (final key in order)
      found[key] ??
          const _ProcessStageData(
            key: '',
            label: '',
            percent: 0,
            detail: '',
            color: Color(0xFFCBD5E1),
          )
  ];
  return _ProcessParseResult(stages: stages, remaining: remaining);
}

String _shortenDetail(String text) {
  // 카드 좁은 폭에 맞게 detail 을 짧게 다듬는다
  var t = text.trim();
  // 괄호 안 보충 정보 제거: "(6월 출하계획 없음...)" 등
  t = t.replaceAll(RegExp(r'\s*\([^)]*\)'), '');
  // "조립완료" 같은 보조어 제거
  t = t.replaceAll(RegExp(r'\s*(조립완료|조립진행|발주완료|입고완료)'), '');
  // 빈 표기 정리
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.length > 40) t = t.substring(0, 40) + '…';
  return t;
}

Widget _buildProcessTracker(List<_ProcessStageData> stages, {bool compact = false}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFE5E7EB)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(stages.length, (i) {
        final s = stages[i];
        final item = Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: s.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s.label.isEmpty ? '-' : s.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _percentLabel(s.percent),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: s.color == const Color(0xFFCBD5E1)
                      ? const Color(0xFF6B7280)
                      : s.color,
                ),
              ),
              if (!compact && s.detail.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  _shortenDetail(s.detail),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    height: 1.3,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ],
          ),
        );

        if (i == stages.length - 1) return item;

        return Expanded(
          child: Row(
            children: [
              item,
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 38),
                  height: 2,
                  color: const Color(0xFFE5E7EB),
                ),
              ),
            ],
          ),
        );
      }),
    ),
  );
}


class _BadgeChip extends StatelessWidget {
  final String label;
  final Color? color;
  final bool emphasize;
  const _BadgeChip({required this.label, this.color, this.emphasize = false});

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF1E3A5F);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: emphasize ? c : c.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c, width: 1.2),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: emphasize ? Colors.white : c,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

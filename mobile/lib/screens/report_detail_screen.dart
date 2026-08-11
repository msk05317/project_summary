import 'package:flutter/material.dart';

import '../components/components.dart';
import '../design/design.dart';
import '../models/report_note.dart';
import '../services/report_service.dart';
import '../services/favorites_service.dart';
import '../components/kpi/profit_kpi_section.dart';

class ReportDetailScreen extends StatefulWidget {
  final String projectKey;

  const ReportDetailScreen({
    super.key,
    this.projectKey = 'frame',
  });

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  late Future<ReportNote> _future;
  ReportTab _currentTab = ReportTab.report;

  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _loadFavorite();
  }

  Future<ReportNote> _load() {
    return ReportService.fetchByProject(widget.projectKey);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _loadFavorite() async {
    final fav = await FavoritesService.isFavorite(widget.projectKey);
    if (!mounted) return;
    setState(() {
      _isFavorite = fav;
    });
  }

  Future<void> _toggleFavorite() async {
    final nowFav = await FavoritesService.toggle(widget.projectKey);
    if (!mounted) return;
    setState(() {
      _isFavorite = nowFav;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.reportPageBg,
      body: SafeArea(
        child: FutureBuilder<ReportNote>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return _ErrorView(
                message: snapshot.error.toString(),
                onRetry: _refresh,
              );
            }

            final note = snapshot.data;
            if (note == null) {
              return _ErrorView(
                message: '데이터가 없습니다.',
                onRetry: _refresh,
              );
            }

            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _TopHeader(
                    titleKo: note.title,
                    titleEn: _englishName(note.projectKey, note.title),
                    isFavorite: _isFavorite,
                    onToggleFavorite: _toggleFavorite,
                    onRefresh: _refresh,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.x4,
                      AppSpacing.x3,
                      AppSpacing.x4,
                      AppSpacing.x6,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Breadcrumb(
                          items: [
                            BreadcrumbItem(
                              label: '목록',
                              onTap: () => Navigator.of(context).maybePop(),
                            ),
                            if ((note.divisionLabel ?? '').isNotEmpty)
                              BreadcrumbItem(label: note.divisionLabel!),
                            BreadcrumbItem(label: note.title),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.x3),
                        ReportTabBar(
                          current: _currentTab,
                          onChanged: (tab) {
                            setState(() {
                              _currentTab = tab;
                            });
                          },
                        ),
                        const SizedBox(height: AppSpacing.x4),
                        if (_currentTab == ReportTab.report) ...[
                          ReportTitleCard(
                            title: note.title,
                            subtitle: _buildSubtitle(note.reportDate),
                          ),
                          const SizedBox(height: AppSpacing.x2),
                          // 섹션 전체 표시 (admin/v2와 동일하게)
                          for (final section in note.bodySections) ...[
                            _ReportSectionCard(
                              section: section,
                              projectStatus: note.status ?? 'GRAY',
                            ),
                            const SizedBox(height: AppSpacing.x2),
                          ],
                        ] else
                          _ComingSoonView(tab: _currentTab),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String? _buildSubtitle(String? reportDate) {
    if (reportDate == null || reportDate.isEmpty) return null;
    final week = _weekNumber(reportDate);
    if (week == null) {
      return '보고일자: $reportDate';
    }
    return '보고일자: $reportDate · $week주차';
  }

  int? _weekNumber(String reportDate) {
    final dt = DateTime.tryParse(reportDate);
    if (dt == null) return null;

    // ISO 8601 week number 계산
    // - 주는 월요일 시작
    // - 목요일이 속한 주를 그 해의 주로 간주
    // - 백엔드(_parse_report_filename) 와 동일한 규칙
    final target = DateTime(dt.year, dt.month, dt.day);

    // 이번 주 목요일을 계산 (target 요일: 월=1 ~ 일=7)
    final weekday = target.weekday; // 1..7
    final thursday = target.add(Duration(days: 4 - weekday));

    // 목요일이 속한 해의 1월 1일
    final jan1 = DateTime(thursday.year, 1, 1);

    // 1월 1일부터 목요일까지의 일수 → 주차
    final daysDiff = thursday.difference(jan1).inDays;
    return 1 + (daysDiff ~/ 7);
  }

  String _englishName(String key, String fallback) {
    const map = <String, String>{
      'frame': 'Frame',
      'powerbox': 'Powerbox',
      'major_module': 'Major Module',
      'cup': 'CUP',
      'enclosure': 'Enclosure',
      'chamber': 'Chamber',
      'hrva_plate': 'HRVA Plate',
      'plating_cell': 'Plating Cell',
      'tolon': 'Tolon',
      'eos_chamber': 'EOS Chamber',
      'bloom_main': 'Bloom',
    };
    return map[key] ?? fallback;
  }
}

class _TopHeader extends StatelessWidget {
  final String titleKo;
  final String titleEn;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final Future<void> Function() onRefresh;

  const _TopHeader({
    required this.titleKo,
    required this.titleEn,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x2,
        AppSpacing.x3,
        AppSpacing.x2,
        AppSpacing.x3,
      ),
      color: const Color(0xFF0E2841),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.chevron_left_rounded),
            color: Colors.white,
            iconSize: 28,
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    titleKo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    titleEn,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: onToggleFavorite,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 20,
                      color: isFavorite ? const Color(0xFFF59E0B) : Colors.white54,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            color: Colors.white,
            iconSize: 22,
          ),
        ],
      ),
    );
  }
}

class _PhotoOnlySection extends StatelessWidget {
  final ReportSection section;
  const _PhotoOnlySection({required this.section});

  @override
  Widget build(BuildContext context) {
    final photo = section.firstPhoto;
    if (photo == null || photo.photoRef == null || photo.photoRef!.isEmpty) {
      return const SizedBox.shrink();
    }
    return BaseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: AppText.h2.copyWith(color: AppColors.reportHeading),
          ),
          const SizedBox(height: AppSpacing.x2),
          PhotoCard(
            photoRef: photo.photoRef!,
            fileName: photo.text,
          ),
        ],
      ),
    );
  }
}

class _ReportSectionCard extends StatelessWidget {
  final ReportSection section;
  final String projectStatus;

  const _ReportSectionCard({
    required this.section,
    required this.projectStatus,
  });

  @override
  Widget build(BuildContext context) {
    final rows = section.items
        .where((it) => it.type != 'photo' && it.text.trim().isNotEmpty)
        .toList();

    return BaseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: AppText.h2.copyWith(color: AppColors.reportHeading),
          ),
          const SizedBox(height: AppSpacing.x2),
          if (section.firstPhoto != null) ...[
            PhotoCard(
              photoRef: section.firstPhoto!.photoRef!,
              fileName: section.firstPhoto!.text,
            ),
            const SizedBox(height: AppSpacing.x2),
          ],
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.x1),
            _ReportItemRow(item: rows[i]),
          ],
          if (section.salesSummary != null && (section.salesVisible ?? true)) ...[
            const SizedBox(height: AppSpacing.x2),
            _SalesSummaryBadge(
              text: section.salesSummary!,
              reportDate: section.salesComputedAt,
            ),
          ],
        ],
      ),
    );
  }

}

class _SalesSummaryBadge extends StatelessWidget {
  final String text;
  final String? reportDate;

  const _SalesSummaryBadge({
    required this.text,
    this.reportDate,
  });

  /// ISO-8601 주차 계산 (reportDate 또는 오늘 기준)
  int _isoWeek() {
    DateTime d;
    try {
      d = reportDate != null && reportDate!.isNotEmpty
          ? DateTime.parse(reportDate!)
          : DateTime.now();
    } catch (_) {
      d = DateTime.now();
    }
    // ISO 8601: 목요일 기준
    final thursday = d.add(Duration(days: 3 - ((d.weekday + 6) % 7)));
    final firstThursday = DateTime(thursday.year, 1, 4);
    final firstMonday = firstThursday
        .subtract(Duration(days: (firstThursday.weekday + 6) % 7));
    final diff = thursday.difference(firstMonday).inDays;
    return (diff ~/ 7) + 1;
  }

  /// "7월 298.0만불 · W31 120.0만불 · 8월 407.0만불 ▲8.8%" 파싱
  List<_SalesBox> _parse(String raw) {
    final segs = raw.split('·').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final boxes = <_SalesBox>[];

    final segRe = RegExp(
      r'^(.+?)\s+([\-]?\d+(?:,\d{3})*(?:\.\d+)?)\s*만불(?:\s*([▲▼])\s*([\-]?\d+(?:\.\d+)?)\s*%)?',
    );

    for (final seg in segs) {
      final m = segRe.firstMatch(seg);
      if (m == null) continue;
      var label = (m.group(1) ?? '').trim();
      final amount = m.group(2) ?? '';
      final arrow = m.group(3);
      final pct = m.group(4);

      final wm = RegExp(r'^W(\d+)$').firstMatch(label);
      if (wm != null) {
        label = '${wm.group(1)}주차';
      } else if (label == '이번주') {
        label = '${_isoWeek()}주차';
      }

      boxes.add(_SalesBox(
        label: label,
        amount: amount,
        deltaPct: pct,
        deltaUp: arrow == '▲',
      ));
    }
    return boxes;
  }

  @override
  Widget build(BuildContext context) {
    final boxes = _parse(text);
    if (boxes.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F6FB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFDCE3EE)),
        ),
        child: Row(
          children: [
            const Text('💰', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF12325F),
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: List.generate(boxes.length, (i) {
        final isLast = i == boxes.length - 1;
        final b = boxes[i];
        final highlight = b.deltaPct != null;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: BoxDecoration(
                color: highlight ? const Color(0xFFFFF9E6) : const Color(0xFFF3F6FB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFDCE3EE)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    b.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF7C8594),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      b.amount,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF12325F),
                        height: 1.15,
                      ),
                    ),
                  ),
                  const Text(
                    '만불',
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF98A2B3),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (b.deltaPct != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${b.deltaUp ? "▲" : "▼"} ${b.deltaPct}%',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: b.deltaUp
                            ? const Color(0xFFD92D20)
                            : const Color(0xFF067647),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _SalesBox {
  final String label;
  final String amount;
  final String? deltaPct;
  final bool deltaUp;
  const _SalesBox({
    required this.label,
    required this.amount,
    this.deltaPct,
    this.deltaUp = true,
  });
}


class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

  bool get _isNotFound => message.contains('404');

  @override
  Widget build(BuildContext context) {
    final title = _isNotFound ? '등록된 보고서가 없습니다' : '데이터를 불러오지 못했어요.';
    final subtitle = _isNotFound
        ? '해당 프로젝트에 대한 상세 보고서가 아직 등록되지 않았어요.'
        : message;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.x5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isNotFound
                ? Icons.description_outlined
                : Icons.error_outline_rounded,
            size: 40,
            color: _isNotFound
                ? AppColors.reportBody
                : AppColors.reportHeading,
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            title,
            style: AppText.h2.copyWith(color: AppColors.reportHeading),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            subtitle,
            style: AppText.caption.copyWith(color: AppColors.reportBody),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.x4),
          if (_isNotFound)
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('뒤로 가기'),
            )
          else
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('다시 시도'),
            ),
        ],
      ),
    );
  }
}

class _ComingSoonView extends StatelessWidget {
  final ReportTab tab;
  const _ComingSoonView({required this.tab});

  IconData get _icon {
    switch (tab) {
      case ReportTab.production: return Icons.precision_manufacturing_outlined;
      case ReportTab.inbound:    return Icons.download_outlined;
      case ReportTab.outbound:   return Icons.upload_outlined;
      case ReportTab.report:     return Icons.description_outlined;
    }
  }

  String get _label {
    switch (tab) {
      case ReportTab.production: return '생산';
      case ReportTab.inbound:    return '입고';
      case ReportTab.outbound:   return '출하';
      case ReportTab.report:     return '보고';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 56, color: AppColors.textMute),
          const SizedBox(height: 14),
          Text('$_label 화면',
              style: AppText.h2.copyWith(color: AppColors.textSub)),
          const SizedBox(height: 6),
          Text('개발 중인 화면입니다',
              style: AppText.body.copyWith(color: AppColors.textMute)),
          const SizedBox(height: 2),
          Text('추후 업데이트 예정',
              style: AppText.caption.copyWith(color: AppColors.textMute)),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────
// _ReportItemRow: 한 섹션 안의 개별 아이템 1줄 렌더
//   · 입력 순서 그대로 (정렬 안 함)
//   · due_date 있으면 우측 DeadlinePill, 없으면 배지 위젯 자체 미삽입
//   · type 별 마커: highlight → 진한 dot, bullet → 옅은 dot, sub → 들여쓰기 + ·
// ─────────────────────────────────────────────
class _ReportItemRow extends StatelessWidget {
  final ReportItem item;

  const _ReportItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final deadline = _deadlineForIso(item.dueDate);
    final isSub = item.type == 'sub';
    final isHighlight = item.type == 'highlight';

    final textStyle = (isHighlight ? AppText.bodyStrong : AppText.body).copyWith(
      color: isSub ? AppColors.reportBody : AppColors.reportHeading,
      height: 1.45,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 0),
      child: Padding(
        padding: EdgeInsets.only(left: isSub ? 16 : 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildItemText(item, textStyle),
            ),
            if (deadline != null) ...[
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: DeadlinePill(
                  text: deadline.text,
                  tone: deadline.tone,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


({String text, DeadlineTone tone})? _deadlineForIso(String? dueDate) {
  if (dueDate == null || dueDate.isEmpty) return null;
  final dt = DateTime.tryParse(dueDate);
  if (dt == null) return null;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = dt.difference(today).inDays;

  final mm = dt.month.toString().padLeft(2, '0');
  final dd = dt.day.toString().padLeft(2, '0');

  if (diff < 0) {
    return (text: 'D+${-diff} ($mm/$dd)', tone: DeadlineTone.over);
  }
  if (diff == 0) {
    return (text: 'D-day ($mm/$dd)', tone: DeadlineTone.warn);
  }
  if (diff <= 7) {
    return (text: 'D-$diff ($mm/$dd)', tone: DeadlineTone.warn);
  }
  return (text: 'D-$diff ($mm/$dd)', tone: DeadlineTone.normal);
}


/// item.textRuns가 있으면 RichText로, 없으면 일반 Text로 렌더.
Widget _buildItemText(ReportItem item, TextStyle baseStyle) {
  // text_runs 유무 관계없이 항상 Text 위젯 사용 (렌더 경로 통일 → 폰트 크기 균일).
  // text_runs가 있으면 Text.rich로 span 트리 렌더.
  final runs = item.textRuns;
  if (runs == null || runs.isEmpty) {
    return Text(item.text, style: baseStyle, softWrap: true);
  }
  return Text.rich(
    TextSpan(
      style: baseStyle,
      children: runs.map((run) {
        Color? c;
        if (run.color != null && run.color!.isNotEmpty) {
          c = _parseHexColor(run.color!);
        }
        // 부모 baseStyle에서 fontSize/fontWeight/fontFamily/height 상속.
        // size_scale이 1.0이 아닐 때만 fontSize 명시.
        final scaledFontSize = run.sizeScale != 1.0
            ? (baseStyle.fontSize ?? 14.0) * run.sizeScale
            : null;
        return TextSpan(
          text: run.text,
          style: TextStyle(
            color: c,
            fontWeight: run.bold ? FontWeight.w700 : null,
            fontStyle: run.italic ? FontStyle.italic : null,
            decoration: run.underline ? TextDecoration.underline : null,
            fontSize: scaledFontSize,
          ),
        );
      }).toList(),
    ),
    softWrap: true,
  );
}

Color? _parseHexColor(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;

  // rgb(r,g,b) / rgba(r,g,b,a) 형식
  final rgbMatch = RegExp(
    r'^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)$',
    caseSensitive: false,
  ).firstMatch(s);
  if (rgbMatch != null) {
    try {
      final r = int.parse(rgbMatch.group(1)!).clamp(0, 255);
      final g = int.parse(rgbMatch.group(2)!).clamp(0, 255);
      final b = int.parse(rgbMatch.group(3)!).clamp(0, 255);
      int a = 255;
      final aStr = rgbMatch.group(4);
      if (aStr != null) {
        final aVal = double.parse(aStr);
        a = (aVal * 255).round().clamp(0, 255);
      }
      return Color.fromARGB(a, r, g, b);
    } catch (_) {
      return null;
    }
  }

  // hex (#RRGGBB / RRGGBB / #AARRGGBB / AARRGGBB / #RGB / RGB)
  var h = s;
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 3) {
    h = h.split('').map((c) => '$c$c').join();
  }
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  try {
    return Color(int.parse(h, radix: 16));
  } catch (_) {
    return null;
  }
}


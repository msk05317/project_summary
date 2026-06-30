import 'package:flutter/material.dart';

import '../components/components.dart';
import '../components/base/deadline_pill.dart';
import '../design/design.dart';
import '../models/report_note.dart';
import '../services/report_service.dart';
import '../services/favorites_service.dart';

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
                        ReportTitleCard(
                          title: note.title,
                          subtitle: _buildSubtitle(note.reportDate),
                        ),
                        const SizedBox(height: AppSpacing.x3),
                        if ((note.summaryText ?? '').isNotEmpty)
                          StatusSummaryCard(
                            text: note.summaryText!,
                            status: note.status ?? 'GRAY',
                          ),
                        const SizedBox(height: AppSpacing.x3),
                        for (final section in note.bodySections) ...[
                          _ReportSectionCard(
                            section: section,
                            projectStatus: note.status ?? 'GRAY',
                          ),
                          const SizedBox(height: AppSpacing.x3),
                        ],
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

    final jan1 = DateTime(dt.year, 1, 1);
    final daysUntilFirstMonday = (8 - jan1.weekday) % 7;
    final firstMonday = jan1.add(Duration(days: daysUntilFirstMonday));
    if (dt.isBefore(firstMonday)) return 0;

    final target = DateTime(dt.year, dt.month, dt.day);
    final diff = target.difference(firstMonday).inDays;
    return 1 + (diff ~/ 7);
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

class _ReportSectionCard extends StatelessWidget {
  final ReportSection section;
  final String projectStatus;

  const _ReportSectionCard({
    required this.section,
    required this.projectStatus,
  });

  @override
  Widget build(BuildContext context) {
    final headlineItem = _pickHeadlineItem(section);
    final headlineText = headlineItem?.text ?? section.title;

    // 마감 배지 텍스트 + 톤 (없으면 둘 다 null)
    final deadline = _deadlineFor(headlineItem?.dueDate);

    final deadlineStatus =
        _statusFromDueDate(headlineItem?.dueDate) ?? projectStatus;

    final subs = _buildSubs(section, headlineItem);

    return BaseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: AppText.h2.copyWith(color: AppColors.reportHeading),
          ),
          const SizedBox(height: AppSpacing.x3),
          if (section.firstPhoto != null) ...[
            PhotoCard(
              photoRef: section.firstPhoto!.photoRef!,
              fileName: section.firstPhoto!.text,
            ),
            const SizedBox(height: AppSpacing.x3),
          ],
          IssueBlock(
            headline: headlineText,
            status: deadlineStatus,
            showStar: deadlineStatus == 'RED' || deadlineStatus == 'YELLOW',
            subs: subs,
            deadlineText: deadline?.text,
            deadlineTone: deadline?.tone ?? DeadlineTone.normal,
          ),
        ],
      ),
    );
  }

  ReportItem? _pickHeadlineItem(ReportSection section) {
    for (final item in section.items) {
      if (item.type == 'highlight') return item;
    }
    for (final item in section.items) {
      if (item.type == 'bullet') return item;
    }
    for (final item in section.items) {
      if (item.type == 'sub') return item;
    }
    return null;
  }

  List<IssueSubLine> _buildSubs(ReportSection section, ReportItem? headlineItem) {
    final result = <IssueSubLine>[];
    for (final item in section.items) {
      if (identical(item, headlineItem)) continue;
      if (item.type == 'photo') continue;
      if (item.text.trim().isEmpty) continue;

      final marker = item.type == 'sub' ? '·' : '-';
      result.add(IssueSubLine(text: item.text, marker: marker));
    }
    return result;
  }

  String? _statusFromDueDate(String? dueDate) {
    if (dueDate == null || dueDate.isEmpty) return null;
    final dt = DateTime.tryParse(dueDate);
    if (dt == null) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = dt.difference(today).inDays;

    if (diff < 0) return 'RED';
    if (diff <= 7) return 'YELLOW';
    return 'GREEN';
  }

  // due_date → 'D+6 (06/18)' / 'D-3 (07/01)' 형식과 톤을 함께 반환
  ({String text, DeadlineTone tone})? _deadlineFor(String? dueDate) {
    if (dueDate == null || dueDate.isEmpty) return null;
    final dt = DateTime.tryParse(dueDate);
    if (dt == null) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = dt.difference(today).inDays;

    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');

    String text;
    DeadlineTone tone;

    if (diff < 0) {
      text = 'D+${-diff} ($mm/$dd)';
      tone = DeadlineTone.over;
    } else if (diff == 0) {
      text = 'D-day ($mm/$dd)';
      tone = DeadlineTone.warn;
    } else if (diff <= 7) {
      text = 'D-$diff ($mm/$dd)';
      tone = DeadlineTone.warn;
    } else {
      text = 'D-$diff ($mm/$dd)';
      tone = DeadlineTone.normal;
    }

    return (text: text, tone: tone);
  }
}


class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.x5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, size: 40),
          const SizedBox(height: AppSpacing.x3),
          Text(
            '데이터를 불러오지 못했어요.',
            style: AppText.h2.copyWith(color: AppColors.reportHeading),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            message,
            style: AppText.caption.copyWith(color: AppColors.reportBody),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.x4),
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

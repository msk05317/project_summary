import 'package:flutter/material.dart';
import '../design/design.dart';
import '../models/calendar_event.dart';
import '../models/dashboard.dart';
import '../services/dashboard_service.dart';
import '../components/calendar/calendar_summary_banner.dart';
import '../components/calendar/calendar_category_filter.dart';
import '../components/calendar/calendar_month_view.dart';
import '../components/calendar/calendar_day_event_card.dart';
import '../components/calendar/calendar_deadline_row.dart';
import '../components/home/app_bottom_nav.dart';
import 'division_select_screen.dart';
import 'report_detail_screen.dart';
import 'settings_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _today;
  late DateTime _month;
  late DateTime _selected;

  final Set<CalendarCategory> _filter = {
    CalendarCategory.shipping,
    CalendarCategory.receiving,
    CalendarCategory.report,
    CalendarCategory.approval,
    CalendarCategory.milestone,
  };

  List<CalendarEvent> _events = [];
  final Set<String> _doneIds = {};

  bool _loading = true;
  String? _error;

  bool _expandDay = false;
  bool _expandDeadline = false;

  @override
  void initState() {
    super.initState();
    _today = DateTime.now();
    _today = DateTime(_today.year, _today.month, _today.day);
    _month = DateTime(_today.year, _today.month, 1);
    _selected = _today;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cards = await DashboardService.fetchCards();
      final events = _cardsToEvents(cards);
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<CalendarEvent> _cardsToEvents(List<DashboardCard> cards) {
    final list = <CalendarEvent>[];
    for (final c in cards) {
      final seenDates = <String>{};

      DateTime? mainDate;
      if (c.dueDateMin != null && c.dueDateMin!.isNotEmpty) {
        mainDate = DateTime.tryParse(c.dueDateMin!);
      }

      final year = _today.year;
      final re = RegExp(r'\((\d{2})-(\d{2})\)');

      final aiTitle = c.headline.isNotEmpty ? c.headline : '';

      for (int i = 0; i < c.summaryBullets.length; i++) {
        final bullet = c.summaryBullets[i];
        final m = re.firstMatch(bullet);
        DateTime? d;
        if (m != null) {
          final mm = int.tryParse(m.group(1)!);
          final dd = int.tryParse(m.group(2)!);
          if (mm != null && dd != null) {
            d = DateTime(year, mm, dd);
          }
        }
        d ??= (i == 0 ? mainDate : null);
        if (d == null) continue;

        final key = '${d.toIso8601String()}|${c.projectKey}|$i';
        if (seenDates.contains(key)) continue;
        seenDates.add(key);

        final rawTitle = re.hasMatch(bullet)
            ? bullet.replaceAll(re, '').trim()
            : bullet.trim();
        String title;
        if (i == 0 && aiTitle.isNotEmpty) {
          title = aiTitle;
        } else if (rawTitle.isEmpty) {
          title = c.projectLabel;
        } else {
          title = rawTitle.length > 30
              ? '${rawTitle.substring(0, 30)}…'
              : rawTitle;
        }
        final category = _classify(title);

        final id = '${c.projectKey}-${d.toIso8601String()}-$i';
        list.add(CalendarEvent(
          id: id,
          date: d,
          category: category,
          title: title,
          divisionLabel: c.divisionLabel,
          projectLabel: c.projectLabel,
          projectKey: c.projectKey,
          headline: aiTitle,
          isDone: _doneIds.contains(id),
        ));
      }

      if (list.every((e) => !e.id.startsWith('${c.projectKey}-'))
          && mainDate != null) {
        final headline = c.headline.isNotEmpty
            ? c.headline
            : (c.summaryBullets.isNotEmpty
                ? c.summaryBullets.first
                : c.projectLabel);
        final id = '${c.projectKey}-${mainDate.toIso8601String()}-main';
        list.add(CalendarEvent(
          id: id,
          date: mainDate,
          category: _classify(headline),
          title: headline.length > 40
              ? '${headline.substring(0, 40)}…'
              : headline,
          divisionLabel: c.divisionLabel,
          projectLabel: c.projectLabel,
          isDone: _doneIds.contains(id),
        ));
      }
    }
    return list;
  }

  CalendarCategory _classify(String text) {
    final t = text;
    if (t.contains('출하') || t.contains('출고') || t.contains('선적')) {
      return CalendarCategory.shipping;
    }
    if (t.contains('승인') || t.contains('검토') || t.contains('확정')) {
      return CalendarCategory.approval;
    }
    if (t.contains('보고') || t.contains('리뷰') || t.contains('회의')) {
      return CalendarCategory.report;
    }
    if (t.contains('입고') || t.contains('발주')) {
      return CalendarCategory.receiving;
    }
    return CalendarCategory.milestone;
  }

  List<CalendarEvent> get _filtered =>
      _events.where((e) => _filter.contains(e.category)).toList();

  List<CalendarEvent> get _dayEvents {
    return _filtered.where((e) => _sameDay(e.date, _selected)).toList()
      ..sort((a, b) => a.title.compareTo(b.title));
  }

  List<CalendarEvent> get _deadline7 {
    final list = _filtered.where((e) {
      final d = e.diffDays(_today);
      return d >= 0 && d <= 7;
    }).toList()
      ..sort((a, b) {
        if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
        return a.date.compareTo(b.date);
      });
    return list;
  }

  List<CalendarEvent> get _dayEventsVisible =>
      _expandDay ? _dayEvents : _dayEvents.take(2).toList();

  List<CalendarEvent> get _deadline7Visible =>
      _expandDeadline ? _deadline7 : _deadline7.take(4).toList();

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  int get _pendingCount => _deadline7.where((e) => !e.isDone).length;
  int get _doneCount => _deadline7.where((e) => e.isDone).length;

  void _toggleDone(String id, bool done) {
    setState(() {
      if (done) {
        _doneIds.add(id);
      } else {
        _doneIds.remove(id);
      }
      _events = _events
          .map((e) => e.id == id ? e.copyWith(isDone: done) : e)
          .toList();
    });
  }

  void _openReport(String projectKey) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReportDetailScreen(projectKey: projectKey),
      ),
    );
  }

  void _handleBottomNav(AppNavTab tab) {
    switch (tab) {
      case AppNavTab.home:
        Navigator.of(context).popUntil((r) => r.isFirst);
        break;
      case AppNavTab.list:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DivisionSelectScreen()),
        );
        break;
      case AppNavTab.calendar:
        break;
      case AppNavTab.settings:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedText =
        '${_selected.year}-${_selected.month.toString().padLeft(2, '0')}-${_selected.day.toString().padLeft(2, '0')} · ${_dayEvents.length}건';

    return Scaffold(
      backgroundColor: AppColors.bgPage,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              color: AppColors.headerNavy,
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '캘린더',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _load,
                    child: const Icon(Icons.refresh,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 14),
                  const Icon(Icons.menu, color: Colors.white, size: 20),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline,
                                    color: Color(0xFFE53935), size: 40),
                                const SizedBox(height: 10),
                                Text('데이터 로드 실패\n$_error',
                                    textAlign: TextAlign.center),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: _load,
                                  child: const Text('다시 시도'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding:
                                const EdgeInsets.fromLTRB(16, 14, 16, 20),
                            children: [
                              CalendarSummaryBanner(
                                pendingCount: _pendingCount,
                                doneCount: _doneCount,
                                categoryLabels: const [
                                  '출하',
                                  '입고',
                                  '보고',
                                  '승인·검토',
                                  '마일스톤',
                                ],
                              ),
                              const SizedBox(height: 12),
                              CalendarCategoryFilter(
                                selected: _filter,
                                onToggle: (c) => setState(() {
                                  if (_filter.contains(c)) {
                                    _filter.remove(c);
                                  } else {
                                    _filter.add(c);
                                  }
                                }),
                              ),
                              const SizedBox(height: 12),
                              CalendarMonthView(
                                month: _month,
                                today: _today,
                                selected: _selected,
                                events: _filtered,
                                onSelect: (d) =>
                                    setState(() => _selected = d),
                                onPrev: () => setState(() => _month =
                                    DateTime(
                                        _month.year, _month.month - 1, 1)),
                                onNext: () => setState(() => _month =
                                    DateTime(
                                        _month.year, _month.month + 1, 1)),
                                onToday: () => setState(() {
                                  _month =
                                      DateTime(_today.year, _today.month, 1);
                                  _selected = _today;
                                }),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  const Text(
                                    '선택 날짜 일정',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.headerNavy,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    selectedText,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF7C8594)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (_dayEvents.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 20),
                                  child: Center(
                                    child: Text(
                                      '선택한 날짜에 일정이 없습니다',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                ),
                              ..._dayEventsVisible
                                  .map((e) => CalendarDayEventCard(
                                        event: e,
                                        onToggleDone: (v) =>
                                            _toggleDone(e.id, v),
                                        onTap: e.projectKey.isEmpty
                                            ? null
                                            : () => _openReport(e.projectKey),
                                      )),
                              if (_dayEvents.length >
                                  _dayEventsVisible.length)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      top: 4, bottom: 8),
                                  child: InkWell(
                                    onTap: () =>
                                        setState(() => _expandDay = true),
                                    child: Text(
                                      '+${_dayEvents.length - _dayEventsVisible.length}건 더 보기',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF156082),
                                      ),
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Row(
                                children: const [
                                  Text(
                                    'D-7 이내 마감 전체',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.headerNavy,
                                    ),
                                  ),
                                  Spacer(),
                                  Text(
                                    '미확인 우선',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFFE53935),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: const Color(0xFFE6EAF0),
                                      width: 1),
                                ),
                                child: Column(
                                  children: [
                                    if (_deadline7Visible.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 20),
                                        child: Text(
                                          'D-7 이내 마감이 없습니다',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ),
                                    for (int i = 0;
                                        i < _deadline7Visible.length;
                                        i++) ...[
                                      if (i > 0)
                                        const Divider(
                                            height: 1,
                                            color: Color(0xFFEDF0F4)),
                                      CalendarDeadlineRow(
                                          event: _deadline7Visible[i],
                                          today: _today),
                                    ],
                                    if (_deadline7.length >
                                        _deadline7Visible.length)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 10),
                                        child: InkWell(
                                          onTap: () => setState(() =>
                                              _expandDeadline = true),
                                          child: Text(
                                            '전체 보기 (+${_deadline7.length - _deadline7Visible.length}건)',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF156082),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
            ),
            AppBottomNav(
              current: AppNavTab.calendar,
              onChanged: _handleBottomNav,
            ),
          ],
        ),
      ),
    );
  }
}

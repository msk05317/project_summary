// 사업부 '매입·지급 현황' 카드.
//
// 엑셀 '월별 매입 현황 분석'을 앱에서 한 눈에 본다. 다른 사업부 화면과
// 같은 문법이다 — 월 칩 → 큰 숫자 하나 → 얇은 진행바 → 항목 리스트.
//
//   맨 위   그 달 매입액 하나. 그 밑에 지급률 바.
//   추이    매출 · 매입 · 지급 세 막대. 누르면 그 달로 넘어간다.
//   항목별  원소재 · 소모품 · 기타 · 외주. 바는 지급률이다.
//   지급    선급금 · 실지급액 · 실비투자.
//
// 잔액은 계산하지 않는다. 표의 잔액이 매입-지급과 맞지 않는 달이 있어서
// 서버가 '적힌 값'을 그대로 준다.
import 'package:flutter/material.dart';

import '../models/purchase_status.dart';

const _kNavy = Color(0xFF0F2C59);
const _kBorder = Color(0xFFE4E7EC);
const _kT1 = Color(0xFF0F172A);
const _kT2 = Color(0xFF4B5563);
const _kT3 = Color(0xFF98A2B3);
const _kRed = Color(0xFFDC2626);
const _kRev = Color(0xFF2073BE);   // 매출
const _kBuy = Color(0xFFC2600F);   // 매입
const _kPaid = Color(0xFFF1C79B);  // 지급
const _kTrack = Color(0xFFE8ECF1);

String _n(num v) {
  final neg = v < 0;
  final s = v.abs().round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return neg ? '($b)' : b.toString();
}

class PurchaseStatusCard extends StatefulWidget {
  final PurchaseStatus status;

  /// '요약 / 표로 보기' 토글. 지금은 지급 내역 아래를 다 비워 두기로 해서
  /// 꺼 둔다 — 다시 켤 때 이 한 줄만 true 로 주면 된다.
  final bool showToggle;

  const PurchaseStatusCard({
    super.key,
    required this.status,
    this.showToggle = false,
  });

  @override
  State<PurchaseStatusCard> createState() => _PurchaseStatusCardState();
}

class _PurchaseStatusCardState extends State<PurchaseStatusCard> {
  String _sel = '';
  bool _table = false;

  /// 막대를 누르면 그 달 숫자를 검은 박스로 띄운다. 막대 높이만 보고
  /// 얼마인지 맞히라고 하면 아무도 안 본다.
  String _tip = '';

  PurchaseStatus get _s => widget.status;

  String get _cur => _s.currency == 'KRW' ? '₩' : '\$';

  /// $186.4만 — 표에서만 전체 자리를 보여준다.
  String _man(double v) {
    final m = v / 10000;
    final neg = m < 0;
    final t = m.abs() >= 1000
        ? m.abs().toStringAsFixed(0)
        : m.abs().toStringAsFixed(1);
    final head = '$_cur${_group(t)}만';
    return neg ? '($head)' : head;
  }

  /// 툴팁 안에서는 통화 기호 없이 만 단위 숫자만 쓴다.
  String _manNum(double v) {
    final m = v / 10000;
    final t = m.abs() >= 1000 ? m.abs().toStringAsFixed(0) : m.abs().toStringAsFixed(1);
    return (m < 0 ? '(' : '') + _group(t) + (m < 0 ? ')' : '');
  }

  String _group(String t) {
    final dot = t.indexOf('.');
    final head = dot < 0 ? t : t.substring(0, dot);
    final tail = dot < 0 ? '' : t.substring(dot);
    final b = StringBuffer();
    for (var i = 0; i < head.length; i++) {
      if (i > 0 && (head.length - i) % 3 == 0) b.write(',');
      b.write(head[i]);
    }
    return '$b$tail';
  }

  PurchaseMonth get _cardMonth {
    final tabs = _s.tabs;
    for (final m in tabs) {
      if (m.month == _sel) return m;
    }
    // 고른 게 없거나 사라졌으면 가장 최근 달.
    return _s.months.isNotEmpty ? _s.months.last : tabs.first;
  }

  @override
  void initState() {
    super.initState();
    _sel = _s.latest;
  }

  @override
  Widget build(BuildContext context) {
    if (!_s.hasData || _s.months.isEmpty) return const SizedBox.shrink();
    final m = _cardMonth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _chips(),
        const SizedBox(height: 10),
        _hero(m),
        if (_s.months.length > 1) ...[
          const SizedBox(height: 10),
          _trend(),
        ],
        const SizedBox(height: 10),
        _table ? _itemTable(m) : _items(m),
        const SizedBox(height: 10),
        _payment(m),
        if (widget.showToggle) ...[
          const SizedBox(height: 8),
          _toggle(),
        ],
      ],
    );
  }

  // ------------------------------------------------------------ 칩
  Widget _chips() {
    final tabs = _s.tabs;
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final t = tabs[i];
          final on = t.month == _cardMonth.month;
          return GestureDetector(
            onTap: () => setState(() { _sel = t.month; _tip = ''; }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? _kNavy : Colors.white,
                border: Border.all(color: on ? _kNavy : _kBorder),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                t.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : _kT2,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _kBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
        child: child,
      );

  Widget _head(String title, String right, {Widget? tag}) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.w800, color: _kT1)),
          if (tag != null) ...[const SizedBox(width: 6), tag],
          const Spacer(),
          Text(right, style: const TextStyle(fontSize: 11, color: _kT3)),
        ],
      );

  // 제목 옆 작은 꼬리표. 지금은 누적이 달 합산일 때만 붙는다.
  Widget _tag(String s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F4F7),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(s,
            style: const TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: _kT3)),
      );

  // ------------------------------------------------------------ 히어로
  Widget _hero(PurchaseMonth m) {
    final rate = m.payRate.clamp(0, 100).toDouble();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _head('${m.label} 매입', m.isTotal ? m.range : '',
              tag: m.isSummed ? _tag('달 합산') : null),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_man(m.buy),
                  style: const TextStyle(
                      fontSize: 32,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.6,
                      color: _kNavy)),
              const SizedBox(width: 7),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(_n(m.buy),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: _kT2)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Row(children: [
              Expanded(
                flex: (rate * 10).round().clamp(0, 1000),
                child: Container(height: 7, color: _kBuy),
              ),
              if (rate > 0 && rate < 100) const SizedBox(width: 2),
              Expanded(
                flex: ((100 - rate) * 10).round().clamp(0, 1000),
                child: Container(height: 7, color: _kTrack),
              ),
            ]),
          ),
          const SizedBox(height: 7),
          Row(children: [
            _dot(_kBuy, '지급 완료 ${_p(m.payRate)}'),
            const SizedBox(width: 12),
            _dot(_kTrack, '미지급 ${_p(100 - m.payRate)}'),
          ]),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFEFF2F5)),
          const SizedBox(height: 12),
          Row(children: [
            _kpi('지급액', _man(m.paid), false),
            _sep(),
            _kpi('잔액', _man(m.balance), m.balance < 0 || m.balance > 0),
            _sep(),
            _kpi('매출액', _man(m.revenue), false),
          ]),
        ],
      ),
    );
  }

  String _p(double v) => '${v.toStringAsFixed(1)}%';

  Widget _dot(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 9,
            height: 9,
            decoration:
                BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(t,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: _kT2)),
      ]);

  Widget _sep() => Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 11),
      color: const Color(0xFFEFF2F5));

  Widget _kpi(String k, String v, bool warn) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: _kT3)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(v,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.3,
                      color: warn ? _kRed : _kNavy)),
            ),
          ],
        ),
      );

  // ------------------------------------------------------------ 추이
  Widget _trend() {
    final ms = _s.months;
    var max = 0.0;
    for (final m in ms) {
      if (m.buy > max) max = m.buy;
      if (m.revenue > max) max = m.revenue;
    }
    if (max <= 0) return const SizedBox.shrink();
    const plot = 128.0;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _head('월별 추이', '단위 만 ${_s.currency}'),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (ctx, bc) {
            final w = bc.maxWidth;
            final n = ms.length;
            final gw = n > 0 ? w / n : w;
            const tipW = 178.0;
            var tipLeft = 0.0;
            var tipIdx = -1;
            for (var i = 0; i < n; i++) {
              if (ms[i].month == _tip) tipIdx = i;
            }
            if (tipIdx >= 0) {
              tipLeft = ((tipIdx + 0.5) * gw - tipW / 2)
                  .clamp(0.0, (w - tipW).clamp(0.0, double.infinity));
            }
            return SizedBox(
              height: plot + 22,
              child: Stack(children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: ms.map((m) {
                    final on = m.month == _cardMonth.month;
                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() {
                          _sel = m.month;
                          _tip = _tip == m.month ? '' : m.month;
                        }),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            SizedBox(
                              height: plot,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _bar(m.revenue / max * plot, _kRev),
                                  const SizedBox(width: 3),
                                  _bar(m.buy / max * plot, _kBuy),
                                  const SizedBox(width: 3),
                                  _bar(m.paid / max * plot, _kPaid),
                                ],
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(m.label,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: on ? _kNavy : _kT2)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (tipIdx >= 0)
                  Positioned(
                    left: tipLeft,
                    top: 0,
                    width: tipW,
                    child: _tipBox(ms[tipIdx]),
                  ),
              ]),
            );
          }),
          const SizedBox(height: 9),
          Row(children: [
            _dot(_kRev, '매출'),
            const SizedBox(width: 12),
            _dot(_kBuy, '매입'),
            const SizedBox(width: 12),
            _dot(_kPaid, '지급'),
          ]),
        ],
      ),
    );
  }

  Widget _tipBox(PurchaseMonth m) => GestureDetector(
        onTap: () => setState(() => _tip = ''),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${m.label} · 만 ${_s.currency}',
                  style: const TextStyle(
                      fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 4),
              _tipLine('매출', _manNum(m.revenue), '매입', _manNum(m.buy)),
              const SizedBox(height: 2),
              _tipLine('지급', _manNum(m.paid), '잔액', _manNum(m.balance)),
            ],
          ),
        ),
      );

  Widget _tipLine(String k1, String v1, String k2, String v2) => Row(children: [
        Text('$k1 ',
            style: const TextStyle(fontSize: 10.5, color: Color(0xFFCBD5E1))),
        Text(v1,
            style: const TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white)),
        const SizedBox(width: 10),
        Text('$k2 ',
            style: const TextStyle(fontSize: 10.5, color: Color(0xFFCBD5E1))),
        Text(v2,
            style: const TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white)),
      ]);

  Widget _bar(double h, Color c) => Container(
        width: 11,
        height: h.isFinite ? h.clamp(2.0, 999.0) : 2,
        decoration: BoxDecoration(
          color: c,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        ),
      );

  // ------------------------------------------------------------ 항목별
  Widget _items(PurchaseMonth m) {
    if (m.items.isEmpty) return const SizedBox.shrink();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _head('항목별 매입', m.label),
          const SizedBox(height: 4),
          for (var i = 0; i < m.items.length; i++) _itemRow(m.items[i], i == m.items.length - 1),
        ],
      ),
    );
  }

  Widget _itemRow(PurchaseItem it, bool last) {
    final rate = it.payRate.clamp(0, 100).toDouble();
    return Container(
      padding: const EdgeInsets.only(top: 10, bottom: 9),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFF2F4F7))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(it.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800, color: _kT1)),
              ),
              const SizedBox(width: 8),
              Text(_man(it.buy),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800, color: _kNavy)),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(children: [
              Expanded(
                flex: (rate * 10).round().clamp(0, 1000),
                child: Container(height: 6, color: _kBuy),
              ),
              Expanded(
                flex: ((100 - rate) * 10).round().clamp(0, 1000),
                child: Container(height: 6, color: const Color(0xFFF1F3F6)),
              ),
            ]),
          ),
          const SizedBox(height: 5),
          Row(children: [
            Text('지급 ${_man(it.paid)} (${it.payRate.round()}%)',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: _kT2)),
            const Spacer(),
            Text('잔액 ${_man(it.balance)}',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: it.balance < 0 ? _kRed : _kT2)),
          ]),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 표로 보기
  Widget _itemTable(PurchaseMonth m) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _head('항목별 매입', '단위 ${_s.currency}'),
          const SizedBox(height: 10),
          Table(
            border: TableBorder.all(color: const Color(0xFFE3E7EB), width: 1),
            columnWidths: const {
              0: FlexColumnWidth(1.5),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(1),
            },
            children: [
              _tr(['항목', '매입액', '지급액', '잔액'], head: true),
              for (final it in m.items)
                _tr([it.label, _n(it.buy), _n(it.paid), _n(it.balance)],
                    neg: it.balance < 0),
              _tr(['합계', _n(m.buy), _n(m.paid), _n(m.balance)], total: true),
            ],
          ),
        ],
      ),
    );
  }

  TableRow _tr(List<String> cells,
          {bool head = false, bool total = false, bool neg = false}) =>
      TableRow(
        decoration: BoxDecoration(
          color: head
              ? const Color(0xFFF3F5F7)
              : (total ? _kNavy : Colors.transparent),
        ),
        children: [
          for (var i = 0; i < cells.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Text(
                cells[i],
                textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: head || total || i == 0
                      ? FontWeight.w800
                      : FontWeight.w600,
                  color: total
                      ? Colors.white
                      : (neg && i == 3 ? _kRed : const Color(0xFF334155)),
                ),
              ),
            ),
        ],
      );

  // ------------------------------------------------------------ 지급 내역
  Widget _payment(PurchaseMonth m) {
    final p = m.payment;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _head('지급 내역', m.isTotal ? m.range : m.label),
          const SizedBox(height: 4),
          _payRow('선급금', _man(p.prepaid), false),
          _payRow('실지급액', _man(p.actualPaid), false),
          _payRow('실비투자', p.invest == null ? '미입력' : _man(p.invest!),
              p.invest == null),
          const Divider(height: 17, color: Color(0xFFEDF0F3)),
          _payRow('지급 합계', _man(p.total), false, bold: true),
        ],
      ),
    );
  }

  Widget _payRow(String k, String v, bool dim, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Text(k,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
                  color: bold ? _kT1 : _kT2)),
          const Spacer(),
          Text(v,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: dim ? FontWeight.w700 : FontWeight.w800,
                  color: dim ? _kT3 : _kNavy)),
        ]),
      );

  // ------------------------------------------------------------ 토글
  Widget _toggle() => Row(children: [
        _tgl('요약', !_table, () => setState(() => _table = false)),
        const SizedBox(width: 6),
        _tgl('표로 보기', _table, () => setState(() => _table = true)),
      ]);

  Widget _tgl(String t, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: on ? _kNavy : Colors.white,
            border: Border.all(color: on ? _kNavy : _kBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(t,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: on ? Colors.white : _kT2)),
        ),
      );
}

// 전체 현황 — 타일이 곧 목록의 머리다.
//
// 전에는 '전체 현황'(지연·임박·보류·PO 대기 숫자)과 '지금 봐야 할 것'(프로젝트
// 목록)이 카드 두 장으로 떨어져 있었다. 그런데 둘은 같은 데이터다. 앞은 합계고
// 뒤는 그 내역이다. 지연 4건은 딱 두 곳(하바플레이트 3 · 챔버 1)에 있고, 그 두
// 곳이 바로 뒤 카드에 뜨던 목록이었다 — 같은 목록을 두 번 그리고 있었던 것.
//
// 원래 한 카드의 머리와 몸인 것을 둘로 떼어 놓았으니 관계가 보일 수가 없었다.
// 합치면 저절로 이어진다: 목록의 건수는 누른 타일에서 나오므로, 어디서도 안
// 나오는 '49' 같은 숫자가 생길 수 없다.
import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../../services/home_alerts_service.dart';
import '../../utils/status_words.dart';

// 맨 앞이 '정상' 이다. 문제만 네 칸 늘어놓으면 260종 중 250종이
// 제대로 가고 있다는 사실이 화면 어디에도 안 나온다. '보류' 는 뺐다 —
// 멈춰 세운 것은 오늘 볼 일이 아니라서 밑줄 한 줄로 충분하다.
//
// 값 순서가 곧 타일 순서다 (정상 · 일정 지연 · 특이사항 · 집중관리).
enum _Kind { normal, delayed, issue, soon }

class StatusBoardCard extends StatefulWidget {
  final HomeAlerts alerts;
  final bool loading;

  /// 목록의 한 줄을 누르면 그 프로젝트로 (키와 이름을 같이 넘긴다 —
  /// 이름 없이 열면 프로젝트 화면 맨 위가 빈 줄이 된다)
  final void Function(String projectKey, String projectName)? onTapProject;

  /// 타일을 길게 누르거나 '모두 보기' 를 누르면 전체 목록으로
  final void Function(String filter)? onTapAll;

  const StatusBoardCard({
    super.key,
    required this.alerts,
    this.loading = false,
    this.onTapProject,
    this.onTapAll,
  });

  @override
  State<StatusBoardCard> createState() => _StatusBoardCardState();
}

class _StatusBoardCardState extends State<StatusBoardCard> {
  // 열자마자 보이는 것은 '정상' 이다. 문제부터 펴 놓으면 앱을 열 때마다
  // 나쁜 소식으로 시작한다 — 265종 중 190종은 제대로 가고 있다.
  _Kind _sel = _Kind.normal;

  /// 서버가 쓰는 값. by_kind 의 키이자 alert 의 kind 다. 바꾸면 안 된다.
  static const _key = {
    _Kind.normal: '정상',
    _Kind.delayed: '지연',
    _Kind.issue: '이슈',
    _Kind.soon: '임박',
  };

  /// 화면에 보이는 말 (utils/status_words.dart).
  static const _label = {
    _Kind.normal: StatusWords.normal,
    _Kind.delayed: StatusWords.delayed,
    _Kind.issue: StatusWords.issue,
    _Kind.soon: StatusWords.soon,
  };

  /// 목록 머리처럼 자리가 있는 곳에서는 긴 말을 쓴다.
  static const _long = {
    _Kind.soon: StatusWords.soonFull,
  };

  // 정상은 초록, 나머지는 일정 지연 → 특이사항 → 집중관리 순으로
  // 색이 옅어진다. 급한 순서가 곧 색 순서다.
  static const _color = {
    _Kind.normal: AppColors.summaryNormal,
    _Kind.delayed: Color(0xFFDC2626),
    _Kind.issue: Color(0xFFEA580C),
    _Kind.soon: Color(0xFFD97706),
  };

  int _countOf(_Kind k) {
    final a = widget.alerts;
    switch (k) {
      case _Kind.normal:
        return a.normal;
      case _Kind.delayed:
        return a.delayed;
      case _Kind.issue:
        return a.issue;
      case _Kind.soon:
        return a.soon;
    }
  }

  List<AlertProject> _rowsOf(_Kind k) =>
      widget.alerts.byKind[_key[k]] ?? const <AlertProject>[];

  Widget _shell(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderDefault),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return _shell(const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(
            child: SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))),
      ));
    }
    // 못 받아왔을 때 0 을 그리면 '아무 문제 없음' 과 똑같이 보인다.
    if (!widget.alerts.loaded) {
      return _shell(const Row(children: [
        Icon(Icons.error_outline, size: 16, color: AppColors.statusRed),
        SizedBox(width: 6),
        Text('현황을 불러오지 못했습니다',
            style: TextStyle(fontSize: 13, color: AppColors.statusRed)),
      ]));
    }

    final a = widget.alerts;
    final rows = _rowsOf(_sel);

    return _shell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('전체 현황',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const Spacer(),
        Text(a.fromCache && a.savedAt != null
            ? '저장된 값'
            : '오늘 ${TimeOfDay.now().format(context)} 기준',
            style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
      ]),
      const SizedBox(height: 12),

      Row(children: [
        for (final k in _Kind.values) _tile(k),
      ]),

      const SizedBox(height: 14),
      Text('${_long[_sel] ?? _label[_sel]} ${_countOf(_sel)}건 · ${rows.length}곳',
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700,
              color: AppColors.textMute)),

      if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
              _sel == _Kind.delayed
                  ? '일정 밀린 모델이 없습니다'
                  : (_sel == _Kind.issue
                      ? '적어 둔 특이사항이 없습니다'
                      : '해당하는 항목이 없습니다'),
              style: const TextStyle(fontSize: 13, color: AppColors.textHint)),
        )
      else
        for (int i = 0; i < rows.length && i < 5; i++) _row(rows[i]),

      if (rows.length > 5)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: widget.onTapAll == null
                ? null
                : () => widget.onTapAll!(_key[_sel]!),
            child: Text('모두 보기 (${rows.length}곳)',
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.summaryInProgress)),
          ),
        ),

      const Divider(height: 19, color: AppColors.borderSoft),
      // '진행 중' 은 정상 타일과 같은 것을 다르게 센 숫자라 빼 버렸다.
      // 어디서도 안 나오는 숫자가 또 생긴다. 보류는 타일에서 뺐으니 여기 남긴다.
      Text(
          '모델 ${a.total}종 · 완료 ${a.done} · 보류 ${a.hold} · PO 대기 ${a.poWait}',
          style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
    ]));
  }

  Widget _tile(_Kind k) {
    final on = _sel == k;
    final c = _color[k]!;
    final n = _countOf(k);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _sel = k),
        child: Container(
          padding: const EdgeInsets.fromLTRB(2, 7, 2, 8),
          decoration: BoxDecoration(
            color: on ? AppColors.statusGraySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border(
              bottom: BorderSide(
                  color: on ? c : Colors.transparent, width: 2.5),
            ),
          ),
          child: Column(children: [
            Text('$n',
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: n > 0 ? c : AppColors.statusGray)),
            const SizedBox(height: 3),
            Text(_label[k]!,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textMute)),
          ]),
        ),
      ),
    );
  }

  Widget _row(AlertProject p) {
    final c = _color[_sel]!;
    return InkWell(
      onTap: widget.onTapProject == null
          ? null
          : () => widget.onTapProject!(p.key, p.label),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          Container(
            width: 7, height: 7,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(p.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain)),
          ),
          const SizedBox(width: 8),
          Text('${p.count}건',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w800, color: c)),
          const Icon(Icons.chevron_right, size: 18, color: AppColors.statusGray),
        ]),
      ),
    );
  }
}

// 홈 화면 '전체 사업부' 영역 상단의 검색바 + 필터 버튼.
//
// 시안 위치:
// - '전체 사업부' 섹션 헤더 바로 아래
// - 좌측: 돋보기 아이콘이 prefix 로 들어간 긴 검색 입력
// - 우측: 별도 사각 '필터' 버튼
//
// 책임 분리:
// - 이 위젯은 UI + 콜백 노출만 담당.
// - 실제 검색 결과 필터링은 호출 측(HomeScreen) 책임.
//   (입력값을 받아서 즐겨찾기/사업부 리스트를 줄여나가는 로직은 부모에서 처리)
//
// 사용 예:
//   SearchFilterRow(
//     value: _query,
//     onChanged: (v) => setState(() => _query = v),
//     onTapFilter: () => ScaffoldMessenger.of(context).showSnackBar(...),
//   )

import 'package:flutter/material.dart';

import '../../design/design.dart';

class SearchFilterRow extends StatelessWidget {
  // 외부에서 관리하는 검색어 (부모가 controller 를 가진 경우 controller 사용).
  // 둘 다 없으면 내부에서 비어있는 입력으로 시작.
  final String? value;

  // 입력이 변할 때마다 호출. (debounce 는 상위에서 책임)
  final ValueChanged<String>? onChanged;

  // 우측 '필터' 버튼 콜백. null 이면 비활성 톤.
  final VoidCallback? onTapFilter;

  // placeholder.
  final String hintText;

  const SearchFilterRow({
    super.key,
    this.value,
    this.onChanged,
    this.onTapFilter,
    this.hintText = '사업부명 / 프로젝트 검색',
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ─────────────────────────────
        // 검색바 (가변 폭)
        // ─────────────────────────────
        Expanded(
          child: _SearchField(
            value: value,
            onChanged: onChanged,
            hintText: hintText,
          ),
        ),

        const SizedBox(width: 8),

        // ─────────────────────────────
        // 필터 버튼 (고정 폭)
        // ─────────────────────────────
        _FilterButton(onTap: onTapFilter),
      ],
    );
  }
}

// 좌측 검색 입력 필드.
// - 값(value) 이 외부에서 바뀌어도 동기화되도록 didUpdateWidget 으로 컨트롤러 갱신.
class _SearchField extends StatefulWidget {
  final String? value;
  final ValueChanged<String>? onChanged;
  final String hintText;

  const _SearchField({
    required this.value,
    required this.onChanged,
    required this.hintText,
  });

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value ?? '');
  }

  @override
  void didUpdateWidget(covariant _SearchField old) {
    super.didUpdateWidget(old);
    // 외부에서 value 가 바뀐 경우(예: 검색 초기화), 컨트롤러 동기화.
    if ((widget.value ?? '') != _ctrl.text) {
      _ctrl.text = widget.value ?? '';
      // 커서 위치를 맨 끝으로
      _ctrl.selection =
          TextSelection.collapsed(offset: _ctrl.text.length);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.reportCardBorder),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 18,
            color: AppColors.textMute,
          ),
          const SizedBox(width: 6),
          // 입력 필드 자체는 보더/배경 없이 컨테이너 안에 들어감.
          Expanded(
            child: TextField(
              controller: _ctrl,
              onChanged: widget.onChanged,
              textInputAction: TextInputAction.search,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.reportHeading,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: InputBorder.none,
                hintText: widget.hintText,
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: AppColors.textHint,
                ),
              ),
            ),
          ),
          // 입력이 있을 때만 보이는 클리어 버튼.
          if (_ctrl.text.isNotEmpty)
            InkResponse(
              radius: 16,
              onTap: () {
                _ctrl.clear();
                widget.onChanged?.call('');
                // 다시 그려서 클리어 버튼이 사라지도록.
                setState(() {});
              },
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: AppColors.textMute,
              ),
            ),
        ],
      ),
    );
  }
}

// 우측 '필터' 버튼.
// - 이번 단계에서는 UI 만, 클릭 시 호출 측이 토스트 등을 띄움.
class _FilterButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _FilterButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.reportCardBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune_rounded,
              size: 16,
              color: disabled ? AppColors.textHint : AppColors.reportHeading,
            ),
            const SizedBox(width: 4),
            Text(
              '필터',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color:
                    disabled ? AppColors.textHint : AppColors.reportHeading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

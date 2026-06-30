// 홈 화면 하단의 LLM 입력바.
// 현재는 UI 만 구현된 단계(L0).
// - onSubmit 콜백이 주어지면 그 함수로 텍스트를 전달
// - onSubmit 이 없으면 "준비 중" 안내만 표시
//
// 추후 백엔드에 /chat 같은 LLM 라우트가 생기면,
// 호출 측에서 onSubmit 으로 실제 호출을 연결하면 됩니다.
// 이 컴포넌트는 LLM 연동 자체를 알 필요가 없습니다(관심사 분리).

import 'package:flutter/material.dart';

import '../../design/design.dart';

class BottomPromptBar extends StatefulWidget {
  // 사용자가 입력한 텍스트를 받아 처리할 콜백.
  // null 이면 입력은 가능하지만 전송 시 "준비 중" SnackBar 만 띄웁니다.
  final Future<void> Function(String text)? onSubmit;

  const BottomPromptBar({
    super.key,
    this.onSubmit,
  });

  @override
  State<BottomPromptBar> createState() => _BottomPromptBarState();
}

class _BottomPromptBarState extends State<BottomPromptBar> {
  // 입력창의 컨트롤러. 전송 후 입력값을 비우거나 키보드를 닫을 때 사용합니다.
  final TextEditingController _controller = TextEditingController();

  // 현재 전송 중인지 여부. 스피너 표시/중복 클릭 방지에 사용합니다.
  bool _sending = false;

  @override
  void dispose() {
    // 컨트롤러 누수 방지를 위해 반드시 dispose.
    _controller.dispose();
    super.dispose();
  }

  // 전송 버튼 또는 키보드의 submit 시 호출됩니다.
  // 1) 빈 문자열이면 무시
  // 2) onSubmit 미지정이면 안내만 표시
  // 3) onSubmit 호출 후 입력값 초기화
  Future<void> _handleSend() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    if (widget.onSubmit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('LLM 연결 준비 중입니다.')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      await widget.onSubmit!(text);
      _controller.clear();
    } finally {
      // 호출 도중 위젯이 dispose 됐을 수 있으므로 mounted 확인.
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x4,
        AppSpacing.x2,
        AppSpacing.x4,
        AppSpacing.x2,
      ),
      child: Container(
        // 둥근 alert-style 바.
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.reportCardBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            // 입력창
            Expanded(
              child: TextField(
                controller: _controller,
                onSubmitted: (_) => _handleSend(),
                decoration: const InputDecoration(
                  hintText: '무엇이든 물어보세요',
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            // 음성 입력 버튼 (시안 v3: 옅은 파란 원형 배경)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('음성 입력 준비 중입니다.')),
                  );
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Color(0xFFDBEAFE), // 옅은 파랑
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mic_rounded,
                    size: 18,
                    color: Color(0xFF156082), // todayBlue
                  ),
                ),
              ),
            ),

            // 전송 버튼: 전송 중이면 스피너로 교체합니다.
            _sending
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF0E2841),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: _handleSend,
                      icon: const Icon(Icons.send_rounded, size: 18),
                      color: Colors.white,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

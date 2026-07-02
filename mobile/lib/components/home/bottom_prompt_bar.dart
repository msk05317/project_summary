import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../../services/voice_input_service.dart';

class BottomPromptBar extends StatefulWidget {
  final Future<void> Function(String text)? onSubmit;

  const BottomPromptBar({
    super.key,
    this.onSubmit,
  });

  @override
  State<BottomPromptBar> createState() => _BottomPromptBarState();
}

class _BottomPromptBarState extends State<BottomPromptBar>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  bool _listening = false;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _pulse.dispose();
    super.dispose();
  }

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
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await VoiceInputService.stop();
      if (mounted) {
        setState(() => _listening = false);
        _pulse.stop();
      }
      return;
    }

    final ok = await VoiceInputService.ensureReady();
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('음성 인식을 사용할 수 없어요. 마이크 권한을 확인해주세요.')),
      );
      return;
    }

    setState(() => _listening = true);
    _pulse.repeat(reverse: true);

    await VoiceInputService.start(
      onResult: (partial, isFinal) {
        if (!mounted) return;
        setState(() {
          _controller.text = partial;
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: partial.length),
          );
        });
        if (isFinal) {
          setState(() => _listening = false);
          _pulse.stop();
        }
      },
    );
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
            Expanded(
              child: TextField(
                controller: _controller,
                onSubmitted: (_) => _handleSend(),
                decoration: InputDecoration(
                  hintText: _listening ? '듣고 있어요…' : '무엇이든 물어보세요',
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _toggleMic,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, _) {
                    final bg = _listening
                        ? Color.lerp(
                            const Color(0xFFFFC1C1),
                            const Color(0xFFFF6B6B),
                            _pulse.value,
                          )!
                        : const Color(0xFFDBEAFE);
                    final fg = _listening
                        ? Colors.white
                        : const Color(0xFF156082);
                    return Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: bg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _listening ? Icons.stop_rounded : Icons.mic_rounded,
                        size: 18,
                        color: fg,
                      ),
                    );
                  },
                ),
              ),
            ),
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

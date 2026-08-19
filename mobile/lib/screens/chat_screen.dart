import 'package:flutter/material.dart';
import '../design/design.dart';
import '../models/chat_message.dart';
import '../services/chat_service.dart';
import '../services/voice_input_service.dart';
import '../components/chat/chat_bubble.dart';
import 'project_overview_screen.dart';

class ChatScreen extends StatefulWidget {
  final String? initialQuestion;
  const ChatScreen({super.key, this.initialQuestion});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _messages = [];
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
    if (widget.initialQuestion != null &&
        widget.initialQuestion!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _send(widget.initialQuestion!.trim());
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _pulse.dispose();
    super.dispose();
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
        const SnackBar(content: Text('음성 인식을 사용할 수 없어요.')),
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

  Future<void> _send(String text) async {
    final msg = text.trim();
    if (msg.isEmpty || _sending) return;
    setState(() {
      _messages.add(ChatMessage(role: ChatRole.user, text: msg));
      _messages.add(ChatMessage(
        role: ChatRole.assistant,
        text: '',
        loading: true,
      ));
      _sending = true;
      _controller.clear();
    });
    _scrollToEnd();

    final answer = await ChatService.ask(msg);

    if (!mounted) return;
    setState(() {
      _messages.removeLast();
      _messages.add(answer);
      _sending = false;
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _openSource(ChatSource s) {
    if (s.projectKey.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectOverviewScreen(projectKey: s.projectKey, projectName: ''),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPage,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              color: AppColors.headerNavy,
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'OneView 어시스턴트',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Icon(Icons.close,
                        color: Colors.white, size: 22),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _messages.isEmpty
                  ? _EmptyState(onQuickAsk: _send)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) => ChatBubble(
                        message: _messages[i],
                        onTapSource: _openSource,
                      ),
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Color(0xFFE6EAF0), width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      decoration: InputDecoration(
                        hintText: _listening ? '듣고 있어요…' : '무엇이든 물어보세요',
                        hintStyle: const TextStyle(
                            color: Color(0xFF9AA3AF), fontSize: 14),
                        filled: true,
                        fillColor: const Color(0xFFF6F8FB),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
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
                          width: 40,
                          height: 40,
                          decoration:
                              BoxDecoration(color: bg, shape: BoxShape.circle),
                          child: Icon(
                            _listening
                                ? Icons.stop_rounded
                                : Icons.mic_rounded,
                            size: 20,
                            color: fg,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Material(
                    color: AppColors.headerNavy,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _sending
                          ? null
                          : () => _send(_controller.text),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.send_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ValueChanged<String> onQuickAsk;
  const _EmptyState({required this.onQuickAsk});

  @override
  Widget build(BuildContext context) {
    const samples = [
      '지연되고 있는 프로젝트가 뭐가 있어?',
      '이번 주 마감 임박한 일정 알려줘',
      '파워박스 EMA 승인 상황은?',
      '하바플레이트 현황 요약해줘',
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '무엇을 도와드릴까요?',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.reportHeading,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '프로젝트, 일정, 이슈에 대해\n자연스럽게 물어보세요.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF7C8594),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '이렇게 물어볼 수 있어요',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF7C8594),
            ),
          ),
          const SizedBox(height: 10),
          ...samples.map((q) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => onQuickAsk(q),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFFE6EAF0), width: 1),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            q,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.reportHeading,
                            ),
                          ),
                        ),
                        const Icon(Icons.north_east,
                            size: 14, color: Color(0xFF7C8594)),
                      ],
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

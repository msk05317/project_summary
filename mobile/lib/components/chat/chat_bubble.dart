import 'package:flutter/material.dart';
import '../../design/design.dart';
import '../../models/chat_message.dart';
import 'source_chip.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final ValueChanged<ChatSource>? onTapSource;

  const ChatBubble({
    super.key,
    required this.message,
    this.onTapSource,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    final bg = isUser ? AppColors.headerNavy : Colors.white;
    final fg = isUser ? Colors.white : AppColors.reportHeading;

    Widget body;
    if (message.loading) {
      body = SizedBox(
        width: 60,
        height: 16,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: List.generate(
            3,
            (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _Dot(delay: i * 200),
            ),
          ),
        ),
      );
    } else if (message.error != null) {
      body = Text(
        '오류: ${message.error}',
        style: const TextStyle(fontSize: 13, color: Color(0xFFE53935)),
      );
    } else {
      body = Text(
        message.text,
        style: TextStyle(fontSize: 14, color: fg, height: 1.5),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser)
            Container(
              margin: const EdgeInsets.only(right: 8, top: 2),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.headerNavy,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome,
                  color: Colors.white, size: 16),
            ),
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(14),
                      topRight: const Radius.circular(14),
                      bottomLeft: Radius.circular(isUser ? 14 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 14),
                    ),
                    border: isUser
                        ? null
                        : Border.all(
                            color: const Color(0xFFE6EAF0),
                            width: 1,
                          ),
                  ),
                  child: body,
                ),
                if (!isUser && message.sources.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: message.sources
                          .map((s) => SourceChip(
                                source: s,
                                onTap: () => onTapSource?.call(s),
                              ))
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _c.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFF7C8594),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

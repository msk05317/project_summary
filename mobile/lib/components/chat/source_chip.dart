import 'package:flutter/material.dart';
import '../../models/chat_message.dart';

class SourceChip extends StatelessWidget {
  final ChatSource source;
  final VoidCallback? onTap;
  const SourceChip({super.key, required this.source, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F8FB),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE6EAF0), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined,
                size: 12, color: Color(0xFF7C8594)),
            const SizedBox(width: 4),
            Text(
              source.projectLabel,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF525A66),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

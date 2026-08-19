import 'package:flutter/material.dart';
import '../design/typography.dart';

class ModelCostDetailScreen extends StatelessWidget {
  final Map<String, dynamic> model;
  const ModelCostDetailScreen({super.key, required this.model});

  String _fmt(num? v) {
    final n = (v ?? 0).toInt();
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final pos = s.length - i;
      buf.write(s[i]);
      if (pos > 1 && pos % 3 == 1) buf.write(',');
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final name = model['name'] ?? model['id'] ?? '';
    final group = model['group'] ?? '양산';
    final status = model['status'] ?? '정상';
    final price = (model['price'] as num?)?.toInt() ?? 0;
    final mcost = (model['material_cost'] as num?)?.toInt() ?? 0;
    final ratio = price > 0 ? (mcost / price * 100) : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(name, style: AppText.bodyStrong.copyWith(fontSize: 17)),
        iconTheme: const IconThemeData(color: Color(0xFF111827)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 모델 정보 헤더
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Text('💰', style: TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: AppText.bodyStrong.copyWith(fontSize: 16)),
                      const SizedBox(height: 4),
                      Row(children: [
                        _chip(group, group == '양산'
                            ? const Color(0xFFDBEAFE) : const Color(0xFFFEF3C7),
                            group == '양산'
                                ? const Color(0xFF1D4ED8) : const Color(0xFFB45309)),
                        const SizedBox(width: 6),
                        _chip(status, const Color(0xFFF3F4F6), const Color(0xFF374151)),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 판가 / 재료비
          Row(children: [
            Expanded(child: _costCard('판가', '\$${_fmt(price)}', const Color(0xFF0F2C59))),
            const SizedBox(width: 10),
            Expanded(child: _costCard('재료비', '\$${_fmt(mcost)}', const Color(0xFF374151))),
          ]),
          const SizedBox(height: 12),
          // 재료비율
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('재료비율', style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                const SizedBox(height: 8),
                Text(
                  ratio != null ? '${ratio.toStringAsFixed(1)}%' : '-',
                  style: const TextStyle(
                      fontSize: 34, fontWeight: FontWeight.w800, color: Color(0xFF0F2C59)),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio != null ? (ratio / 100).clamp(0.0, 1.0) : 0,
                    minHeight: 8,
                    backgroundColor: const Color(0xFFF3F4F6),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      ratio != null && ratio >= 80
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF0F2C59),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  price > 0
                      ? '재료비 \$${_fmt(mcost)} ÷ 판가 \$${_fmt(price)} × 100'
                      : '판가가 입력되지 않아 계산할 수 없습니다',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  Widget _costCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

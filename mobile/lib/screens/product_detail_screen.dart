import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../models/product_card.dart';
import '../services/api_client.dart';
import '../widgets/traffic_light_card.dart';

class ProductDetailScreen extends StatelessWidget {
  final String docId;
  final String productName;

  const ProductDetailScreen({
    super.key,
    required this.docId,
    required this.productName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: Text(productName),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: SafeArea(
        bottom: true,
        child: FutureBuilder<ProductDetail>(
        future: ApiClient().fetchProductDetail(docId, productName),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('에러: ${snap.error}'));
          }

          final p = snap.data!;
          final color = TrafficLightCard.statusColors[p.status] ?? Colors.grey;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 헤드라인 카드
              Card(
                color: color.withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          p.headline,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // KPI
              if (p.kpis.isNotEmpty) ...[
                _sectionTitle('📊 KPI'),
                ...p.kpis.map((k) => _kpiCard(k)),
              ],

              // 핵심 이슈
              if (p.criticalIssues.isNotEmpty) ...[
                _sectionTitle('🚨 핵심 이슈'),
                ...p.criticalIssues.map((i) => _issueCard(i)),
              ],

              // 마일스톤
              if (p.milestones.isNotEmpty) ...[
                _sectionTitle('📅 일정'),
                ...p.milestones.map((m) => _milestoneCard(m)),
              ],

              // 매출
              if (p.financials.isNotEmpty) ...[
                _sectionTitle('💰 매출'),
                Card(
                  child: ListTile(
                    title: Text(p.financials['revenue']?.toString() ?? '-'),
                    subtitle: Text(p.financials['note']?.toString() ?? ''),
                  ),
                ),
              ],

              // 다음 액션
              if (p.nextActions.isNotEmpty) ...[
                _sectionTitle('✅ 다음 액션'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: p.nextActions
                          .map((a) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Text('• $a'),
                              ))
                          .toList(),
                    ),
                  ),
                ),
              ],

              // 원본 슬라이드 보기
              if (p.slideImageUrls.isNotEmpty) ...[
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SlideViewer(urls: p.slideImageUrls),
                    ),
                  ),
                  icon: const Icon(Icons.image),
                  label: Text('원본 PPT 표/차트 보기 (${p.slideImageUrls.length}장)'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ],
            ],
          );
        },
      )
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
        child: Text(t,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      );

  Widget _kpiCard(dynamic k) {
    final status = k['status'] ?? 'BLACK';
    final color = TrafficLightCard.statusColors[status] ?? Colors.grey;
    return Card(
      child: ListTile(
        title: Text(k['label']?.toString() ?? ''),
        trailing: Text(
          '${k['value']} / ${k['target']}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _issueCard(dynamic i) {
    return Card(
      color: Colors.red.shade50,
      child: ListTile(
        leading: const Icon(Icons.warning_amber, color: Colors.red),
        title: Text(i['title']?.toString() ?? ''),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(i['detail']?.toString() ?? ''),
            const SizedBox(height: 4),
            Text('영향: ${i['impact'] ?? ''}',
                style: const TextStyle(fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  Widget _milestoneCard(dynamic m) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.event),
        title: Text(m['event']?.toString() ?? ''),
        subtitle: Text(m['date']?.toString() ?? ''),
        trailing: Text(
          m['status']?.toString() ?? '',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

// 원본 PPT 슬라이드 핀치 줌 뷰어
class SlideViewer extends StatelessWidget {
  final List<String> urls;
  const SlideViewer({super.key, required this.urls});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('원본 슬라이드', style: TextStyle(color: Colors.white)),
      ),
      body: PhotoViewGallery.builder(
        itemCount: urls.length,
        builder: (ctx, i) => PhotoViewGalleryPageOptions(
          imageProvider: NetworkImage(urls[i]),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 4,
        ),
        scrollPhysics: const BouncingScrollPhysics(),
      ),
    );
  }
}

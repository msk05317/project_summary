import '../config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';


class ProjectDetailScreen extends StatefulWidget {
  final String projectKey;
  final String projectLabel;
  final String? status;  // ← 추가

  const ProjectDetailScreen({
    super.key,
    required this.projectKey,
    required this.projectLabel,
    this.status,  // ← 추가
  });

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  Map<String, dynamic>? detail;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await http.get(
        Uri.parse('$kApiBaseUrl/projects/${widget.projectKey}'),
      );
      if (res.statusCode != 200) {
        throw Exception('${res.statusCode}');
      }
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      setState(() {
        detail = decoded;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'RED':
        return Colors.red;
      case 'BLUE':
        return Colors.blue;
      case 'BLACK':
        return Colors.grey.shade800;
      default:
        return Colors.grey;
    }
  }

  String _absUrl(String url) {
    if (url.startsWith('http')) return url;
    if (url.startsWith('/')) return '$kApiBaseUrl$url';
    return '$kApiBaseUrl/$url';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projectLabel),
        backgroundColor: detail != null ? _statusColor(detail!['status'] ?? 'BLACK') : null,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        bottom: true,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? Center(child: Text('오류: $error'))
                : detail == null
                    ? const Center(child: Text('데이터 없음'))
                    : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final d = detail!;
    final sections = (d['sections'] as List?) ?? [];
    final headerSummary = d['header_summary']?.toString() ?? '';
    final headerMetrics = (d['header_metrics'] as Map?) ?? {};
    final reportDate = d['report_date']?.toString() ?? '';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 헤더
          Card(
            color: _statusColor(d['status'] ?? 'BLACK').withOpacity(0.08),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d['label']?.toString() ?? '',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  if (reportDate.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('보고일자: $reportDate',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                    ),
                  if (headerSummary.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('※ $headerSummary',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    ),
                  ...headerMetrics.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('• ${e.key}: ${e.value}',
                            style: const TextStyle(fontSize: 14)),
                      )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 섹션들
          ...sections.map<Widget>((s) => _buildSection(s as Map<String, dynamic>)),
        ],
      ),
    );
  }

  Widget _buildSection(Map<String, dynamic> s) {
    final title = s['title']?.toString() ?? '';
    final items = (s['items'] as List?) ?? [];
    final notes = (s['notes'] as List?) ?? [];
    final images = (s['image_urls'] as List?) ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 섹션 제목
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 10),
            // items
            ...items.map((it) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(child: Text(it.toString(), style: const TextStyle(fontSize: 14))),
                    ],
                  ),
                )),
            // notes
            ...notes.map((n) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('※ ${n.toString()}',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange.shade900,
                          fontStyle: FontStyle.italic)),
                )),
            // 이미지들
            ...images.map<Widget>((img) => _buildImage(img)),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(dynamic imgData) {
    String url;
    String caption = '';
    if (imgData is Map) {
      url = imgData['url']?.toString() ?? '';
      caption = imgData['caption']?.toString() ?? '';
    } else {
      url = imgData.toString();
    }
    if (url.isEmpty) return const SizedBox.shrink();
    final fullUrl = _absUrl(url);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => Dialog(
                  child: InteractiveViewer(child: Image.network(fullUrl)),
                ),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                fullUrl,
                fit: BoxFit.fitWidth,
                width: double.infinity,
                errorBuilder: (_, __, ___) => Container(
                  height: 120,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F3F5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.broken_image_outlined,
                      size: 32, color: Color(0xFFADB5BD)),
                ),
              ),
            ),
          ),
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(caption,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ),
        ],
      ),
    );
  }
}

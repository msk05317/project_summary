import '../config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';


class ProjectDetailScreen extends StatefulWidget {
  final String projectKey;
  final String projectLabel;
  final String? status;

  const ProjectDetailScreen({
    super.key,
    required this.projectKey,
    required this.projectLabel,
    this.status,
  });

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  Map<String, dynamic>? detail;       // 기존 PPT 카드 (백워드 호환)
  Map<String, dynamic>? noteCard;     // 주간 보고 노트
  String noteReportDate = '';
  String noteDivisionId = '';
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      // 1) 주간 보고 노트 우선 로드
      final noteRes = await http.get(
        Uri.parse('$kApiBaseUrl/notes/by_project?project_key=${Uri.encodeComponent(widget.projectKey)}'),
      );
      Map<String, dynamic>? nc;
      String nd = '';
      String ndiv = '';
      if (noteRes.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(noteRes.bodyBytes));
        if (decoded is Map && decoded['card'] != null) {
          nc = Map<String, dynamic>.from(decoded['card']);
          nd = (decoded['report_date'] ?? '').toString();
          ndiv = (decoded['division_id'] ?? '').toString();
        }
      }

      // 2) 노트 없으면 기존 PPT 카드 폴백
      Map<String, dynamic>? d;
      if (nc == null) {
        final res = await http.get(
          Uri.parse('$kApiBaseUrl/projects/${widget.projectKey}'),
        );
        if (res.statusCode == 200) {
          d = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        }
      }

      setState(() {
        noteCard = nc;
        noteReportDate = nd;
        noteDivisionId = ndiv;
        detail = d;
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
    final headerColor = noteCard != null
        ? Colors.indigo
        : (detail != null ? _statusColor(detail!['status'] ?? 'BLACK') : Colors.grey);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projectLabel),
        backgroundColor: headerColor,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        bottom: true,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? Center(child: Text('오류: $error'))
                : (noteCard != null
                    ? _buildNoteContent()
                    : (detail != null
                        ? _buildLegacyContent()
                        : const Center(child: Text('데이터 없음')))),
      ),
    );
  }

  // ============================== 주간 보고 노트 ==============================
  Widget _buildNoteContent() {
    final c = noteCard!;
    final title = (c['title'] ?? widget.projectLabel).toString();
    final sections = (c['sections'] as List?) ?? [];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 헤더
          Card(
            color: Colors.indigo.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  if (noteReportDate.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('보고일자: $noteReportDate',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...sections.map<Widget>((s) => _buildNoteSection(s as Map<String, dynamic>)),
        ],
      ),
    );
  }

  Widget _buildNoteSection(Map<String, dynamic> s) {
    final title = (s['title'] ?? '').toString();
    final items = (s['items'] as List?) ?? [];
    final secTableData = s['table_data'];   // 섹션 레벨 표 (호환)

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            if (title.isNotEmpty) const SizedBox(height: 10),
            ..._buildItemsWithGroups(items),
            // 섹션 레벨 표 (구버전 호환)
            if (secTableData != null) ...[
              const SizedBox(height: 8),
              _buildTableMini(secTableData as Map<String, dynamic>),
            ],
          ],
        ),
      ),
    );
  }

  // group_id 같은 항목들을 노란 박스로 묶어 렌더
  List<Widget> _buildItemsWithGroups(List items) {
    final widgets = <Widget>[];
    int i = 0;
    while (i < items.length) {
      final raw = items[i];
      final it = (raw is String)
          ? {'type': 'bullet', 'text': raw}
          : (raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{});
      final gid = (it['group_id'] ?? '').toString();

      if (gid.isNotEmpty) {
        // 같은 group_id 연속 구간 모으기
        final groupItems = <dynamic>[];
        int j = i;
        while (j < items.length) {
          final r = items[j];
          final x = (r is String)
              ? {'type': 'bullet', 'text': r}
              : (r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{});
          if ((x['group_id'] ?? '').toString() != gid) break;
          groupItems.add(r);
          j++;
        }

        // 일반 항목 / group_note 분리
        final normals = <dynamic>[];
        final notes = <dynamic>[];
        for (final g in groupItems) {
          final o = (g is String)
              ? {'type': 'bullet', 'text': g}
              : (g is Map ? Map<String, dynamic>.from(g) : <String, dynamic>{});
          if ((o['type'] ?? '').toString() == 'group_note') {
            notes.add(g);
          } else {
            normals.add(g);
          }
        }

        widgets.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border(left: BorderSide(color: Colors.amber.shade700, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...normals.map<Widget>((g) => _buildNoteItem(g)),
              if (notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    padding: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: Colors.amber.shade300,
                          width: 1,
                          style: BorderStyle.solid,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: notes.map<Widget>((g) {
                        final o = (g is String)
                            ? {'text': g}
                            : (g is Map ? Map<String, dynamic>.from(g) : <String, dynamic>{});
                        final text = (o['text'] ?? '').toString();
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('↪ ',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber.shade800)),
                              Expanded(
                                child: Text(text,
                                    style: TextStyle(
                                        fontSize: 13.5,
                                        color: Colors.brown.shade800,
                                        fontStyle: FontStyle.italic)),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
            ],
          ),
        ));
        i = j;
      } else {
        // group_id 없는 항목
        widgets.add(_buildNoteItem(raw));
        i++;
      }
    }
    return widgets;
  }

  Widget _buildNoteItem(dynamic raw) {
    // 문자열도 허용 (구버전)
    if (raw is String) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(child: Text(raw, style: const TextStyle(fontSize: 14))),
          ],
        ),
      );
    }
    if (raw is! Map) return const SizedBox.shrink();
    final it = Map<String, dynamic>.from(raw);
    final type = (it['type'] ?? 'bullet').toString();
    final text = (it['text'] ?? '').toString();

    switch (type) {
      case 'highlight':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('★ ',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.red.shade700)),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.red.shade800)),
              ),
            ],
          ),
        );
      case 'sub':
        return Padding(
          padding: const EdgeInsets.only(left: 24, top: 2, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('→ ', style: TextStyle(color: Colors.grey.shade600)),
              Expanded(
                child: Text(text,
                    style: TextStyle(fontSize: 13.5, color: Colors.grey.shade800)),
              ),
            ],
          ),
        );
      case 'group_note':
        return Padding(
          padding: const EdgeInsets.only(left: 16, top: 4, bottom: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border(left: BorderSide(color: Colors.amber.shade700, width: 3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('↪ ',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.amber.shade800)),
                Expanded(
                  child: Text(text,
                      style: TextStyle(
                          fontSize: 13.5,
                          color: Colors.brown.shade800,
                          fontStyle: FontStyle.italic)),
                ),
              ],
            ),
          ),
        );
      case 'table':
        final tdata = it['table_data'];
        if (tdata is Map) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _buildTableMini(Map<String, dynamic>.from(tdata)),
          );
        }
        return const SizedBox.shrink();
      case 'photo':
        final ref = (it['photo_ref'] ?? '').toString();
        if (ref.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: _buildPhotoMini('/note_photos/$ref'),
        );
      case 'bullet':
      default:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
            ],
          ),
        );
    }
  }

  Widget _buildTableMini(Map<String, dynamic> table) {
    final title = (table['title'] ?? '').toString();
    final headers = (table['headers'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final rows = (table['rows'] as List?) ?? [];
    final previewRows = rows.take(3).toList();
    final hasMore = rows.length > 3;

    return InkWell(
      onTap: () => _openTableFull(table),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.table_chart, size: 16, color: Colors.indigo),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(title.isEmpty ? '표' : title,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                ),
                Icon(Icons.zoom_out_map, size: 14, color: Colors.grey.shade600),
              ],
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 32,
                dataRowMinHeight: 28,
                dataRowMaxHeight: 32,
                columnSpacing: 16,
                horizontalMargin: 4,
                columns: headers
                    .map((h) => DataColumn(
                        label: Text(h,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold))))
                    .toList(),
                rows: previewRows
                    .map<DataRow>((r) => DataRow(
                          cells: (r as List)
                              .map<DataCell>((c) => DataCell(Text(c.toString(),
                                  style: const TextStyle(fontSize: 12))))
                              .toList(),
                        ))
                    .toList(),
              ),
            ),
            if (hasMore)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('… 외 ${rows.length - 3}행 (탭하여 전체 보기)',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ),
          ],
        ),
      ),
    );
  }

  void _openTableFull(Map<String, dynamic> table) {
    final title = (table['title'] ?? '표').toString();
    final headers = (table['headers'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final rows = (table['rows'] as List?) ?? [];
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              Flexible(
                child: InteractiveViewer(
                  constrained: false,
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: DataTable(
                    columns: headers
                        .map((h) => DataColumn(
                            label: Text(h,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold))))
                        .toList(),
                    rows: rows
                        .map<DataRow>((r) => DataRow(
                              cells: (r as List)
                                  .map<DataCell>((c) => DataCell(Text(c.toString())))
                                  .toList(),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoMini(String relPath) {
    final url = _absUrl(relPath);
    return InkWell(
      onTap: () => _openPhotoFull(url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          height: 160,
          width: double.infinity,
          errorBuilder: (_, __, ___) => Container(
            height: 100,
            color: Colors.grey.shade200,
            child: const Center(child: Text('사진 로드 실패')),
          ),
        ),
      ),
    );
  }

  void _openPhotoFull(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(0),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================== 기존 PPT 카드 (백워드 호환) ==============================
  Widget _buildLegacyContent() {
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
          ...sections.map<Widget>((s) => _buildLegacySection(s as Map<String, dynamic>)),
        ],
      ),
    );
  }

  Widget _buildLegacySection(Map<String, dynamic> s) {
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
            ...notes.map((n) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('※ ${n.toString()}',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange.shade900,
                          fontStyle: FontStyle.italic)),
                )),
            ...images.map<Widget>((img) => _buildLegacyImage(img)),
          ],
        ),
      ),
    );
  }

  Widget _buildLegacyImage(dynamic imgData) {
    String url;
    String caption = '';
    if (imgData is String) {
      url = imgData;
    } else if (imgData is Map) {
      url = (imgData['url'] ?? '').toString();
      caption = (imgData['caption'] ?? '').toString();
    } else {
      return const SizedBox.shrink();
    }
    if (url.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _openPhotoFull(_absUrl(url)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(_absUrl(url),
                  fit: BoxFit.cover, width: double.infinity, height: 200,
                  errorBuilder: (_, __, ___) => Container(
                        height: 100,
                        color: Colors.grey.shade200,
                        child: const Center(child: Text('이미지 로드 실패')),
                      )),
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

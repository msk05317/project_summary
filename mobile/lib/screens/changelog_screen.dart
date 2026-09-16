// 변경 내역 — 버전마다 무엇이 달라졌는지.
//
// 전에는 서버가 release_notes 를 한 줄만 들고 있었다. 버전을 올려도 그
// 줄을 안 고치면 옛 노트가 그대로 나갔고, 실제로 2.3.10 이 몇 버전 전의
// 블룸 일 보고 얘기를 띄우고 있었다. 게다가 '2.3.9 와 2.3.10 이 뭐가
// 다른가' 는 어디에도 안 남아서 답할 수가 없었다.
//
// 이제 저장소의 CHANGELOG.md 를 버전별로 쌓고 /app/changelog 로 받는다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../design/design.dart';

class ChangelogEntry {
  final String version;
  final String date;
  final String body;

  const ChangelogEntry(this.version, this.date, this.body);
}

class ChangelogScreen extends StatefulWidget {
  /// 지금 깔려 있는 버전. 그 줄에 '설치됨' 을 붙인다.
  final String installed;

  const ChangelogScreen({super.key, this.installed = ''});

  @override
  State<ChangelogScreen> createState() => _ChangelogScreenState();
}

class _ChangelogScreenState extends State<ChangelogScreen> {
  late Future<List<ChangelogEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<ChangelogEntry>> _fetch() async {
    final res = await http
        .get(Uri.parse('$kApiBaseUrl/app/changelog'))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final d = jsonDecode(utf8.decode(res.bodyBytes));
    final items = (d is Map ? d['items'] as List? : null) ?? const [];
    return items.whereType<Map>().map((e) {
      return ChangelogEntry(
        (e['version'] ?? '').toString(),
        (e['date'] ?? '').toString(),
        (e['body'] ?? '').toString(),
      );
    }).toList();
  }

  /// 설치된 버전과 같은 줄인지. '2.3.10 (33)' 처럼 빌드 번호가 붙어 온다.
  bool _isInstalled(String version) {
    final v = widget.installed.split(' ').first.trim();
    return v.isNotEmpty && v == version.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPage,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('변경 내역',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textMain)),
        iconTheme: const IconThemeData(color: AppColors.textMain),
      ),
      body: FutureBuilder<List<ChangelogEntry>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(strokeWidth: 2));
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('변경 내역을 불러오지 못했습니다\n${snap.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textMute)),
              ),
            );
          }
          final list = snap.data ?? const <ChangelogEntry>[];
          if (list.isEmpty) {
            return const Center(
                child: Text('기록이 없습니다',
                    style: TextStyle(color: AppColors.textHint)));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            itemCount: list.length,
            itemBuilder: (_, i) => _card(list[i]),
          );
        },
      ),
    );
  }

  Widget _card(ChangelogEntry e) {
    final here = _isInstalled(e.version);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: here ? AppColors.summaryInProgress : AppColors.borderDefault),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(e.version,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMain)),
          const SizedBox(width: 8),
          if (here)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.summaryInProgress.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text('설치됨',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.summaryInProgress)),
            ),
          const Spacer(),
          Text(e.date,
              style: const TextStyle(fontSize: 11.5, color: AppColors.textHint)),
        ]),
        const SizedBox(height: 9),
        Text(e.body,
            style: const TextStyle(
                fontSize: 13, height: 1.65, color: AppColors.textSub)),
      ]),
    );
  }
}

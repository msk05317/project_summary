import 'package:flutter/material.dart';
import '../services/notifications_service.dart';
import 'report_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  String? _error;
  List<NotificationItem> _items = [];
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await NotificationsService.list(limit: 100);
      if (!mounted) return;
      setState(() {
        _items = res.items;
        _unreadCount = res.unreadCount;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _markAllRead() async {
    try {
      await NotificationsService.markAllRead();
      await _load();
    } catch (_) {}
  }

  String _fallbackProjectKey(String title) {
    switch (title.trim()) {
      case '챔버':
        return 'chamber';
      case '파워박스':
        return 'powerbox';
      case '메이저모듈':
        return 'major_module';
      case '프레임':
        return 'frame';
      default:
        return 'frame';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'RED':
        return const Color(0xFFDC2626);
      case 'ORANGE':
        return const Color(0xFFEA580C);
      case 'GREEN':
        return const Color(0xFF16A34A);
      case 'BLUE':
        return const Color(0xFF2563EB);
      default:
        return const Color(0xFF6B7280);
    }
  }

  String _statusEmoji(String status) {
    switch (status) {
      case 'RED':
        return '🔴';
      case 'ORANGE':
        return '🟠';
      case 'GREEN':
        return '🟢';
      case 'BLUE':
        return '🔵';
      default:
        return '⚪';
    }
  }

  String _formatTime(String ts) {
    if (ts.length < 16) return ts;
    return '${ts.substring(5, 10).replaceAll('-', '/')} ${ts.substring(11, 16)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('알림${_unreadCount > 0 ? " ($_unreadCount)" : ""}'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF12325F),
        elevation: 1,
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('모두 읽음'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                      const SizedBox(height: 8),
                      Text('알림을 불러오지 못했습니다\n$_error', textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _load, child: const Text('다시 시도')),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_none, size: 56, color: Color(0xFFCBD5E1)),
                          SizedBox(height: 8),
                          Text('알림이 없습니다', style: TextStyle(color: Color(0xFF6B7280))),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: Color(0xFFEEF2F7)),
                        itemBuilder: (context, idx) {
                          final it = _items[idx];
                          final bgColor =
                              it.read ? Colors.white : const Color(0xFFF0F7FF);
                          return Container(
                            color: bgColor,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              leading: Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _statusColor(it.newStatus).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _statusEmoji(it.newStatus),
                                  style: const TextStyle(fontSize: 20),
                                ),
                              ),
                              title: Text(
                                it.title,
                                style: TextStyle(
                                  fontWeight:
                                      it.read ? FontWeight.w500 : FontWeight.w700,
                                  color: const Color(0xFF12325F),
                                  fontSize: 15,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (it.triggerText.isNotEmpty)
                                      Text(
                                        it.triggerText,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF334155)),
                                      ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        if (it.ddayLabel.isNotEmpty) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: _statusColor(it.newStatus)
                                                    .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              it.ddayLabel,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color:
                                                    _statusColor(it.newStatus),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        Text(
                                          _formatTime(it.ts),
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF94A3B8)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              onTap: () async {
                                try {
                                  await NotificationsService.markRead(it.id);
                                } catch (_) {}
                                if (!context.mounted) return;

                                final key = it.projectKey.isNotEmpty
                                    ? it.projectKey
                                    : _fallbackProjectKey(it.title);

                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ReportDetailScreen(projectKey: key),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/weekly_revenue.dart';

Future<WeeklyRevenue?> fetchWeeklyRevenue(String projectKey, {String? month}) async {
  final m = month ?? DateTime.now().toIso8601String().substring(0, 7);
  final uri = Uri.parse('$kApiBaseUrl/projects/$projectKey/weekly-revenue?month=$m');
  final res = await http.get(uri);
  if (res.statusCode != 200) return null;
  final j = jsonDecode(utf8.decode(res.bodyBytes));
  if (j['groups'] == null) return null;
  return WeeklyRevenue.fromJson(j);
}

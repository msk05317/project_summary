// 앱 전체 숫자 표기 단일 진입점.
//
// 지금까지 금액·수량·퍼센트가 화면마다 제각각이었다.
//  - 천단위 구분: weekly_revenue_card 는 intl, model_list_screen 은 직접 구현, 나머지는 생 정수
//  - 퍼센트 소수점: 0자리/1자리/2자리 혼재
// 경영진이 자릿수를 세지 않도록 여기 한 곳에서만 포맷한다.
import 'package:intl/intl.dart';

class Fmt {
  Fmt._();

  static final NumberFormat _int = NumberFormat('#,##0');
  static final NumberFormat _dec1 = NumberFormat('#,##0.0');

  /// 12345 → '12,345'
  static String qty(num? v) => v == null ? '-' : _int.format(v.round());

  /// 1520796 → '\$1,520,796'
  static String money(num? v) => v == null ? '-' : '\$${_int.format(v.round())}';

  /// 큰 금액 축약. 1520796 → '\$1.52M', 820000 → '\$820K'
  /// 경영진 화면의 KPI 숫자는 자릿수보다 크기 감이 중요하다.
  static String moneyShort(num? v) {
    if (v == null) return '-';
    final n = v.abs();
    final sign = v < 0 ? '-' : '';
    if (n >= 1000000) {
      final m = n / 1000000;
      return '$sign\$${m >= 100 ? m.toStringAsFixed(0) : m.toStringAsFixed(2)}M';
    }
    if (n >= 1000) {
      final k = n / 1000;
      return '$sign\$${k >= 100 ? k.toStringAsFixed(0) : _dec1.format(k)}K';
    }
    return '$sign\$${_int.format(n.round())}';
  }

  /// 72 → '72%', null → '-'
  static String pct(num? v) => v == null ? '-' : '${v.round()}%';

  /// '2026-08' → '8월'
  static String monthShort(String? ym) {
    if (ym == null || !ym.contains('-')) return '';
    final m = int.tryParse(ym.split('-')[1]);
    return m == null ? '' : '$m월';
  }

  /// 계획 대비 달성률(%). 계획이 0이면 null.
  static int? rate(num actual, num plan) =>
      plan <= 0 ? null : (actual * 100 / plan).round();
}

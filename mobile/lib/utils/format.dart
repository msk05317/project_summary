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

  /// 12345 → '12,345'
  static String qty(num? v) => v == null ? '-' : _int.format(v.round());

  /// 1520796 → '\$1,520,796'
  static String money(num? v) => v == null ? '-' : '\$${_int.format(v.round())}';

  /// 큰 금액 축약 — 한국식 만/억 단위.
  /// K·M 이 한눈에 안 들어온다는 피드백이 있어 만·억으로 바꿨다.
  ///   7120000 → '$712만',  164566 → '$16.5만',  74707 → '$74,707',  120000000 → '$1.2억'
  /// 10만 미만은 축약하지 않고 정확한 금액을 그대로 보여준다 (자릿수가 짧아 그게 더 명확).
  static String moneyShort(num? v) {
    if (v == null) return '-';
    final n = v.abs();
    final sign = v < 0 ? '-' : '';
    if (n >= 100000000) {
      return '$sign\$${_unit(n / 100000000)}억';
    }
    if (n >= 100000) {
      return '$sign\$${_unit(n / 10000)}만';
    }
    return '$sign\$${_int.format(n.round())}';
  }

  /// 만/억 앞자리. 100 이상은 소수점 없이, 그 외는 한 자리.
  /// '10.0만' 처럼 의미 없는 .0 은 떼고, 99.99 → '100' 으로 올려서 '100.0만' 을 막는다.
  static String _unit(double x) {
    final t = x >= 100 ? x.toStringAsFixed(0) : x.toStringAsFixed(1);
    return t.endsWith('.0') ? t.substring(0, t.length - 2) : t;
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

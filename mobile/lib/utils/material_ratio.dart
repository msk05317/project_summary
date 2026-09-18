// 재료비율 한 가지 규칙.
//
// 목록(판가·재료비)과 상세가 서로 다른 기준으로 색을 칠하면, 목록에서
// 빨간 모델을 눌러 들어갔더니 남색으로 적혀 있는 일이 생긴다.
// 구간과 색은 여기서만 정한다.
import 'package:flutter/material.dart';

/// 재료비율 구간.
///   high  90% 이상 — 남는 게 없다
///   mid   80% 대   — 위험선
///   low   80% 미만
///   none  판가가 없어 계산이 안 된다
enum RatioBand { all, high, mid, low, none }

const Map<RatioBand, String> kRatioBandLabel = {
  RatioBand.all: '전체',
  RatioBand.high: '90% 이상',
  RatioBand.mid: '80%대',
  RatioBand.low: '80% 미만',
  RatioBand.none: '판가 미등록',
};

const Map<RatioBand, Color> kRatioBandColor = {
  RatioBand.all: Color(0xFF0E2841),
  RatioBand.high: Color(0xFFDC2626),
  RatioBand.mid: Color(0xFFEA580C),
  RatioBand.low: Color(0xFF059669),
  RatioBand.none: Color(0xFF9CA3AF),
};

/// .toInt() 로 자르면 $0.7 부품이 0 이 되고 재료비율이 0.0% 로 뜬다.
/// 센트를 살린다.
double? ratioOf(Map m) {
  final price = (m['price'] as num?)?.toDouble() ?? 0;
  final mcost = (m['material_cost'] as num?)?.toDouble() ?? 0;
  return price > 0 ? (mcost / price * 100) : null;
}

RatioBand bandOf(double? r) {
  if (r == null) return RatioBand.none;
  if (r >= 90) return RatioBand.high;
  if (r >= 80) return RatioBand.mid;
  return RatioBand.low;
}

/// 숫자에 칠하는 색. 80% 대는 주황, 90% 이상은 빨강.
/// 그 아래는 강조하지 않는다 — 정상인 것까지 색을 주면 위험한 게 안 보인다.
Color ratioColor(double? r) {
  switch (bandOf(r)) {
    case RatioBand.high:
      return const Color(0xFFDC2626);
    case RatioBand.mid:
      return const Color(0xFFEA580C);
    case RatioBand.none:
      return const Color(0xFF9CA3AF);
    default:
      return const Color(0xFF0F2C59);
  }
}

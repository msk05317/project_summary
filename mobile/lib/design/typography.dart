import 'package:flutter/material.dart';
import 'colors.dart';

/// 앱 전역 타이포그래피
///
/// 4단계만 사용 (간단하게):
/// - h1: 화면 제목
/// - h2: 카드 제목
/// - body: 본문
/// - caption: 보조 텍스트
class AppText {
  AppText._();

  static const TextStyle h1 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: AppColors.textMain,
    height: 1.3,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: AppColors.textMain,
    height: 1.3,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textMain,
    height: 1.4,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppColors.textMain,
    height: 1.4,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textMute,
    height: 1.4,
  );

  static const TextStyle captionStrong = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.textSub,
    height: 1.4,
  );
}

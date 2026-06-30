import 'package:flutter/material.dart';

import '../../design/design.dart';

class PhotoCard extends StatelessWidget {
  // 백엔드가 내려주는 photo_ref. 예) 'semiconductor/xls_2026-06-16_xxxx.png'
  final String photoRef;

  // 이미지 위에 같이 보여줄 파일명/제목. 예) '프레임.xlsx'
  final String? fileName;

  // 빌드 시점에 --dart-define=API_BASE_URL=... 으로 주입된 값.
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://projectsummary-production.up.railway.app',
  );

  const PhotoCard({
    super.key,
    required this.photoRef,
    this.fileName,
  });

  String get _imageUrl => '$_baseUrl/note_photos/$photoRef';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.x4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.reportCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((fileName ?? '').isNotEmpty) ...[
            Text(
              fileName!,
              style: AppText.caption.copyWith(color: AppColors.reportBody),
            ),
            const SizedBox(height: AppSpacing.x3),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              _imageUrl,
              fit: BoxFit.contain,
              // 로딩 중에는 박스 형태 유지를 위해 회색 톤 placeholder
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  height: 140,
                  width: double.infinity,
                  color: const Color(0xFFF8FAFC),
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                );
              },
              // 실패 시 안내 placeholder
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  height: 140,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    border: Border.all(color: AppColors.reportCardBorder),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '이미지를 불러오지 못했어요',
                    style: AppText.caption.copyWith(color: AppColors.reportBody),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

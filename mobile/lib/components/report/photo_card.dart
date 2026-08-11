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
    defaultValue: 'https://project-summary-mkoo.fly.dev',
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
          if ((fileName ?? '').isNotEmpty && !_isFileNameOnly(fileName!)) ...[
            Text(
              fileName!,
              style: AppText.caption.copyWith(color: AppColors.reportBody),
            ),
            const SizedBox(height: AppSpacing.x3),
          ],
          // 이미지: 탭하면 풀스크린 줌 뷰어 열림
          GestureDetector(
            onTap: () => _openFullscreen(context),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Hero(
                tag: 'photo_$photoRef',
                child: Image.network(
                  _imageUrl,
                  fit: BoxFit.contain,
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
            ),
          ),
        ],
      ),
    );
  }

  void _openFullscreen(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => _FullscreenPhoto(
          imageUrl: _imageUrl,
          heroTag: 'photo_$photoRef',
          title: fileName,
        ),
      ),
    );
  }

  bool _isFileNameOnly(String name) {
    return RegExp(r'\.(xlsx|xls|pptx|ppt|docx|doc|pdf|png|jpg|jpeg|gif|webp)$',
        caseSensitive: false).hasMatch(name.trim());
  }
}


/// 풀스크린 이미지 뷰어. 핀치 줌 + 팬 (InteractiveViewer).
class _FullscreenPhoto extends StatelessWidget {
  final String imageUrl;
  final String heroTag;
  final String? title;

  const _FullscreenPhoto({
    required this.imageUrl,
    required this.heroTag,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: (title != null && title!.isNotEmpty)
            ? Text(
                title!,
                style: const TextStyle(fontSize: 14, color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              )
            : null,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Hero(
        tag: heroTag,
        child: InteractiveViewer(
          minScale: 1.0,
          maxScale: 6.0,
          constrained: false,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          child: SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child: Text(
                    '이미지를 불러오지 못했어요',
                    style: TextStyle(color: Colors.white70),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

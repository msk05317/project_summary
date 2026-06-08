// API 서버 주소 (빌드 시점에 --dart-define으로 주입)
//
// 로컬 개발:
//   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
//
// Railway 프로덕션:
//   flutter run --dart-define=API_BASE_URL=https://projectsummary-production.up.railway.app
//
// APK 빌드:
//   flutter build apk --release --dart-define=API_BASE_URL=https://projectsummary-production.up.railway.app

const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://projectsummary-production.up.railway.app',
);

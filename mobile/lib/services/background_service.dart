import 'package:workmanager/workmanager.dart';
import '../services/dashboard_service.dart';
import '../services/divisions_service.dart';

const String kBgRefreshTask = 'bg_data_refresh';

/// WorkManager 콜백: 반드시 top-level 이거나 @pragma('vm:entry-point') 필요
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == kBgRefreshTask) {
      try {
        await Future.wait([
          DashboardService.fetchCards(),
          DivisionsService.fetchAll(),
        ]);
      } catch (_) {
        return Future.value(false);
      }
    }
    return Future.value(true);
  });
}

class BackgroundService {
  BackgroundService._();
  static final BackgroundService instance = BackgroundService._();

  Future<void> init() async {
    await Workmanager().initialize(callbackDispatcher);
  }

  Future<void> registerPeriodic(int minutes) async {
    await Workmanager().cancelByUniqueName(kBgRefreshTask);
    if (minutes <= 0) return;
    await Workmanager().registerPeriodicTask(
      kBgRefreshTask,
      kBgRefreshTask,
      frequency: Duration(minutes: minutes),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(kBgRefreshTask);
  }
}

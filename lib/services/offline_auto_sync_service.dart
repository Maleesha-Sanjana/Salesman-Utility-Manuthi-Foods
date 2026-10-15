import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'api_service.dart';
import 'offline_sync_service.dart';

typedef AutoSyncCompletedCallback = void Function(
  OfflineSyncAllResult result,
  bool manual,
);

/// Watches for server availability and uploads queued offline documents.
class OfflineAutoSyncService {
  OfflineAutoSyncService._();

  static final OfflineAutoSyncService instance = OfflineAutoSyncService._();

  static const Duration _pollInterval = Duration(seconds: 10);
  static const Duration _autoSyncCooldown = Duration(seconds: 15);

  Timer? _pollTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _started = false;
  bool _isSyncing = false;
  DateTime? _lastAutoSyncAttempt;
  AutoSyncCompletedCallback? onSyncCompleted;

  final ValueNotifier<int> pendingCount = ValueNotifier(0);
  final ValueNotifier<bool> isSyncing = ValueNotifier(false);

  void start() {
    if (_started) return;
    _started = true;
    unawaited(refreshPendingCount());
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(tryAutoSync());
    });
    
    // Listen for network changes to trigger immediate sync when coming online
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.isNotEmpty && !results.contains(ConnectivityResult.none)) {
        debugPrint('🌐 Network detected, scheduling auto-sync attempt...');
        scheduleSyncAttempt();
      }
    });

    unawaited(tryAutoSync());
  }

  void stop() {
    _started = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  void scheduleSyncAttempt() {
    unawaited(refreshPendingCount());
    unawaited(tryAutoSync());
  }

  Future<void> refreshPendingCount() async {
    pendingCount.value = await OfflineSyncService.getTotalPendingCount();
  }

  Future<OfflineSyncAllResult?> syncAll({required bool manual}) async {
    if (_isSyncing) return null;

    if (!manual) {
      final now = DateTime.now();
      if (_lastAutoSyncAttempt != null &&
          now.difference(_lastAutoSyncAttempt!) < _autoSyncCooldown) {
        return null;
      }
    }

    _isSyncing = true;
    isSyncing.value = true;

    try {
      await refreshPendingCount();
      if (pendingCount.value == 0) {
        return manual
            ? const OfflineSyncAllResult(
                totalSynced: 0,
                totalFailed: 0,
                totalRemaining: 0,
                byType: <String, OfflineSyncResult>{},
              )
            : null;
      }

      final serverAvailable = await ApiService.checkHealth();
      if (!serverAvailable) {
        return manual
            ? OfflineSyncAllResult(
                totalSynced: 0,
                totalFailed: pendingCount.value,
                totalRemaining: pendingCount.value,
                message: 'Server is not reachable',
                byType: <String, OfflineSyncResult>{},
              )
            : null;
      }

      debugPrint(
        '🔄 [AutoSync] Starting sync (${manual ? "manual" : "auto"}, ${pendingCount.value} pending)...',
      );
      _lastAutoSyncAttempt = DateTime.now();
      final result = await OfflineSyncService.syncAllPending();
      await refreshPendingCount();
      debugPrint(
        '✅ [AutoSync] Finished: ${result.totalSynced} synced, ${result.totalFailed} failed, ${result.totalRemaining} remaining',
      );
      onSyncCompleted?.call(result, manual);
      return result;
    } finally {
      _isSyncing = false;
      isSyncing.value = false;
    }
  }

  Future<OfflineSyncAllResult?> tryAutoSync() async {
    if (!_started) return null;
    return syncAll(manual: false);
  }
}

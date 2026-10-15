const fs = require('fs');
let code = fs.readFileSync('lib/services/background_location_service.dart', 'utf8');

const newCode = `
int _lastPendingCount = 0;
Timer? _notificationPollingTimer;
final FlutterLocalNotificationsPlugin _localNotifPlugin = FlutterLocalNotificationsPlugin();

Future<void> _showSalesOrderNotification(int count) async {
  const androidDetails = AndroidNotificationDetails(
    'sales_order_channel',
    'Sales Orders',
    channelDescription: 'Notifications for pending sales orders',
    importance: Importance.max,
    priority: Priority.high,
  );
  const notificationDetails = NotificationDetails(android: androidDetails);
  
  await _localNotifPlugin.show(
    999,
    'New Sales Order',
    'You have $count pending sales orders awaiting approval.',
    notificationDetails,
  );
}

void _startNotificationPolling() {
  _notificationPollingTimer?.cancel();
  _notificationPollingTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
    try {
      final count = await ApiService.getPendingSalesOrdersCount();
      if (count > _lastPendingCount) {
        _lastPendingCount = count;
        await _showSalesOrderNotification(count);
      } else if (count < _lastPendingCount) {
        _lastPendingCount = count; // reset down if orders were approved
      }
    } catch (e) {
      debugPrint('Error polling notifications: $e');
    }
  });
}
`;

// Insert the code around line 200 before `Future<void> _stopBackgroundTracking`
code = code.replace('Future<void> _stopBackgroundTracking', newCode + '\nFuture<void> _stopBackgroundTracking');

// Hook the polling in `_startBackgroundTracking`
code = code.replace(
  `_backgroundPositionStream =`, 
  `_startNotificationPolling();\n  _backgroundPositionStream =`
);

// Cancel the polling in `_stopBackgroundTracking`
code = code.replace(
  `_backgroundLocationTimer?.cancel();`,
  `_backgroundLocationTimer?.cancel();\n  _notificationPollingTimer?.cancel();`
);

fs.writeFileSync('lib/services/background_location_service.dart', code);
console.log('Patched');

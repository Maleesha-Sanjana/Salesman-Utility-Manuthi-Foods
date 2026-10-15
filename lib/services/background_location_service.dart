import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class BackgroundLocationService {
  static const String _notificationChannelId = 'location_tracking_channel';
  static const String _notificationChannelName = 'Location Tracking';
  static const int _notificationId = 888;

  /// Initialize background service
  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _notificationChannelId,
      _notificationChannelName,
      description: 'Keeps salesman location active for admin monitoring',
      importance: Importance.low,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: _notificationChannelId,
        initialNotificationTitle: 'Sales Man Utility',
        initialNotificationContent: 'Location tracking is active',
        foregroundServiceNotificationId: _notificationId,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  /// Start background location tracking
  static Future<void> startLocationTracking(
    String userCode,
    String userName,
  ) async {
    debugPrint('🌍 Starting background location tracking for: $userName');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tracking_user_code', userCode);
    await prefs.setString('tracking_user_name', userName);
    await prefs.setBool('location_tracking_active', true);

    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
    }
    service.invoke('startLocationTracking');
  }

  /// Stop background location tracking
  static Future<void> stopLocationTracking() async {
    debugPrint('🛑 Stopping background location tracking');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('location_tracking_active', false);

    final service = FlutterBackgroundService();
    service.invoke('stopLocationTracking');
  }

  static Future<bool> isTrackingActive() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('location_tracking_active') ?? false;
  }
}

Timer? _backgroundLocationTimer;
StreamSubscription<Position>? _backgroundPositionStream;

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  service.on('startLocationTracking').listen((event) async {
    await _startBackgroundTracking(service);
  });

  service.on('stopLocationTracking').listen((event) async {
    await _stopBackgroundTracking(service);
  });

  final prefs = await SharedPreferences.getInstance();
  final wasTracking = prefs.getBool('location_tracking_active') ?? false;
  if (wasTracking) {
    await _startBackgroundTracking(service);
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

Future<void> _startBackgroundTracking(ServiceInstance service) async {
  await _stopBackgroundTracking(service);

  final prefs = await SharedPreferences.getInstance();
  final userCode = prefs.getString('tracking_user_code');
  final userName = prefs.getString('tracking_user_name');

  if (userCode == null || userName == null) {
    debugPrint('❌ Background service: No user info found');
    return;
  }

  if (!await _ensureBackgroundPermission()) {
    debugPrint('❌ Background service: Background location permission missing');
    return;
  }

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: 'Sales Man Utility - Location Tracking',
      content: 'Tracking location for $userName',
    );
  }

  await _sendBackgroundLocation(userCode, userName, service);

  late LocationSettings locationSettings;

  if (defaultTargetPlatform == TargetPlatform.iOS) {
    locationSettings = AppleSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 100,
      pauseLocationUpdatesAutomatically: false,
      allowBackgroundLocationUpdates: true,
      showBackgroundLocationIndicator: true,
    );
  } else {
    locationSettings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 100,
    );
  }

  _startNotificationPolling();
  _backgroundPositionStream =
      Geolocator.getPositionStream(locationSettings: locationSettings).listen(
        (position) async {
          final isActive = prefs.getBool('location_tracking_active') ?? false;
          if (!isActive) return;

          await _sendLocationToServer(userCode, userName, position);

          if (service is AndroidServiceInstance) {
            final now = DateTime.now();
            service.setForegroundNotificationInfo(
              title: 'Sales Man Utility - Location Tracking',
              content:
                  'Last update: ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
            );
          }
        },
        onError: (error) {
          debugPrint('❌ Background position stream error: $error');
        },
      );
}

int _lastPendingCount = 0;
Timer? _notificationPollingTimer;
final FlutterLocalNotificationsPlugin _localNotifPlugin =
    FlutterLocalNotificationsPlugin();

bool _isNotifInitialized = false;
final String _salesOrderChannelId = 'sales_order_channel_final_1';

Future<void> _initLocalNotifications() async {
  if (_isNotifInitialized) return;
  debugPrint('🔔 Initializing Local Notifications Plugin...');
  const initializationSettingsAndroid = AndroidInitializationSettings(
    '@mipmap/ic_launcher',
  );
  const initializationSettingsIOS = DarwinInitializationSettings(
    requestSoundPermission: true,
    requestBadgePermission: true,
    requestAlertPermission: true,
  );
  const initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );
  try {
    final result = await _localNotifPlugin.initialize(initializationSettings);
    
    // Explicitly create the channel for Android to guarantee sound plays
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _localNotifPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      final AndroidNotificationChannel salesOrderChannel = AndroidNotificationChannel(
        _salesOrderChannelId,
        'Sales Orders',
        description: 'Notifications for pending sales orders',
        importance: Importance.max,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('notification'),
        enableVibration: true,
      );
      await androidImplementation.createNotificationChannel(salesOrderChannel);
    }
    
    debugPrint('🔔 Local Notifications Plugin Initialized: $result');
    _isNotifInitialized = true;
  } catch (e) {
    debugPrint('❌ Error initializing Local Notifications: $e');
  }
}

Future<void> _showSalesOrderNotification(int count) async {
  debugPrint(
    '🔔 Attempting to show Sales Order Notification (Count: $count)...',
  );
  final androidDetails = AndroidNotificationDetails(
    _salesOrderChannelId,
    'Sales Orders',
    channelDescription: 'Notifications for pending sales orders',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    sound: const RawResourceAndroidNotificationSound('notification'),
    enableVibration: true,
  );
  const darwinDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
    sound: 'notification.wav',
  );
  final notificationDetails = NotificationDetails(
    android: androidDetails,
    iOS: darwinDetails,
  );

  try {
    await _localNotifPlugin.show(
      999,
      'New Sales Order',
      'You have $count pending sales orders awaiting approval.',
      notificationDetails,
    );
    debugPrint('✅ Successfully triggered local notification display');
  } catch (e) {
    debugPrint('❌ Failed to show local notification: $e');
  }
}

void _startNotificationPolling() {
  debugPrint('🔄 Starting Notification Polling Timer (5m)...');
  _notificationPollingTimer?.cancel();
  _notificationPollingTimer = Timer.periodic(const Duration(minutes: 5), (
    _,
  ) async {
    try {
      debugPrint('⏱️ Polling Notification API...');
      await _initLocalNotifications();
      final count = await ApiService.getPendingSalesOrdersCount();
      debugPrint(
        '📊 API returned Pending Count: $count | Previous Count: $_lastPendingCount',
      );
      if (count > _lastPendingCount) {
        _lastPendingCount = count;
        await _showSalesOrderNotification(count);
      } else if (count < _lastPendingCount) {
        _lastPendingCount = count; // reset down if orders were approved
      }
    } catch (e) {
      debugPrint('❌ Error polling notifications: $e');
    }
  });
}

Future<void> _stopBackgroundTracking(ServiceInstance service) async {
  _backgroundLocationTimer?.cancel();
  _notificationPollingTimer?.cancel();
  _backgroundLocationTimer = null;
  await _backgroundPositionStream?.cancel();
  _backgroundPositionStream = null;

  service.stopSelf();
}

Future<bool> _ensureBackgroundPermission() async {
  if (kIsWeb) return true;

  if (Platform.isAndroid) {
    final notificationStatus = await Permission.notification.status;
    if (!notificationStatus.isGranted) {
      await Permission.notification.request();
    }

    var status = await Permission.locationWhenInUse.status;
    if (!status.isGranted) {
      status = await Permission.locationWhenInUse.request();
    }
    if (!status.isGranted) return false;

    // Try to ask for 'Always' permission. Android 11+ might ignore this,
    // but we don't care about the result because 'locationWhenInUse'
    // is fully sufficient for a Foreground Service to track location.
    final alwaysStatus = await Permission.locationAlways.status;
    if (!alwaysStatus.isGranted) {
      await Permission.locationAlways.request();
    }

    // Return TRUE because 'WhenInUse' is granted and that is enough.
    return true;
  }

  final permission = await Geolocator.checkPermission();
  return permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;
}

Future<void> _sendBackgroundLocation(
  String userCode,
  String userName,
  ServiceInstance service,
) async {
  const int maxRetries = 3;
  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 30),
        forceAndroidLocationManager: !kIsWeb && Platform.isAndroid,
      );

      await _sendLocationToServer(userCode, userName, position);

      if (service is AndroidServiceInstance) {
        final now = DateTime.now();
        service.setForegroundNotificationInfo(
          title: 'Sales Man Utility - Location Tracking',
          content:
              'Last update: ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
        );
      }

      debugPrint(
        '📍 Background location sent: ${position.latitude}, ${position.longitude}',
      );
      break; // Success, exit retry loop
    } catch (e) {
      debugPrint(
        '❌ Background location error (Attempt $attempt/$maxRetries): $e',
      );
      if (attempt < maxRetries) {
        await Future.delayed(const Duration(seconds: 5));
      }
    }
  }
}

Future<void> _sendLocationToServer(
  String userCode,
  String userName,
  Position position,
) async {
  try {
    final response = await ApiService.withFailover(() {
      return http
          .post(
            Uri.parse('${ApiService.baseUrl}/location/update'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'userCode': userCode,
              'userName': userName,
              'latitude': position.latitude,
              'longitude': position.longitude,
              'accuracy': position.accuracy,
              'timestamp': DateTime.now().toIso8601String(),
              'speed': position.speed,
              'heading': position.heading,
            }),
          )
          .timeout(const Duration(seconds: 10));
    });

    if (response.statusCode != 200) {
      debugPrint('❌ Background location failed: ${response.statusCode}');
    }
  } catch (e) {
    debugPrint('❌ Background location error: $e');
  }
}

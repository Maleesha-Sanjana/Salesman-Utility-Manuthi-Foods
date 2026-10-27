// ignore_for_file: unused_element

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../models/salesman.dart';

class ApiService {
  static dynamic _decodeJson(String source) => json.decode(source);
  // ---------------------------------------------------------------------------
  // API host — switch between local DEV and production:
  //
  // LOCAL DEV (simulator / Mac backend): uncomment the localhost pair below
  // and comment out the production pair.
  //
  static const String primaryBaseUrl = 'http://localhost:3000/api';
  static const String fallbackBaseUrl = 'http://localhost:3000/api';
  //
  // PRODUCTION (static IP first, then LAN fallback):
  // ---------------------------------------------------------------------------

  /// Public / static IP — tried first.
  //static const String primaryBaseUrl =
  //'http://38.247.130.159:3000/api'; //Manuthi Foods

  /// LAN fallback — used when primary is unreachable.
  //static const String fallbackBaseUrl =
  //'http://38.247.130.159:3000/api'; //Manuthi Foods

  static const String _offlineProductsKey = 'offline_products_no_images';
  static const String _cachedCustomersKey = 'cached_customers_list';
  static const Duration _memoryCacheTtl = Duration(minutes: 10);
  static const Duration _connectTimeout = Duration(seconds: 8);

  static String _activeBaseUrl = primaryBaseUrl;
  static bool _hostProbeDone = false;

  /// Active API base (switches to [fallbackBaseUrl] after connection failures).
  static String get baseUrl => _activeBaseUrl;

  static bool get isUsingFallback => _activeBaseUrl == fallbackBaseUrl;

  static void resetApiHostToPrimary() {
    _activeBaseUrl = primaryBaseUrl;
    _hostProbeDone = false;
  }

  static bool _isConnectionFailure(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('clientexception') ||
        text.contains('connection refused') ||
        text.contains('connection reset') ||
        text.contains('network is unreachable') ||
        text.contains('failed host lookup') ||
        text.contains('timed out') ||
        text.contains('timeout') ||
        text.contains('os error') ||
        error is TimeoutException;
  }

  /// Probe primary, then fallback. Call before login / when network may change.
  static Future<String> ensureApiHost({bool force = false}) async {
    if (_hostProbeDone && !force) return _activeBaseUrl;

    for (final candidate in [primaryBaseUrl, fallbackBaseUrl]) {
      try {
        final response = await http
            .get(Uri.parse('$candidate/health'))
            .timeout(_connectTimeout);
        if (response.statusCode == 200) {
          _activeBaseUrl = candidate;
          _hostProbeDone = true;
          debugPrint('✅ API host ready: $_activeBaseUrl');
          return _activeBaseUrl;
        }
      } catch (e) {
        debugPrint('⚠️ API host unreachable ($candidate): $e');
      }
    }

    // Prefer fallback as last default if both health checks fail.
    _activeBaseUrl = fallbackBaseUrl;
    _hostProbeDone = true;
    debugPrint('⚠️ API health checks failed; defaulting to $_activeBaseUrl');
    return _activeBaseUrl;
  }

  static void _activateFallback(Object error) {
    debugPrint('⚠️ Primary API failed ($_activeBaseUrl): $error');
    _activeBaseUrl = fallbackBaseUrl;
    _hostProbeDone = true;
    debugPrint('🔄 Switching API host to $_activeBaseUrl');
  }

  /// Runs [action] on the current host; on connection errors, retries once on fallback.
  static Future<T> withFailover<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e, st) {
      if (!_isConnectionFailure(e) || _activeBaseUrl == fallbackBaseUrl) {
        Error.throwWithStackTrace(e, st);
      }
      _activateFallback(e);
      return await action();
    }
  }

  static Future<http.Response> _httpGet(
    String path, {
    Duration? timeout,
    Map<String, String>? headers,
  }) {
    return withFailover(() {
      final future = http.get(Uri.parse('$baseUrl$path'), headers: headers);
      return future.timeout(timeout ?? _connectTimeout);
    });
  }

  static Future<http.Response> _httpPost(
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) {
    return withFailover(() {
      final future = http.post(
        Uri.parse('$baseUrl$path'),
        headers: headers,
        body: body,
      );
      return future.timeout(timeout ?? _connectTimeout);
    });
  }

  static Future<http.Response> _httpPut(
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) {
    return withFailover(() {
      final future = http.put(
        Uri.parse('$baseUrl$path'),
        headers: headers,
        body: body,
      );
      return future.timeout(timeout ?? _connectTimeout);
    });
  }

  static Future<http.Response> _httpDelete(
    String path, {
    Map<String, String>? headers,
    Duration? timeout,
  }) {
    return withFailover(() {
      final future = http.delete(Uri.parse('$baseUrl$path'), headers: headers);
      return future.timeout(timeout ?? _connectTimeout);
    });
  }

  /// Rebuilds the URI from the active base on each attempt (needed for failover).
  static Future<http.Response> _httpRequest(
    Future<http.Response> Function(String base) request, {
    Duration? timeout,
  }) {
    return withFailover(() {
      return request(baseUrl).timeout(timeout ?? _connectTimeout);
    });
  }

  static List<Map<String, dynamic>>? _memoryCustomerCache;
  static String? _memoryCustomerCacheKey;
  static DateTime? _memoryCustomerCacheAt;
  static List<Map<String, dynamic>>? _memoryProductCache;
  static DateTime? _memoryProductCacheAt;
  static Future<List<Map<String, dynamic>>>? _inflightCustomers;
  static Future<List<Map<String, dynamic>>>? _inflightProducts;

  static bool _isCacheFresh(DateTime? cachedAt) {
    if (cachedAt == null) return false;
    return DateTime.now().difference(cachedAt) < _memoryCacheTtl;
  }

  static void invalidateCustomerCache() {
    _memoryCustomerCache = null;
    _memoryCustomerCacheKey = null;
    _memoryCustomerCacheAt = null;
  }

  static void invalidateProductCache() {
    _memoryProductCache = null;
    _memoryProductCacheAt = null;
  }

  // Helper method to handle HTTP responses

  // ==================== PRODUCTS (for invoice) ====================

  // ==================== AUTHENTICATION ====================

  static Future<Map<String, dynamic>> authenticateSalesman(
    String salesmanCode,
    String password,
  ) async {
    try {
      await ensureApiHost();
      final response = await _httpPost(
        '/auth/login',
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'salesmanCode': salesmanCode, 'password': password}),
      );

      if (response.statusCode == 200) {
        return await compute<String, dynamic>(_decodeJson, response.body);
      } else {
        final error = await compute<String, dynamic>(
          _decodeJson,
          response.body,
        );
        throw Exception(error['message'] ?? 'Authentication failed');
      }
    } catch (e) {
      debugPrint('Error authenticating salesman: $e');
      rethrow;
    }
  }

  // Password-only authentication

  static Future<Map<String, dynamic>> authenticateWithPassword(
    String password,
  ) async {
    try {
      await ensureApiHost();
      final response = await _httpPost(
        '/auth/login-password',
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'password': password}),
      );

      if (response.statusCode == 200) {
        return await compute<String, dynamic>(_decodeJson, response.body);
      } else {
        final error = await compute<String, dynamic>(
          _decodeJson,
          response.body,
        );
        throw Exception(error['message'] ?? 'Authentication failed');
      }
    } catch (e) {
      debugPrint('Error authenticating with password: $e');
      rethrow;
    }
  }

  static Future<void> logout(String salesmanCode) async {
    try {
      await ensureApiHost();
      await _httpPost(
        '/auth/logout',
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'salesmanCode': salesmanCode}),
      );
    } catch (e) {
      debugPrint('Error logging out salesman: $e');
    }
  }

  static Future<void> logoutAllUsers() async {
    try {
      await ensureApiHost();
      await _httpPost('/auth/logout-all');
    } catch (e) {
      debugPrint('Error logging out all users: $e');
    }
  }

  static Future<void> logoutAllSalesmans() async {
    try {
      await ensureApiHost();
      await _httpPost('/auth/logout-all-salesmans');
    } catch (e) {
      debugPrint('Error logging out all salesmans: $e');
    }
  }

  static Future<void> confirmLogin(String salesmanCode) async {
    try {
      await ensureApiHost();
      await _httpPost(
        '/auth/confirm-login',
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'salesmanCode': salesmanCode}),
      );
    } catch (e) {
      debugPrint('Error confirming login for salesman: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getTables() async {
    try {
      debugPrint('🔄 API: Fetching tables from inv_tables...');
      final response = await _httpGet('/tables');

      debugPrint('📊 API: Tables response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> data = await compute<String, dynamic>(
          _decodeJson,
          response.body,
        );
        debugPrint('✅ API: Loaded ${data.length} tables from database');
        return data.cast<Map<String, dynamic>>();
      } else {
        debugPrint('❌ API: Failed to fetch tables: ${response.statusCode}');
        throw Exception('Failed to fetch tables: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ API: Error fetching tables: $e');
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getChairs() async {
    try {
      debugPrint('🔄 API: Fetching chair options...');
      final response = await _httpGet('/chairs');

      debugPrint('📊 API: Chairs response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> data = await compute<String, dynamic>(
          _decodeJson,
          response.body,
        );
        debugPrint('✅ API: Loaded ${data.length} chair options');
        return data.cast<Map<String, dynamic>>();
      } else {
        debugPrint('❌ API: Failed to fetch chairs: ${response.statusCode}');
        throw Exception('Failed to fetch chairs: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ API: Error fetching chairs: $e');
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getRooms() async {
    try {
      debugPrint('🔄 API: Fetching rooms from inv_rooms...');
      final response = await _httpGet('/rooms');

      debugPrint('📊 API: Rooms response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> data = await compute<String, dynamic>(
          _decodeJson,
          response.body,
        );
        debugPrint('✅ API: Loaded ${data.length} rooms from database');
        return data.cast<Map<String, dynamic>>();
      } else {
        debugPrint('❌ API: Failed to fetch rooms: ${response.statusCode}');
        throw Exception('Failed to fetch rooms: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ API: Error fetching rooms: $e');
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getPaymentModes() async {
    final defaultModes = <Map<String, dynamic>>[
      {'PaymentCode': '001', 'PaymentMode': 'Cash'},
      {'PaymentCode': '002', 'PaymentMode': 'Master Card'},
      {'PaymentCode': '003', 'PaymentMode': 'Visa Card'},
      {'PaymentCode': '004', 'PaymentMode': 'Amex Card'},
      {'PaymentCode': '006', 'PaymentMode': 'Credit'},
      {'PaymentCode': '007', 'PaymentMode': 'Cheque'},
      {'PaymentCode': '008', 'PaymentMode': 'Direct Deposit'},
      {'PaymentCode': '009', 'PaymentMode': 'Online'},
    ];

    try {
      debugPrint('🔄 API: Fetching payment modes from gen_paymentmode...');
      final response = await _httpGet(
        '/gen-paymentmode',
        timeout: const Duration(seconds: 5),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = await compute<String, dynamic>(
          _decodeJson,
          response.body,
        );
        if (data.isNotEmpty) {
          debugPrint(
            '✅ API: Loaded ${data.length} payment modes from database',
          );
          return data.cast<Map<String, dynamic>>();
        }
      }
    } catch (e) {
      debugPrint(
        '⚠️ API: Could not fetch payment modes from DB, using default: $e',
      );
    }
    return defaultModes;
  }

  static Future<Map<String, dynamic>> getSalesmanProfile(
    String salesmanCode,
  ) async {
    try {
      final response = await _httpGet(
        '/salesmen/${Uri.encodeComponent(salesmanCode)}/profile',
        timeout: const Duration(seconds: 20),
      );

      if (response.statusCode == 200) {
        return await compute<String, dynamic>(_decodeJson, response.body)
            as Map<String, dynamic>;
      }

      final error = await compute<String, dynamic>(_decodeJson, response.body);
      throw Exception(
        error['details'] ?? error['error'] ?? 'Failed to load profile',
      );
    } catch (e) {
      debugPrint('❌ API: Exception fetching salesman profile: $e');
      rethrow;
    }
  }

  static final Map<String, String?> _salesmanImageCache = {};

  static bool hasCachedSalesmanImage(String salesmanCode) {
    return _salesmanImageCache.containsKey(salesmanCode.trim());
  }

  static String? getCachedSalesmanImage(String salesmanCode) {
    return _salesmanImageCache[salesmanCode.trim()];
  }

  static void clearSalesmanImageCache(String salesmanCode) {
    _salesmanImageCache.remove(salesmanCode.trim());
  }

  static Future<void> uploadSalesmanImage(
    String salesmanCode,
    List<int> imageBytes,
  ) async {
    final code = salesmanCode.trim();
    if (code.isEmpty) {
      throw Exception('Salesman code is required');
    }

    try {
      final response = await _httpPut(
        '/salesmen/${Uri.encodeComponent(code)}/image',
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'image': base64Encode(imageBytes)}),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        clearSalesmanImageCache(code);
        return;
      }

      final error = await compute<String, dynamic>(_decodeJson, response.body);
      throw Exception(
        error['details'] ?? error['error'] ?? 'Failed to upload profile photo',
      );
    } catch (e) {
      debugPrint('❌ API: Exception uploading salesman image: $e');
      rethrow;
    }
  }

  static Future<String?> fetchSalesmanImage(String salesmanCode) async {
    final code = salesmanCode.trim();
    if (code.isEmpty) return null;

    if (_salesmanImageCache.containsKey(code)) {
      return _salesmanImageCache[code];
    }

    try {
      final response = await _httpGet(
        '/salesmen/${Uri.encodeComponent(code)}/image',
        timeout: const Duration(seconds: 15),
      );

      if (response.statusCode == 200) {
        final data =
            await compute<String, dynamic>(_decodeJson, response.body)
                as Map<String, dynamic>;
        final image = data['image']?.toString();
        _salesmanImageCache[code] = image != null && image.isNotEmpty
            ? image
            : null;
        return _salesmanImageCache[code];
      }
    } catch (e) {
      debugPrint('⚠️ API: Failed to fetch salesman image for $code: $e');
    }

    _salesmanImageCache[code] = null;
    return null;
  }

  static Future<List<Salesman>> getSalesmen() async {
    try {
      final response = await _httpGet('/salesmen');
      if (response.statusCode == 200) {
        final data =
            await compute<String, dynamic>(_decodeJson, response.body) as List;
        return data.map((json) => Salesman.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load salesmen: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching salesmen: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> createSalesman({
    required String salesmanName,
    required String password,
    String mobile = '',
    String salesmanType = 'Rep',
    String createdUser = '',
    bool isAdmin = false,
    String costCenter = '000001',
    String userName = '',
  }) async {
    try {
      final response = await _httpPost(
        '/salesmen',
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'salesmanName': salesmanName,
          'password': password,
          'mobile': mobile,
          'salesmanType': salesmanType,
          'createdUser': createdUser,
          'isAdmin': isAdmin,
          'costCenter': costCenter,
          'userName': userName,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return await compute<String, dynamic>(_decodeJson, response.body)
            as Map<String, dynamic>;
      } else {
        final error = await compute<String, dynamic>(
          _decodeJson,
          response.body,
        );
        throw Exception(
          error['details'] ?? error['error'] ?? 'Failed to save salesman',
        );
      }
    } catch (e) {
      debugPrint('❌ API: Exception creating salesman: $e');
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> searchSalesmen(
    String query, {
    String? role,
  }) async {
    try {
      final roleParam = role != null
          ? '&role=${Uri.encodeQueryComponent(role)}'
          : '';
      final response = await _httpGet(
        '/salesmen/search?q=${Uri.encodeQueryComponent(query)}$roleParam',
        timeout: const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data =
            await compute<String, dynamic>(_decodeJson, response.body) as List;
        return data.map((json) => json as Map<String, dynamic>).toList();
      } else {
        final error = await compute<String, dynamic>(
          _decodeJson,
          response.body,
        );
        throw Exception(
          error['details'] ?? error['error'] ?? 'Failed to search salesmen',
        );
      }
    } catch (e) {
      debugPrint('❌ API: Exception searching salesmen: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> updateSalesmanAccessLevel({
    required String salesmanCode,
    required String accessLevel,
    String editedUser = '',
  }) async {
    try {
      final response = await _httpPut(
        '/salesmen/${Uri.encodeComponent(salesmanCode)}/access',
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'accessLevel': accessLevel,
          'editedUser': editedUser,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return await compute<String, dynamic>(_decodeJson, response.body)
            as Map<String, dynamic>;
      } else {
        final error = await compute<String, dynamic>(
          _decodeJson,
          response.body,
        );
        throw Exception(
          error['details'] ??
              error['error'] ??
              'Failed to update salesman access level',
        );
      }
    } catch (e) {
      debugPrint('❌ API: Exception updating salesman access level: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getSalesmanUseRights(
    String salesmanCode,
  ) async {
    try {
      final response = await _httpGet(
        '/salesmen/${Uri.encodeComponent(salesmanCode)}/use-rights',
        timeout: const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final body =
            await compute<String, dynamic>(_decodeJson, response.body)
                as Map<String, dynamic>;
        final rights = body['rights'];
        if (rights is Map<String, dynamic>) return rights;
        return Map<String, dynamic>.from(body);
      } else {
        final error = await compute<String, dynamic>(
          _decodeJson,
          response.body,
        );
        throw Exception(
          error['details'] ??
              error['error'] ??
              'Failed to load salesman use rights',
        );
      }
    } catch (e) {
      debugPrint('❌ API: Exception loading salesman use rights: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> updateSalesmanUseRights({
    required String salesmanCode,
    required Map<String, bool> rights,
    String editedUser = '',
  }) async {
    try {
      final response = await _httpPut(
        '/salesmen/${Uri.encodeComponent(salesmanCode)}/use-rights',
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'rights': rights, 'editedUser': editedUser}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return await compute<String, dynamic>(_decodeJson, response.body)
            as Map<String, dynamic>;
      } else {
        final error = await compute<String, dynamic>(
          _decodeJson,
          response.body,
        );
        throw Exception(
          error['details'] ??
              error['error'] ??
              'Failed to update salesman use rights',
        );
      }
    } catch (e) {
      debugPrint('❌ API: Exception updating salesman use rights: $e');
      rethrow;
    }
  }

  static const String _cachedLocationsKey = 'cached_locations_list';
  static List<Map<String, dynamic>>? _cachedLocations;

  static Future<List<Map<String, dynamic>>> getLocations({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cachedLocations != null &&
        _cachedLocations!.isNotEmpty) {
      return List<Map<String, dynamic>>.from(_cachedLocations!);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!forceRefresh) {
        final cachedString = prefs.getString(_cachedLocationsKey);
        if (cachedString != null && cachedString.isNotEmpty) {
          try {
            final decoded = json.decode(cachedString) as List;
            _cachedLocations = decoded
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            // Silent refresh in background
            _httpGet('/locations', timeout: const Duration(seconds: 8))
                .then((res) {
                  if (res.statusCode == 200) {
                    final fresh = json.decode(res.body) as List;
                    final freshList = fresh
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList();
                    _cachedLocations = freshList;
                    prefs.setString(_cachedLocationsKey, res.body);
                  }
                })
                .catchError((_) {});
            return List<Map<String, dynamic>>.from(_cachedLocations!);
          } catch (_) {}
        }
      }

      final response = await _httpGet(
        '/locations',
        timeout: const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data =
            await compute<String, dynamic>(_decodeJson, response.body) as List;
        final list = data.map((json) => json as Map<String, dynamic>).toList();
        _cachedLocations = list;
        prefs.setString(_cachedLocationsKey, response.body);
        return list;
      } else {
        throw Exception('Failed to load locations: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ API: Exception fetching locations: $e');
      if (_cachedLocations != null && _cachedLocations!.isNotEmpty) {
        return List<Map<String, dynamic>>.from(_cachedLocations!);
      }
      return [];
    }
  }

  // ==================== CUSTOMERS ====================

  static Future<List<Map<String, dynamic>>> getCustomers({
    String salesRepCode = '',
    bool forceRefresh = false,
  }) async {
    final cacheKey = salesRepCode.trim();

    if (!forceRefresh &&
        _memoryCustomerCache != null &&
        _memoryCustomerCacheKey == cacheKey &&
        _isCacheFresh(_memoryCustomerCacheAt)) {
      return List<Map<String, dynamic>>.from(_memoryCustomerCache!);
    }

    if (!forceRefresh && _inflightCustomers != null) {
      return _inflightCustomers!;
    }

    _inflightCustomers = _fetchCustomers(salesRepCode: cacheKey);
    try {
      return await _inflightCustomers!;
    } finally {
      _inflightCustomers = null;
    }
  }

  static Future<List<Map<String, dynamic>>> _fetchCustomers({
    required String salesRepCode,
  }) async {
    try {
      final query = salesRepCode.trim().isEmpty
          ? ''
          : '?createdSalesman=${Uri.encodeQueryComponent(salesRepCode.trim())}';
      debugPrint('🔄 Fetching customer list...');
      final response = await _httpGet(
        '/customers/list$query',
        timeout: const Duration(seconds: 20),
      );

      if (response.statusCode == 200) {
        final data =
            await compute<String, dynamic>(_decodeJson, response.body) as List;
        final customers = data
            .map((json) => Map<String, dynamic>.from(json as Map))
            .toList();
        _memoryCustomerCache = customers;
        _memoryCustomerCacheKey = salesRepCode;
        _memoryCustomerCacheAt = DateTime.now();
        await _persistCustomersCache(customers);
        debugPrint('✅ Loaded ${customers.length} customers');
        return customers;
      }

      throw Exception(
        'Failed to load customers: ${response.statusCode} - ${response.body}',
      );
    } catch (e) {
      debugPrint('❌ API: Exception fetching customers: $e');
      final cached = await _readPersistedCustomersCache();
      if (cached.isNotEmpty) {
        debugPrint('📦 Using ${cached.length} cached customers');
        _memoryCustomerCache = cached;
        _memoryCustomerCacheAt = DateTime.now();
        return cached;
      }
      rethrow;
    }
  }

  static Future<void> _persistCustomersCache(
    List<Map<String, dynamic>> customers,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cachedCustomersKey, json.encode(customers));
    } catch (e) {
      debugPrint('⚠️ Failed to persist customer cache: $e');
    }
  }

  static Future<List<Map<String, dynamic>>>
  _readPersistedCustomersCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cachedCustomersKey);
      if (raw == null || raw.isEmpty) return [];
      final data = await compute<String, dynamic>(_decodeJson, raw) as List;
      return data
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (e) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> searchCustomers(
    String query, {
    String salesRepCode = '',
  }) async {
    try {
      final repQuery = salesRepCode.trim().isEmpty
          ? ''
          : '&createdSalesman=${Uri.encodeQueryComponent(salesRepCode.trim())}';
      final response = await _httpGet(
        '/customers/search?q=${Uri.encodeQueryComponent(query)}$repQuery',
        timeout: const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data =
            await compute<String, dynamic>(_decodeJson, response.body) as List;
        return data.map((json) => json as Map<String, dynamic>).toList();
      } else {
        final error = await compute<String, dynamic>(
          _decodeJson,
          response.body,
        );
        throw Exception(
          error['details'] ?? error['error'] ?? 'Failed to search customers',
        );
      }
    } catch (e) {
      debugPrint('❌ API: Exception searching customers: $e');
      rethrow;
    }
  }

  static Future<double> getCustomerOutstanding(
    String customerCode, {
    String location = '',
    String costCenter = '',
    String date = '',
  }) async {
    try {
      final queryParams = <String>[];
      if (location.isNotEmpty)
        queryParams.add('location=${Uri.encodeQueryComponent(location)}');
      if (costCenter.isNotEmpty)
        queryParams.add('costCenter=${Uri.encodeQueryComponent(costCenter)}');
      if (date.isNotEmpty)
        queryParams.add('date=${Uri.encodeQueryComponent(date)}');

      final queryString = queryParams.isNotEmpty
          ? '?${queryParams.join('&')}'
          : '';

      final response = await _httpGet(
        '/customers/${Uri.encodeComponent(customerCode)}/outstanding$queryString',
        timeout: const Duration(seconds: 15),
      );

      if (response.statusCode == 200) {
        final data = await compute<String, dynamic>(_decodeJson, response.body);
        if (data['success'] == true) {
          return (data['outstanding'] as num).toDouble();
        }
        return 0.0;
      } else {
        throw Exception('Failed to fetch outstanding: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ API: Exception fetching customer outstanding: $e');
      return 0.0;
    }
  }

  static Future<void> assignCustomersToSalesman(
    String salesmanCode,
    List<String> customerCodes,
  ) async {
    try {
      final response = await _httpPost(
        '/admin/assign-customers',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'salesmanCode': salesmanCode,
          'customerCodes': customerCodes,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to assign customers: ${response.body}');
      }
    } catch (e) {
      throw Exception('Network or server error: $e');
    }
  }

  static Future<Map<String, dynamic>> createCustomer({
    required String customerName,
    String location = '',
    double? latitude,
    double? longitude,
    String mobile = '',
    String telephone = '',
    String customerId = '',
    String address1 = '',
    String address2 = '',
    String address3 = '',
    String customerType = 'Trade',
    String taxGroupCode = '1',
    double creditLimit = 0,
    double creditPeriod = 0,
    bool creditLimitRestrict = false,
    bool creditPeriodRestrict = false,
    bool outstandingRestrict = false,
    bool pdChequeRestrict = false,
    String contactPerson = '',
    String companyName = '',
    String salesRepCode = '',
    String createdSalesman = '',
    String costCenter = '000001',
    String createdUser = '',
    bool isOfflineSync = false,
  }) async {
    try {
      final response = await _httpPost(
        '/customers',
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'customerName': customerName,
          'location': location,
          'latitude': latitude,
          'longitude': longitude,
          'mobile': mobile,
          'telephone': telephone,
          'customerId': customerId,
          'address1': address1,
          'address2': address2,
          'address3': address3,
          'customerType': customerType,
          'taxGroupCode': taxGroupCode,
          'creditLimit': creditLimit,
          'creditPeriod': creditPeriod,
          'creditLimitRestrict': creditLimitRestrict,
          'creditPeriodRestrict': creditPeriodRestrict,
          'outstandingRestrict': outstandingRestrict,
          'pdChequeRestrict': pdChequeRestrict,
          'contactPerson': contactPerson,
          'companyName': companyName,
          'salesRepCode': salesRepCode,
          'createdSalesman': createdSalesman.isNotEmpty
              ? createdSalesman
              : salesRepCode,
          'costCenter': costCenter,
          'createdUser': createdUser,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        invalidateCustomerCache();
        return await compute<String, dynamic>(_decodeJson, response.body)
            as Map<String, dynamic>;
      } else if (response.statusCode == 409 && isOfflineSync) {
        final body = await compute<String, dynamic>(_decodeJson, response.body);
        if (body['existingCustomer'] != null &&
            body['existingCustomer']['code'] != null) {
          return {
            'customerCode': body['existingCustomer']['code'],
            'customer': body['existingCustomer'],
          };
        }
      }

      final error = await compute<String, dynamic>(_decodeJson, response.body);
      throw Exception(
        error['details'] ?? error['error'] ?? 'Failed to save customer',
      );
    } catch (e) {
      debugPrint('❌ API: Exception creating customer: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> updateCustomer({
    required String customerCode,
    required String customerName,
    String location = '',
    double? latitude,
    double? longitude,
    String mobile = '',
    String telephone = '',
    String customerId = '',
    String address1 = '',
    String address2 = '',
    String address3 = '',
    String customerType = 'Trade',
    String taxGroupCode = '1',
    double creditLimit = 0,
    double creditPeriod = 0,
    bool creditLimitRestrict = false,
    bool creditPeriodRestrict = false,
    bool outstandingRestrict = false,
    bool pdChequeRestrict = false,
    String salesRepCode = '',
    String createdSalesman = '',
    String editedUser = '',
  }) async {
    try {
      final response = await _httpPut(
        '/customers/${Uri.encodeComponent(customerCode)}',
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'customerName': customerName,
          'location': location,
          'latitude': latitude,
          'longitude': longitude,
          'mobile': mobile,
          'telephone': telephone,
          'customerId': customerId,
          'address1': address1,
          'address2': address2,
          'address3': address3,
          'customerType': customerType,
          'taxGroupCode': taxGroupCode,
          'creditLimit': creditLimit,
          'creditPeriod': creditPeriod,
          'creditLimitRestrict': creditLimitRestrict,
          'creditPeriodRestrict': creditPeriodRestrict,
          'outstandingRestrict': outstandingRestrict,
          'pdChequeRestrict': pdChequeRestrict,
          'salesRepCode': salesRepCode,
          'createdSalesman': createdSalesman.isNotEmpty
              ? createdSalesman
              : salesRepCode,
          'editedUser': editedUser,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return await compute<String, dynamic>(_decodeJson, response.body)
            as Map<String, dynamic>;
      } else {
        final error = await compute<String, dynamic>(
          _decodeJson,
          response.body,
        );
        throw Exception(
          error['details'] ?? error['error'] ?? 'Failed to update customer',
        );
      }
    } catch (e) {
      debugPrint('❌ API: Exception updating customer: $e');
      rethrow;
    }
  }

  static bool _isSilentRefreshingProducts = false;

  /// Cache-First loader for invoice items / products:
  /// 1. Reads immediately from memory if available, or
  /// 2. Reads immediately from device storage (SharedPreferences) if saved,
  /// 3. If no cache exists yet (first time install), fetches from server and caches to device storage.
  /// 4. Dispatches a silent background refresh to fetch latest stock, additions, deletions,
  ///    and calls [onBackgroundUpdate] when fresh data is ready.
  static Future<List<Map<String, dynamic>>> getProductsForInvoiceCacheFirst({
    void Function(List<Map<String, dynamic>> updatedProducts)?
    onBackgroundUpdate,
  }) async {
    // 1. Fast path: Memory cache already populated
    if (_memoryProductCache != null && _memoryProductCache!.isNotEmpty) {
      triggerSilentProductsRefresh(onBackgroundUpdate: onBackgroundUpdate);
      return List<Map<String, dynamic>>.from(_memoryProductCache!);
    }

    // 2. Local device storage check
    final cached = await _getCachedProductsWithoutImages();
    if (cached.isNotEmpty) {
      _memoryProductCache = cached;
      _memoryProductCacheAt = DateTime.now();
      triggerSilentProductsRefresh(onBackgroundUpdate: onBackgroundUpdate);
      return List<Map<String, dynamic>>.from(cached);
    }

    // 3. First time install on mobile device: fetch from server and persist to storage
    final fresh = await getProductsForInvoice(forceRefresh: true);
    return fresh;
  }

  /// Fetches a lightweight realtime stock map: Map<ProductCode, StockQty> in milliseconds
  static Future<Map<String, double>> fetchRealtimeStockMap({
    String? productCode,
  }) async {
    try {
      final query = productCode != null && productCode.trim().isNotEmpty
          ? '?productCode=${Uri.encodeComponent(productCode.trim())}'
          : '';
      final response = await _httpGet(
        '/products/stock$query',
        timeout: const Duration(seconds: 10),
      );
      if (response.statusCode == 200) {
        final data =
            await compute<String, dynamic>(_decodeJson, response.body) as List;
        final Map<String, double> stockMap = {};
        for (final row in data) {
          final code = row['ProductCode']?.toString() ?? '';
          if (code.isNotEmpty) {
            final qty = (row['StockQty'] as num?)?.toDouble() ?? 0.0;
            stockMap[code] = qty;
          }
        }
        return stockMap;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to fetch realtime stock map: $e');
    }
    return {};
  }

  /// Merges a realtime stock map into a provided list of product maps.
  static List<Map<String, dynamic>> applyStockMapToList(
    List<Map<String, dynamic>> products,
    Map<String, double> stockMap,
  ) {
    if (products.isEmpty || stockMap.isEmpty) return products;
    return products.map((item) {
      final code = item['code']?.toString() ?? '';
      if (stockMap.containsKey(code)) {
        final copy = Map<String, dynamic>.from(item);
        copy['stockQty'] = stockMap[code]!;
        return copy;
      }
      return item;
    }).toList();
  }

  /// Instant single-product realtime stock query (for strict validation before adding)
  static Future<double?> fetchSingleProductStock(String productCode) async {
    final map = await fetchRealtimeStockMap(productCode: productCode);
    return map[productCode.trim()];
  }

  /// Updates in-memory and persisted product cache with realtime stock quantities
  static Future<List<Map<String, dynamic>>> applyRealtimeStock(
    Map<String, double> stockMap,
  ) async {
    if (stockMap.isEmpty) return _memoryProductCache ?? [];

    List<Map<String, dynamic>> baseList = _memoryProductCache ?? [];
    if (baseList.isEmpty) {
      baseList = await _getCachedProductsWithoutImages();
    }
    if (baseList.isEmpty) {
      return [];
    }

    final updated = applyStockMapToList(baseList, stockMap);
    _memoryProductCache = updated;
    await _cacheProductsWithoutImages(updated);
    return updated;
  }

  /// Triggers a silent background fetch for invoice products, saving updates
  /// to local device storage and notifying [onBackgroundUpdate] without blocking UI.
  static void triggerSilentProductsRefresh({
    void Function(List<Map<String, dynamic>> updatedProducts)?
    onBackgroundUpdate,
  }) {
    if (_isSilentRefreshingProducts) return;
    _isSilentRefreshingProducts = true;

    // First do a fast realtime stock sync (runs in milliseconds)
    fetchRealtimeStockMap()
        .then((stockMap) async {
          if (stockMap.isNotEmpty) {
            final updatedWithStock = await applyRealtimeStock(stockMap);
            if (updatedWithStock.isNotEmpty) {
              onBackgroundUpdate?.call(updatedWithStock);
            }
          }
        })
        .catchError((_) {});

    // Then do the full product master refresh
    _fetchProductsForInvoice()
        .then((fresh) {
          _isSilentRefreshingProducts = false;
          if (fresh.isNotEmpty) {
            onBackgroundUpdate?.call(fresh);
          }
        })
        .catchError((e) {
          _isSilentRefreshingProducts = false;
          debugPrint('⚠️ Silent background product refresh skipped: $e');
        });
  }

  // Get products for invoice (returns Map format with UnitPrice and WholeSalePrice)
  static Future<List<Map<String, dynamic>>> getProductsForInvoice({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _memoryProductCache != null &&
        _isCacheFresh(_memoryProductCacheAt)) {
      return List<Map<String, dynamic>>.from(_memoryProductCache!);
    }

    if (!forceRefresh && _inflightProducts != null) {
      return _inflightProducts!;
    }

    _inflightProducts = _fetchProductsForInvoice();
    try {
      return await _inflightProducts!;
    } finally {
      _inflightProducts = null;
    }
  }

  static Future<List<Map<String, dynamic>>> _fetchProductsForInvoice() async {
    try {
      debugPrint('🔄 Fetching invoice items with realtime stock...');
      final response = await _httpGet(
        '/products/invoice?realtime=true',
        timeout: const Duration(seconds: 30),
      );

      if (response.statusCode == 200) {
        final data =
            await compute<String, dynamic>(_decodeJson, response.body) as List;
        final products = _mapInvoiceProducts(data);
        _memoryProductCache = products;
        _memoryProductCacheAt = DateTime.now();
        await _cacheProductsWithoutImages(products);
        debugPrint('✅ Loaded ${products.length} invoice items with live stock');
        return products;
      }

      throw Exception(
        'Failed to load products: ${response.statusCode} - ${response.body}',
      );
    } catch (e) {
      debugPrint('❌ API: Exception fetching products: $e');
      final cachedProducts = await _getCachedProductsWithoutImages();
      if (cachedProducts.isNotEmpty) {
        debugPrint('📦 API: Using ${cachedProducts.length} cached products');
        _memoryProductCache = cachedProducts;
        _memoryProductCacheAt = DateTime.now();
        return cachedProducts;
      }
      rethrow;
    }
  }

  static List<Map<String, dynamic>> _mapInvoiceProducts(List<dynamic> data) {
    return data.map((json) {
      final product = json as Map<String, dynamic>;
      double numberValue(String key, [double defaultValue = 0]) {
        final value = product[key];
        if (value is num) return value.toDouble();
        return double.tryParse(value?.toString() ?? '') ?? defaultValue;
      }

      String stringValue(String key, [String defaultValue = '']) {
        final value = product[key];
        if (value == null || value.toString() == 'NULL') {
          return defaultValue;
        }
        return value.toString();
      }

      return {
        'code': product['ProductCode']?.toString() ?? '',
        'name':
            product['ProductName']?.toString() ??
            product['NameOnInvoice']?.toString() ??
            '',
        'longDescription': stringValue('LongDescription'),
        'uom': stringValue('SellingUnit', stringValue('Unit')),
        'margin': numberValue('Margin'),
        'packSize': numberValue('PackSize', 1),
        'reOrderQty': numberValue('ReOrderQty'),
        'costPrice': numberValue('CostPrice'),
        'unitPrice': numberValue('UnitPrice'),
        'wholeSalePrice': numberValue('WholeSalePrice'),
        'batchNo': stringValue('BatchNo'),
        'stockLoca': stringValue('StockLoca'),
        'tax': numberValue('Tax'),
        'serialNo': stringValue('SerialNo'),
        'warrantyPeriod': numberValue('WarrantyPeriod'),
        'phase': stringValue('Phase'),
        'periodDays': numberValue('PeriodDays'),
        'expiryDate': product['ExpiryDate']?.toString(),
        'isBatch': stringValue('IsBatch', '0'),
        'isExpiry': stringValue('IsExpiry', '0'),
        'isSemi': stringValue('IsSemi', '0'),
        'isAuthority': stringValue('IsAuthority', '0'),
        'avgCostPrice': numberValue('AvgCostPrice'),
        'avgDiscount': numberValue('AvgDiscount'),
        'avgOther': numberValue('AvgOther'),
        'avgVat': numberValue('AvgVat'),
        'avgMasterCostPrice': numberValue('AvgMasterCostPrice'),
        'refCode': stringValue('RefCode'),
        'stockQty': numberValue('StockQty'),
        'priceLevels': () {
          final raw = product['PriceLevels'] ?? product['priceLevels'];
          if (raw is List) {
            return raw.map((pl) {
              final m = pl is Map ? pl : <String, dynamic>{};
              return {
                'levelCode': (m['levelCode'] ?? m['LevelCode'] ?? '').toString().trim(),
                'priceLevelName': (m['priceLevelName'] ?? m['PriceLevelName'] ?? '').toString().trim(),
                'price': (m['price'] as num?)?.toDouble() ?? (m['Price'] as num?)?.toDouble() ?? 0.0,
              };
            }).toList();
          }
          return <Map<String, dynamic>>[];
        }(),
      };
    }).toList();
  }

  /// Fetches raw price levels from /api/pricelevels
  static Future<List<Map<String, dynamic>>> getPriceLevels() async {
    try {
      final response = await _httpGet(
        '/pricelevels',
        timeout: const Duration(seconds: 15),
      );
      if (response.statusCode == 200) {
        final data =
            await compute<String, dynamic>(_decodeJson, response.body) as List;
        return data.map((json) {
          final row = json as Map<String, dynamic>;
          return {
            'levelCode': (row['LevelCode'] ?? row['levelCode'] ?? '').toString().trim(),
            'productCode': (row['ProductCode'] ?? row['productCode'] ?? '').toString().trim(),
            'price': (row['Price'] as num?)?.toDouble() ?? (row['price'] as num?)?.toDouble() ?? 0.0,
            'priceLevelName': (row['PriceLevelName'] ?? row['priceLevelName'] ?? '').toString().trim(),
          };
        }).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching price levels: $e');
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> getProductsForCRN() {
    return getProductsForInvoice();
  }

  static final Map<String, String> _productImageCache = {};

  static bool hasCachedProductImage(String productCode) {
    return _productImageCache.containsKey(productCode.trim());
  }

  static String? getCachedProductImage(String productCode) {
    return _productImageCache[productCode.trim()];
  }

  /// Direct binary image URL for [Image.network].
  static String productImageFileUrl(String productCode) {
    final code = productCode.trim();
    return '$baseUrl/products/${Uri.encodeComponent(code)}/image/file';
  }

  static Future<String?> fetchProductImage(String productCode) async {
    final code = productCode.trim();
    if (code.isEmpty) return null;

    final cached = _productImageCache[code];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    try {
      final response = await _httpGet(
        '/products/${Uri.encodeComponent(code)}/image',
        timeout: const Duration(seconds: 15),
      );

      if (response.statusCode == 200) {
        final data =
            await compute<String, dynamic>(_decodeJson, response.body)
                as Map<String, dynamic>;
        final image = data['image']?.toString();
        if (image != null && image.isNotEmpty) {
          _productImageCache[code] = image;
          return image;
        }
      } else {
        debugPrint(
          '⚠️ API: Image fetch for $code returned ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('⚠️ API: Failed to fetch image for $code: $e');
    }

    // Do not cache failures — allow retry on next open.
    return null;
  }

  /// Product codes that have images in ERP (for offline image sync).
  static Future<List<String>> fetchProductImageCodes() async {
    try {
      final response = await _httpGet(
        '/products/images/codes',
        timeout: const Duration(seconds: 30),
      );

      if (response.statusCode == 200) {
        final data =
            await compute<String, dynamic>(_decodeJson, response.body)
                as Map<String, dynamic>;
        final codes = data['codes'];
        if (codes is List) {
          return codes
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      }
      debugPrint('⚠️ API: Product image codes returned ${response.statusCode}');
    } catch (e) {
      debugPrint('⚠️ API: Failed to fetch product image codes: $e');
    }
    return [];
  }

  static Future<void> _cacheProductsWithoutImages(
    List<Map<String, dynamic>> products,
  ) async {
    try {
      final lightweightProducts = products.map((product) {
        final copy = Map<String, dynamic>.from(product);
        copy.remove('image');
        copy['isOfflineCached'] = true;
        return copy;
      }).toList();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _offlineProductsKey,
        json.encode(lightweightProducts),
      );
    } catch (e) {
      debugPrint('⚠️ API: Failed to cache offline products: $e');
    }
  }

  static Future<List<Map<String, dynamic>>>
  _getCachedProductsWithoutImages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_offlineProductsKey);
      if (raw == null || raw.isEmpty) return [];

      final decoded =
          await compute<String, dynamic>(_decodeJson, raw) as List<dynamic>;
      return decoded
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (e) {
      debugPrint('⚠️ API: Failed to read cached offline products: $e');
      return [];
    }
  }

  // ==================== INVOICE POSTING ====================

  // Insert transaction items into inv_temptransaction
  static Future<Map<String, dynamic>> insertTempTransactions({
    required String tempDocNo,
    required String locaCode,
    required String costCenter,
    required String iid,
    required List<Map<String, dynamic>> transactions,
    String? salesmanCode,
  }) async {
    try {
      final response = await _httpPost(
        '/invoice/temp-transactions',
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'tempDocNo': tempDocNo,
          'locaCode': locaCode,
          'costCenter': costCenter,
          'iid': iid,
          'transactions': transactions,
          if (salesmanCode != null && salesmanCode.isNotEmpty)
            'salesmanCode': salesmanCode,
        }),
      );

      if (response.statusCode == 200) {
        return await compute<String, dynamic>(_decodeJson, response.body);
      } else {
        try {
          final error = await compute<String, dynamic>(
            _decodeJson,
            response.body,
          );
          final details = [
            if (error['error'] != null) error['error'],
            if (error['details'] != null) error['details'],
            if (error['errorNumber'] != null) 'SQL:${error['errorNumber']}',
          ].whereType<String>().join(' - ');
          throw Exception(
            details.isNotEmpty
                ? details
                : 'Failed to insert transactions: HTTP ${response.statusCode}',
          );
        } catch (_) {
          throw Exception(
            'Failed to insert transactions: HTTP ${response.statusCode} ${response.body}',
          );
        }
      }
    } catch (e) {
      debugPrint('Error inserting temp transactions: $e');
      rethrow;
    }
  }

  // Insert payment items into inv_temppayment
  static Future<Map<String, dynamic>> insertTempPayments({
    required String tempDocNo,
    required String locaCode,
    required List<Map<String, dynamic>> payments,
  }) async {
    try {
      final response = await _httpPost(
        '/invoice/temp-payments',
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'tempDocNo': tempDocNo,
          'locaCode': locaCode,
          'payments': payments,
        }),
      );

      if (response.statusCode == 200) {
        return await compute<String, dynamic>(_decodeJson, response.body);
      } else {
        try {
          final error = await compute<String, dynamic>(
            _decodeJson,
            response.body,
          );
          final details = [
            if (error['error'] != null) error['error'],
            if (error['details'] != null) error['details'],
            if (error['errorNumber'] != null) 'SQL:${error['errorNumber']}',
          ].whereType<String>().join(' - ');
          throw Exception(
            details.isNotEmpty
                ? details
                : 'Failed to insert payments: HTTP ${response.statusCode}',
          );
        } catch (_) {
          throw Exception(
            'Failed to insert payments: HTTP ${response.statusCode} ${response.body}',
          );
        }
      }
    } catch (e) {
      debugPrint('Error inserting temp payments: $e');
      rethrow;
    }
  }

  // Post invoice using stored procedure
  static Future<Map<String, dynamic>> postInvoice({
    required String docAction, // 'P' for Post, 'S' for Save
    required String customerCode,
    required String salesmanCode,
    required String tempDocNo,
    required String locaCode,
    required String costCenter,
    required String user_Name,
    String? customerName,
    String? address,
    String? iid,
    String? orgDocNo,
    String? tourCode,
    DateTime? documentDate,
    String? manualNo,
    String? reference,
    String? deliveryTerms,
    String? paymentTerms,
    String? remarks,
    int? creditPeriod,
    double? grossAmount,
    double? discPer,
    double? discAmount,
    double? taxPer,
    double? taxAmount,
    double? netAmount,
    String? ledgerCode1,
    String? doubleEntery1,
    String? ledgerCode2,
    String? ledgerCode3,
    String? doubleEntery2,
    String? doubleEntery3,
    String? jobNumber,
    double? otherCharge,
    bool? recall,
    bool? quoRecall,
    bool? sonRecall,
    bool? disRecall,
    bool? toDispach,
    String? saveDocNo,
    String? salesType,
    String? priceLevel,
    String? quotation,
    String? performer,
    String? dispatch,
    double? tempCreditAmt,
    double? roudAmt,
    DateTime? poDate,
    String? currancy,
  }) async {
    try {
      final response = await _httpPost(
        '/invoice/post',
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'docAction': docAction,
          'customerCode': customerCode,
          'customerName': customerName,
          'salesmanCode': salesmanCode,
          'address': address,
          'iid': iid ?? 'INV',
          'tempDocNo': tempDocNo,
          'orgDocNo': orgDocNo,
          'tourCode': tourCode,
          'documentDate': documentDate?.toIso8601String(),
          'locaCode': locaCode,
          'manualNo': manualNo,
          'reference': reference,
          'deliveryTerms': deliveryTerms,
          'paymentTerms': paymentTerms,
          'remarks': remarks,
          'creditPeriod': creditPeriod,
          'grossAmount': grossAmount,
          'discPer': discPer,
          'discAmount': discAmount,
          'taxPer': taxPer,
          'taxAmount': taxAmount,
          'netAmount': netAmount,
          'ledgerCode1': ledgerCode1,
          'doubleEntery1': doubleEntery1,
          'ledgerCode2': ledgerCode2,
          'ledgerCode3': ledgerCode3,
          'doubleEntery2': doubleEntery2,
          'doubleEntery3': doubleEntery3,
          'costCenter': costCenter,
          'jobNumber': jobNumber,
          'otherCharge': otherCharge,
          'recall': recall,
          'quoRecall': quoRecall,
          'sonRecall': sonRecall,
          'disRecall': disRecall,
          'toDispach': toDispach,
          'saveDocNo': saveDocNo,
          'salesType': salesType,
          'priceLevel': priceLevel,
          'quotation': quotation,
          'performer': performer,
          'dispatch': dispatch,
          'tempCreditAmt': tempCreditAmt,
          'roudAmt': roudAmt,
          'poDate': poDate?.toIso8601String(),
          'currancy': currancy ?? 'LKR',
          'user_Name': user_Name,
        }),
      );

      if (response.statusCode == 200) {
        return await compute<String, dynamic>(_decodeJson, response.body);
      } else {
        try {
          final error = await compute<String, dynamic>(
            _decodeJson,
            response.body,
          );
          final details = [
            if (error['error'] != null) error['error'],
            if (error['details'] != null) error['details'],
            if (error['errorNumber'] != null) 'SQL:${error['errorNumber']}',
          ].whereType<String>().join(' - ');
          throw Exception(
            details.isNotEmpty
                ? details
                : 'Failed to post invoice: HTTP ${response.statusCode}',
          );
        } catch (_) {
          throw Exception(
            'Failed to post invoice: HTTP ${response.statusCode} ${response.body}',
          );
        }
      }
    } catch (e) {
      debugPrint('Error posting invoice: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> postInvoicePayload(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _httpPost(
        '/invoice/post',
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      );

      if (response.statusCode == 200) {
        return await compute<String, dynamic>(_decodeJson, response.body)
            as Map<String, dynamic>;
      } else {
        final error = await compute<String, dynamic>(
          _decodeJson,
          response.body,
        );
        final details = [
          if (error['error'] != null) error['error'],
          if (error['details'] != null) error['details'],
          if (error['errorNumber'] != null) 'SQL:${error['errorNumber']}',
        ].whereType<String>().join(' - ');
        throw Exception(
          details.isNotEmpty
              ? details
              : 'Failed to post invoice: HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Error posting invoice payload: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> postCRNPayload(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _httpPost(
        '/crn/post',
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      );

      if (response.statusCode == 200) {
        return await compute<String, dynamic>(_decodeJson, response.body)
            as Map<String, dynamic>;
      } else {
        final error = await compute<String, dynamic>(
          _decodeJson,
          response.body,
        );
        final details = [
          if (error['error'] != null) error['error'],
          if (error['details'] != null) error['details'],
          if (error['errorNumber'] != null) 'SQL:${error['errorNumber']}',
        ].whereType<String>().join(' - ');
        throw Exception(
          details.isNotEmpty
              ? details
              : 'Failed to post CRN: HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Error posting CRN payload: $e');
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getQuotationsForRecall({
    required String customerCode,
  }) async {
    final response = await _httpRequest((base) {
      final uri = Uri.parse(
        '$base/quotations/recall',
      ).replace(queryParameters: {'customerCode': customerCode});
      return http.get(uri);
    });
    if (response.statusCode == 200) {
      return (await compute<String, dynamic>(_decodeJson, response.body)
              as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    }
    throw Exception('Failed to load quotations: ${response.body}');
  }

  static Future<Map<String, dynamic>> getQuotationForRecall({
    required String documentNo,
    String? customerCode,
  }) async {
    final queryParameters = <String, String>{};
    if (customerCode != null && customerCode.trim().isNotEmpty) {
      queryParameters['customerCode'] = customerCode.trim();
    }
    final response = await _httpRequest((base) {
      final uri =
          Uri.parse(
            '$base/quotations/${Uri.encodeComponent(documentNo)}/recall',
          ).replace(
            queryParameters: queryParameters.isEmpty ? null : queryParameters,
          );
      return http.get(uri);
    });
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(
        await compute<String, dynamic>(_decodeJson, response.body) as Map,
      );
    }
    throw Exception('Failed to load quotation: ${response.body}');
  }

  static Future<List<Map<String, dynamic>>> getSalesOrdersForRecall({
    required String customerCode,
  }) async {
    final response = await _httpRequest((base) {
      final uri = Uri.parse(
        '$base/sales-orders/recall',
      ).replace(queryParameters: {'customerCode': customerCode});
      return http.get(uri);
    });
    if (response.statusCode == 200) {
      return (await compute<String, dynamic>(_decodeJson, response.body)
              as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    }
    throw Exception('Failed to load sales orders: ${response.body}');
  }

  static Future<Map<String, dynamic>> getSalesOrderForRecall({
    required String documentNo,
    String? customerCode,
  }) async {
    final queryParameters = <String, String>{};
    if (customerCode != null && customerCode.trim().isNotEmpty) {
      queryParameters['customerCode'] = customerCode.trim();
    }
    final response = await _httpRequest((base) {
      final uri =
          Uri.parse(
            '$base/sales-orders/${Uri.encodeComponent(documentNo)}/recall',
          ).replace(
            queryParameters: queryParameters.isEmpty ? null : queryParameters,
          );
      return http.get(uri);
    });
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(
        await compute<String, dynamic>(_decodeJson, response.body) as Map,
      );
    }
    throw Exception('Failed to load sales order: ${response.body}');
  }

  static Future<List<Map<String, dynamic>>> getInvoicesForRecall({
    required String customerCode,
  }) async {
    final response = await _httpRequest((base) {
      final uri = Uri.parse(
        '$base/invoices/recall',
      ).replace(queryParameters: {'customerCode': customerCode});
      return http.get(uri);
    });
    if (response.statusCode == 200) {
      return (await compute<String, dynamic>(_decodeJson, response.body)
              as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    }
    throw Exception('Failed to load invoices: ${response.body}');
  }

  static Future<Map<String, dynamic>> getInvoiceForRecall({
    required String documentNo,
    String? customerCode,
  }) async {
    final queryParameters = <String, String>{};
    if (customerCode != null && customerCode.trim().isNotEmpty) {
      queryParameters['customerCode'] = customerCode.trim();
    }
    final response = await _httpRequest((base) {
      final uri =
          Uri.parse(
            '$base/invoices/${Uri.encodeComponent(documentNo)}/recall',
          ).replace(
            queryParameters: queryParameters.isEmpty ? null : queryParameters,
          );
      return http.get(uri);
    });
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(
        await compute<String, dynamic>(_decodeJson, response.body) as Map,
      );
    }
    throw Exception('Failed to load invoice: ${response.body}');
  }

  static Future<Map<String, dynamic>> getCrnForRecall({
    required String documentNo,
    String? customerCode,
  }) async {
    final queryParameters = <String, String>{};
    if (customerCode != null && customerCode.trim().isNotEmpty) {
      queryParameters['customerCode'] = customerCode.trim();
    }
    final response = await _httpRequest((base) {
      final uri =
          Uri.parse(
            '$base/crn/${Uri.encodeComponent(documentNo)}/recall',
          ).replace(
            queryParameters: queryParameters.isEmpty ? null : queryParameters,
          );
      return http.get(uri);
    });
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(
        await compute<String, dynamic>(_decodeJson, response.body) as Map,
      );
    }
    throw Exception('Failed to load CRN: ${response.body}');
  }

  // ==================== SALES ORDER POSTING ====================

  // Post sales order using stored procedure
  static Future<Map<String, dynamic>> postSalesOrder(
    Map<String, dynamic> postData,
  ) async {
    try {
      final response = await _httpPost(
        '/sales-order/post',
        headers: {'Content-Type': 'application/json'},
        body: json.encode(postData),
      );

      if (response.statusCode == 200) {
        return await compute<String, dynamic>(_decodeJson, response.body);
      } else {
        try {
          final error = await compute<String, dynamic>(
            _decodeJson,
            response.body,
          );
          final details = [
            if (error['error'] != null) error['error'],
            if (error['details'] != null) error['details'],
            if (error['errorNumber'] != null) 'SQL:${error['errorNumber']}',
          ].whereType<String>().join(' - ');
          throw Exception(
            details.isNotEmpty
                ? details
                : 'Failed to post sales order: HTTP ${response.statusCode}',
          );
        } catch (_) {
          throw Exception(
            'Failed to post sales order: HTTP ${response.statusCode} ${response.body}',
          );
        }
      }
    } catch (e) {
      debugPrint('Error posting sales order: $e');
      rethrow;
    }
  }

  // ==================== QUOTATION POSTING ====================

  static Future<Map<String, dynamic>> postQuotation(
    Map<String, dynamic> postData,
  ) async {
    try {
      final response = await _httpPost(
        '/quotation/post',
        headers: {'Content-Type': 'application/json'},
        body: json.encode(postData),
      );

      if (response.statusCode == 200) {
        return await compute<String, dynamic>(_decodeJson, response.body);
      } else {
        try {
          final error = await compute<String, dynamic>(
            _decodeJson,
            response.body,
          );
          final details = [
            if (error['error'] != null) error['error'],
            if (error['details'] != null) error['details'],
            if (error['errorNumber'] != null) 'SQL:${error['errorNumber']}',
          ].whereType<String>().join(' - ');
          throw Exception(
            details.isNotEmpty
                ? details
                : 'Failed to post quotation: HTTP ${response.statusCode}',
          );
        } catch (_) {
          throw Exception(
            'Failed to post quotation: HTTP ${response.statusCode} ${response.body}',
          );
        }
      }
    } catch (e) {
      debugPrint('Error posting quotation: $e');
      rethrow;
    }
  }

  // ==================== REP HISTORY ====================

  static Future<List<Map<String, dynamic>>> getRepDocumentHistory({
    required String salesmanCode,
    required String documentType,
    String? fromDate,
    String? toDate,
    int limit = 100,
  }) async {
    try {
      final query = <String, String>{
        'salesmanCode': salesmanCode,
        'type': documentType,
        'limit': limit.toString(),
        if (fromDate != null && fromDate.isNotEmpty) 'fromDate': fromDate,
        if (toDate != null && toDate.isNotEmpty) 'toDate': toDate,
      };
      final response = await _httpRequest((base) {
        final uri = Uri.parse(
          '$base/rep-history/documents',
        ).replace(queryParameters: query);
        return http.get(uri);
      });

      final body =
          await compute<String, dynamic>(_decodeJson, response.body)
              as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        final entries = body['entries'];
        if (entries is List) {
          return entries
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList();
        }
        return [];
      }

      throw Exception(
        body['error']?.toString() ??
            body['details']?.toString() ??
            'Failed to load document history',
      );
    } catch (e) {
      debugPrint('Error loading rep document history: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getRepTodaySalesSummary({
    required String salesmanCode,
    String? date,
  }) async {
    try {
      final query = <String, String>{
        'salesmanCode': salesmanCode,
        if (date != null && date.isNotEmpty) 'date': date,
      };
      final response = await _httpRequest((base) {
        final uri = Uri.parse(
          '$base/rep-history/today-summary',
        ).replace(queryParameters: query);
        return http.get(uri);
      });

      final body =
          await compute<String, dynamic>(_decodeJson, response.body)
              as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body;
      }

      throw Exception(
        body['error']?.toString() ??
            body['details']?.toString() ??
            'Failed to load today\'s sales summary',
      );
    } catch (e) {
      debugPrint('Error loading rep today summary: $e');
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getAdminHistorySalesmen() async {
    try {
      debugPrint('📋 Loading admin history salesmen from database...');
      final response = await _httpGet('/admin-history/salesmen');
      final body =
          await compute<String, dynamic>(_decodeJson, response.body)
              as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        final salesmen = body['salesmen'];
        if (salesmen is List) {
          final rows = salesmen
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
          debugPrint(
            '✅ Loaded ${rows.length} salesmen for admin history filter',
          );
          return rows;
        }
        return [];
      }

      throw Exception(
        body['error']?.toString() ??
            body['details']?.toString() ??
            'Failed to load salesmen for history filter',
      );
    } catch (e) {
      debugPrint('Error loading admin history salesmen: $e');
      rethrow;
    }
  }

  static Future<AdminDocumentHistoryResult> getAdminDocumentHistory({
    required String documentType,
    String? salesmanCode,
    String? fromDate,
    String? toDate,
    String? search,
    int limit = 5000,
  }) async {
    try {
      final query = <String, String>{
        'type': documentType,
        'limit': limit.toString(),
        if (salesmanCode != null && salesmanCode.isNotEmpty)
          'salesmanCode': salesmanCode,
        if (fromDate != null && fromDate.isNotEmpty) 'fromDate': fromDate,
        if (toDate != null && toDate.isNotEmpty) 'toDate': toDate,
        if (search != null && search.isNotEmpty) 'search': search,
      };
      final response = await _httpRequest((base) {
        final uri = Uri.parse(
          '$base/admin-history/documents',
        ).replace(queryParameters: query);
        return http.get(uri);
      });

      final body =
          await compute<String, dynamic>(_decodeJson, response.body)
              as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        final result = AdminDocumentHistoryResult.fromJson(body);
        debugPrint(
          '✅ Admin history loaded: ${result.summary.documentCount} document(s), '
          '${result.summary.salesmanCount} salesman group(s), '
          'total Rs. ${result.summary.grandTotal}',
        );
        return result;
      }

      throw Exception(
        body['error']?.toString() ??
            body['details']?.toString() ??
            'Failed to load admin document history',
      );
    } catch (e) {
      debugPrint('Error loading admin document history: $e');
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getAdminLocationCheckInHistory({
    String? salesmanCode,
    String? fromDate,
    String? toDate,
  }) async {
    try {
      debugPrint('📍 Loading admin salesman location history from database...');
      final query = <String, String>{
        if (salesmanCode != null && salesmanCode.isNotEmpty)
          'salesmanCode': salesmanCode,
        if (fromDate != null && fromDate.isNotEmpty) 'fromDate': fromDate,
        if (toDate != null && toDate.isNotEmpty) 'toDate': toDate,
      };
      final response = await _httpRequest((base) {
        final uri = Uri.parse(
          '$base/admin-history/location-checkins',
        ).replace(queryParameters: query);
        return http.get(uri);
      });

      final body =
          await compute<String, dynamic>(_decodeJson, response.body)
              as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        final entries = body['entries'];
        if (entries is List) {
          final rows = entries
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList();
          debugPrint(
            '✅ Loaded ${rows.length} location history point(s) for admin',
          );
          return rows;
        }
        return [];
      }

      throw Exception(
        body['error']?.toString() ??
            body['details']?.toString() ??
            'Failed to load salesman location history',
      );
    } catch (e) {
      debugPrint('Error loading admin location history: $e');
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getSalesmanPlaceCheckInHistory({
    required String salesmanCode,
    String? date,
    String? fromDate,
    String? toDate,
  }) async {
    try {
      final query = <String, String>{
        'salesmanCode': salesmanCode,
        if (date != null && date.isNotEmpty) 'date': date,
        if (fromDate != null && fromDate.isNotEmpty) 'fromDate': fromDate,
        if (toDate != null && toDate.isNotEmpty) 'toDate': toDate,
      };
      final response = await _httpRequest((base) {
        final uri = Uri.parse(
          '$base/salesman-place-checkin',
        ).replace(queryParameters: query);
        return http.get(uri);
      });

      final body =
          await compute<String, dynamic>(_decodeJson, response.body)
              as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        final entries = body['entries'];
        if (entries is List) {
          return entries
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList();
        }
        return [];
      }

      throw Exception(
        body['error']?.toString() ??
            body['details']?.toString() ??
            'Failed to load location history',
      );
    } catch (e) {
      debugPrint('Error loading location history: $e');
      rethrow;
    }
  }

  // ==================== DAILY LEADERBOARD ====================

  static Future<Map<String, dynamic>> getDailyLeaderboard({
    String? date,
  }) async {
    try {
      final query = (date != null && date.trim().isNotEmpty)
          ? '?date=${Uri.encodeComponent(date.trim())}'
          : '';
      final response = await _httpGet('/leaderboard/daily$query');

      if (response.statusCode == 200) {
        return await compute<String, dynamic>(_decodeJson, response.body)
            as Map<String, dynamic>;
      }

      try {
        final error = await compute<String, dynamic>(
          _decodeJson,
          response.body,
        );
        throw Exception(
          error['error']?.toString() ??
              'Failed to load leaderboard: HTTP ${response.statusCode}',
        );
      } catch (_) {
        throw Exception(
          'Failed to load leaderboard: HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Error loading daily leaderboard: $e');
      rethrow;
    }
  }

  // ==================== MONTHLY LEADERBOARD ====================

  static Future<Map<String, dynamic>> getMonthlyLeaderboard({
    String? month, // Format: YYYY-MM
  }) async {
    try {
      final query = (month != null && month.trim().isNotEmpty)
          ? '?month=${Uri.encodeComponent(month.trim())}'
          : '';
      final response = await _httpGet('/leaderboard/monthly$query');

      if (response.statusCode == 200) {
        return await compute<String, dynamic>(_decodeJson, response.body)
            as Map<String, dynamic>;
      }

      try {
        final error = await compute<String, dynamic>(
          _decodeJson,
          response.body,
        );
        throw Exception(
          error['error']?.toString() ??
              'Failed to load monthly leaderboard: HTTP ${response.statusCode}',
        );
      } catch (_) {
        throw Exception(
          'Failed to load monthly leaderboard: HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Error loading monthly leaderboard: $e');
      rethrow;
    }
  }

  // ==================== RANGE LEADERBOARD ====================

  static Future<Map<String, dynamic>> getRangeLeaderboard({
    required String startDate, // Format: YYYY-MM-DD
    required String endDate, // Format: YYYY-MM-DD
  }) async {
    try {
      final query =
          '?startDate=${Uri.encodeComponent(startDate)}&endDate=${Uri.encodeComponent(endDate)}';
      final response = await _httpGet('/leaderboard/range$query');

      if (response.statusCode == 200) {
        return await compute<String, dynamic>(_decodeJson, response.body)
            as Map<String, dynamic>;
      }

      try {
        final error = await compute<String, dynamic>(
          _decodeJson,
          response.body,
        );
        throw Exception(
          error['error']?.toString() ??
              'Failed to load range leaderboard: HTTP ${response.statusCode}',
        );
      } catch (_) {
        throw Exception(
          'Failed to load range leaderboard: HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Error loading range leaderboard: $e');
      rethrow;
    }
  }

  // ==================== HEALTH CHECK ====================

  static Future<bool> checkHealth() async {
    try {
      await ensureApiHost();
      final response = await _httpGet('/health');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Health check failed: $e');
      return false;
    }
  }

  // ==========================================
  // Sales Order Reporting & Approval Endpoints
  // ==========================================

  static Future<List<Map<String, dynamic>>> getSalesOrdersForReporting({
    String? salesmanCode,
    String? status,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (salesmanCode != null) queryParams['salesmanCode'] = salesmanCode;
      if (status != null) queryParams['status'] = status;

      final uri = Uri.parse(
        '$baseUrl/sales-orders/reporting',
      ).replace(queryParameters: queryParams);

      final response = await withFailover(
        () => http.get(uri).timeout(const Duration(seconds: 15)),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = await compute<String, dynamic>(
          _decodeJson,
          response.body,
        );
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      debugPrint('Error getting reporting sales orders: $e');
      return [];
    }
  }

  static Future<bool> approveSalesOrder(String documentNo) async {
    try {
      final response = await withFailover(() {
        return http
            .post(
              Uri.parse('$baseUrl/sales-orders/approve'),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({'documentNo': documentNo}),
            )
            .timeout(const Duration(seconds: 15));
      });
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error approving sales order: $e');
      return false;
    }
  }

  static Future<bool> rejectSalesOrder(String documentNo, String reason) async {
    try {
      final response = await withFailover(() {
        return http
            .post(
              Uri.parse('$baseUrl/sales-orders/reject'),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({'documentNo': documentNo, 'reason': reason}),
            )
            .timeout(const Duration(seconds: 15));
      });
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error rejecting sales order: $e');
      return false;
    }
  }

  static Future<int> getPendingSalesOrdersCount() async {
    try {
      final response = await withFailover(() {
        return http
            .get(Uri.parse('$baseUrl/notifications/pending-sales-orders'))
            .timeout(const Duration(seconds: 10));
      });
      if (response.statusCode == 200) {
        final data = await compute<String, dynamic>(_decodeJson, response.body);
        return data['count'] as int? ?? 0;
      }
      return 0;
    } catch (e) {
      debugPrint('Error getting pending sales orders count: $e');
      return 0;
    }
  }
}

class AdminDocumentHistorySummary {
  const AdminDocumentHistorySummary({
    required this.documentCount,
    required this.salesmanCount,
    required this.grandTotal,
  });

  final int documentCount;
  final int salesmanCount;
  final double grandTotal;

  factory AdminDocumentHistorySummary.fromJson(Map<String, dynamic> json) {
    final grandTotal = json['grandTotal'];
    return AdminDocumentHistorySummary(
      documentCount: json['documentCount'] is num
          ? (json['documentCount'] as num).toInt()
          : int.tryParse('${json['documentCount']}') ?? 0,
      salesmanCount: json['salesmanCount'] is num
          ? (json['salesmanCount'] as num).toInt()
          : int.tryParse('${json['salesmanCount']}') ?? 0,
      grandTotal: grandTotal is num
          ? grandTotal.toDouble()
          : double.tryParse('$grandTotal') ?? 0,
    );
  }
}

class AdminDocumentHistoryGroup {
  const AdminDocumentHistoryGroup({
    required this.salesmanCode,
    required this.salesmanName,
    required this.documentCount,
    required this.totalAmount,
    required this.entries,
  });

  final String salesmanCode;
  final String salesmanName;
  final int documentCount;
  final double totalAmount;
  final List<Map<String, dynamic>> entries;

  factory AdminDocumentHistoryGroup.fromJson(Map<String, dynamic> json) {
    final totalAmount = json['totalAmount'];
    final entries = json['entries'];
    return AdminDocumentHistoryGroup(
      salesmanCode: json['salesmanCode']?.toString() ?? '',
      salesmanName: json['salesmanName']?.toString() ?? '',
      documentCount: json['documentCount'] is num
          ? (json['documentCount'] as num).toInt()
          : int.tryParse('${json['documentCount']}') ?? 0,
      totalAmount: totalAmount is num
          ? totalAmount.toDouble()
          : double.tryParse('$totalAmount') ?? 0,
      entries: entries is List
          ? entries
                .whereType<Map>()
                .map((entry) => Map<String, dynamic>.from(entry))
                .toList()
          : [],
    );
  }
}

class AdminDocumentHistoryResult {
  const AdminDocumentHistoryResult({
    required this.summary,
    required this.groups,
    required this.entries,
  });

  final AdminDocumentHistorySummary summary;
  final List<AdminDocumentHistoryGroup> groups;
  final List<Map<String, dynamic>> entries;

  factory AdminDocumentHistoryResult.fromJson(Map<String, dynamic> json) {
    final summaryJson = json['summary'];
    final groupsJson = json['groups'];
    final entriesJson = json['entries'];

    return AdminDocumentHistoryResult(
      summary: summaryJson is Map<String, dynamic>
          ? AdminDocumentHistorySummary.fromJson(summaryJson)
          : const AdminDocumentHistorySummary(
              documentCount: 0,
              salesmanCount: 0,
              grandTotal: 0,
            ),
      groups: groupsJson is List
          ? groupsJson
                .whereType<Map>()
                .map(
                  (group) => AdminDocumentHistoryGroup.fromJson(
                    Map<String, dynamic>.from(group),
                  ),
                )
                .toList()
          : [],
      entries: entriesJson is List
          ? entriesJson
                .whereType<Map>()
                .map((entry) => Map<String, dynamic>.from(entry))
                .toList()
          : [],
    );
  }
}

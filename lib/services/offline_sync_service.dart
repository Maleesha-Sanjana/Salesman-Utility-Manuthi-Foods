import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'offline_auto_sync_service.dart';

class OfflineSyncService {
  static const String _pendingCustomersKey = 'offline_pending_customers';
  static const String _pendingSalesOrdersKey = 'offline_pending_sales_orders';
  static const String _pendingInvoicesKey = 'offline_pending_invoices';
  static const String _pendingCrnsKey = 'offline_pending_crns';
  static const String _customerCodeMapKey = 'offline_customer_code_map';

  static bool _isSyncingAll = false;
  static bool _isSyncingSalesOrders = false;
  static bool _isSyncingInvoices = false;
  static bool _isSyncingCRNs = false;
  static bool _isSyncingCustomers = false;

  static Future<int> getPendingCustomerCount() async {
    final records = await _readPendingCustomers();
    return records.length;
  }

  static Future<int> getPendingSalesOrderCount() async {
    final records = await _readRecords(_pendingSalesOrdersKey);
    return records.length;
  }

  static Future<int> getPendingInvoiceCount() async {
    final records = await _readRecords(_pendingInvoicesKey);
    return records.length;
  }

  static Future<int> getPendingCRNCount() async {
    final records = await _readRecords(_pendingCrnsKey);
    return records.length;
  }

  static Future<int> getTotalPendingCount() async {
    final counts = await Future.wait([
      getPendingCustomerCount(),
      getPendingSalesOrderCount(),
      getPendingInvoiceCount(),
      getPendingCRNCount(),
    ]);
    return counts.fold<int>(0, (total, count) => total + count);
  }

  static Future<List<Map<String, dynamic>>> getPendingDocumentsForRep({
    required String documentType,
    required String salesmanCode,
  }) async {
    final code = salesmanCode.trim();
    if (code.isEmpty) return [];

    final String storageKey;
    switch (documentType) {
      case 'invoice':
        storageKey = _pendingInvoicesKey;
        break;
      case 'sales-order':
        storageKey = _pendingSalesOrdersKey;
        break;
      case 'crn':
        storageKey = _pendingCrnsKey;
        break;
      default:
        return [];
    }

    final records = await _readRecords(storageKey);
    final entries = <Map<String, dynamic>>[];

    for (final record in records) {
      final postData = Map<String, dynamic>.from(
        record['postData'] as Map? ?? {},
      );
      if (postData['salesmanCode']?.toString().trim() != code) continue;

      final createdAt = record['createdAt']?.toString();
      final documentDateRaw = postData['documentDate']?.toString();
      final documentDate = documentDateRaw != null && documentDateRaw.isNotEmpty
          ? DateTime.tryParse(
                  documentDateRaw,
                )?.toIso8601String().split('T').first ??
                createdAt?.split('T').first ??
                '-'
          : createdAt?.split('T').first ?? '-';

      entries.add({
        'documentNo':
            record['localDocNo']?.toString() ??
            postData['orgDocNo']?.toString() ??
            postData['tempDocNo']?.toString() ??
            'Pending',
        'documentDate': documentDate,
        'customerCode': postData['customerCode']?.toString() ?? '',
        'customerName':
            postData['customerName']?.toString() ??
            postData['customerCode']?.toString() ??
            'Customer',
        'netAmount': postData['netAmount'] ?? 0,
        'balanceAmount': postData['netAmount'] ?? 0,
        'remarks': postData['remarks']?.toString() ?? '',
        'isPendingSync': true,
        'lastError': record['lastError']?.toString(),
      });
    }

    entries.sort((a, b) {
      final aDate = a['documentDate']?.toString() ?? '';
      final bDate = b['documentDate']?.toString() ?? '';
      return bDate.compareTo(aDate);
    });

    return entries;
  }

  static Future<OfflineSyncAllResult> syncAllPending() async {
    if (_isSyncingAll ||
        _isSyncingCustomers ||
        _isSyncingSalesOrders ||
        _isSyncingInvoices ||
        _isSyncingCRNs) {
      return const OfflineSyncAllResult(
        totalSynced: 0,
        totalFailed: 0,
        totalRemaining: 0,
        byType: <String, OfflineSyncResult>{},
      );
    }
    _isSyncingAll = true;

    try {
      final customers = await syncPendingCustomers(fromSyncAll: true);
      final salesOrders = await syncPendingSalesOrders(fromSyncAll: true);
      final invoices = await syncPendingInvoices(fromSyncAll: true);
      final crns = await syncPendingCRNs(fromSyncAll: true);

      final byType = {
        'customers': customers,
        'salesOrders': salesOrders,
        'invoices': invoices,
        'crns': crns,
      };

      final totalSynced = byType.values.fold<int>(
        0,
        (total, result) => total + result.synced,
      );
      final totalFailed = byType.values.fold<int>(
        0,
        (total, result) => total + result.failed,
      );
      final totalRemaining = byType.values.fold<int>(
        0,
        (total, result) => total + result.remaining,
      );

      String? unreachableMessage;
      for (final result in byType.values) {
        if (result.message != null) {
          unreachableMessage = result.message;
          break;
        }
      }

      if (totalFailed > 0 && unreachableMessage == null) {
        final errors = <String>[];
        final prefs = await SharedPreferences.getInstance();
        for (final key in [
          _pendingCustomersKey,
          _pendingSalesOrdersKey,
          _pendingInvoicesKey,
          _pendingCrnsKey,
        ]) {
          final str = prefs.getString(key);
          if (str != null) {
            try {
              final list = json.decode(str) as List;
              for (final item in list) {
                if (item is Map && item['lastError'] != null) {
                  errors.add(item['lastError'].toString());
                }
              }
            } catch (_) {}
          }
        }
        if (errors.isNotEmpty) {
          unreachableMessage = 'Errors: ${errors.toSet().join(" | ")}';
        }
      }

      return OfflineSyncAllResult(
        totalSynced: totalSynced,
        totalFailed: totalFailed,
        totalRemaining: totalRemaining,
        message: unreachableMessage,
        byType: byType,
      );
    } finally {
      _isSyncingAll = false;
    }
  }

  static Future<Map<String, dynamic>> queueCustomerCreate({
    required Map<String, dynamic> payload,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final records = await _readPendingCustomers();
    final timestamp = DateTime.now();
    final localCode =
        'LOCAL-CUS-${timestamp.millisecondsSinceEpoch.toString()}';

    final record = {
      'localCode': localCode,
      'payload': payload,
      'createdAt': timestamp.toIso8601String(),
      'lastError': null,
    };

    records.add(record);
    await prefs.setString(_pendingCustomersKey, json.encode(records));
    _notifyQueueChanged();

    return {
      'code': localCode,
      'name': payload['customerName']?.toString() ?? '',
      'address1': payload['address1']?.toString() ?? '',
      'address3': payload['address3']?.toString() ?? '',
      'mobile': payload['mobile']?.toString() ?? '',
      'customerType': payload['customerType']?.toString() ?? 'Trade',
      'taxGroupCode': payload['taxGroupCode']?.toString() ?? '1',
      'creditLimit': payload['creditLimit'] ?? 0,
      'creditPeriod': payload['creditPeriod'] ?? 0,
      'latitude': payload['latitude'],
      'longitude': payload['longitude'],
      'isOffline': true,
    };
  }

  static Future<List<Map<String, dynamic>>> getPendingCustomersForSelection({
    String salesRepCode = '',
  }) async {
    final normalizedRep = salesRepCode.trim().toUpperCase();
    final records = await _readPendingCustomers();
    return records
        .map((record) {
          final payload = Map<String, dynamic>.from(
            record['payload'] as Map? ?? {},
          );
          return {
            'code': record['localCode']?.toString() ?? '',
            'name': payload['customerName']?.toString() ?? '',
            'phone': payload['mobile']?.toString() ?? '',
            'address': payload['address1']?.toString() ?? '',
            'contactPerson': payload['contactPerson']?.toString() ?? '',
            'salesRepCode': payload['salesRepCode']?.toString() ?? '',
            'createdSalesman':
                payload['createdSalesman']?.toString() ??
                payload['salesRepCode']?.toString() ??
                '',
            'latitude': payload['latitude'],
            'longitude': payload['longitude'],
            'isOffline': true,
          };
        })
        .where((customer) {
          if (customer['code'].toString().isEmpty ||
              customer['name'].toString().isEmpty) {
            return false;
          }
          if (normalizedRep.isEmpty) return true;
          final createdSalesman =
              customer['createdSalesman']?.toString().trim().toUpperCase() ??
              '';
          final salesRepCode =
              customer['salesRepCode']?.toString().trim().toUpperCase() ?? '';
          final assigned =
              customer['assigned']?.toString().trim().toUpperCase() ?? '';
          return createdSalesman == normalizedRep ||
              salesRepCode == normalizedRep ||
              assigned == normalizedRep;
        })
        .toList();
  }

  static const String _cachedCustomersKeyPrefix = 'offline_cached_customers_';

  static final Set<String> _activeCustomerSyncKeys = <String>{};

  static Future<List<Map<String, dynamic>>> getCustomersForSelection({
    required String salesRepCode,
    void Function(List<Map<String, dynamic>> updatedCustomers)? onBackgroundUpdate,
  }) async {
    final code = salesRepCode.trim();
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = '$_cachedCustomersKeyPrefix$code';

    List<Map<String, dynamic>> cachedServerCustomers = [];
    final cacheString = prefs.getString(cacheKey);

    if (cacheString != null) {
      try {
        final decoded = json.decode(cacheString) as List;
        cachedServerCustomers =
            decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (e) {
        // Handle decode error silently
      }
    }

    final offlineCustomers = await getPendingCustomersForSelection(
      salesRepCode: code,
    );

    if (cachedServerCustomers.isEmpty) {
      // First time on newly installed device: download all customers to device storage
      try {
        final serverCustomers = await ApiService.getCustomers(
          salesRepCode: code,
          forceRefresh: true,
        );
        await prefs.setString(cacheKey, json.encode(serverCustomers));
        cachedServerCustomers = serverCustomers;
      } catch (e) {
        // If it fails and cache is empty, we just show pending customers
      }
    } else {
      // Subsequent time: reload from device storage immediately, and sync in background silently
      syncCustomersInBackground(
        salesRepCode: code,
        onBackgroundUpdate: onBackgroundUpdate,
      );
    }

    final existingCodes =
        cachedServerCustomers
            .map((customer) => customer['code']?.toString() ?? '')
            .where((value) => value.isNotEmpty)
            .toSet();

    return [
      ...offlineCustomers.where(
        (customer) =>
            !existingCodes.contains(customer['code']?.toString() ?? ''),
      ),
      ...cachedServerCustomers,
    ];
  }

  static void syncCustomersInBackground({
    required String salesRepCode,
    void Function(List<Map<String, dynamic>> updatedCustomers)? onBackgroundUpdate,
  }) {
    final code = salesRepCode.trim();
    final cacheKey = '$_cachedCustomersKeyPrefix$code';

    if (_activeCustomerSyncKeys.contains(cacheKey)) return;
    _activeCustomerSyncKeys.add(cacheKey);

    _syncServerCustomersInBackground(code, cacheKey, onBackgroundUpdate)
        .whenComplete(() {
          _activeCustomerSyncKeys.remove(cacheKey);
        });
  }

  static Future<void> _syncServerCustomersInBackground(
    String code,
    String cacheKey,
    void Function(List<Map<String, dynamic>> updatedCustomers)? onBackgroundUpdate,
  ) async {
    try {
      final serverCustomers = await ApiService.getCustomers(
        salesRepCode: code,
        forceRefresh: true,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, json.encode(serverCustomers));

      if (onBackgroundUpdate != null) {
        final offlineCustomers = await getPendingCustomersForSelection(
          salesRepCode: code,
        );
        final existingCodes = serverCustomers
            .map((customer) => customer['code']?.toString() ?? '')
            .where((value) => value.isNotEmpty)
            .toSet();
        final combined = [
          ...offlineCustomers.where(
            (customer) =>
                !existingCodes.contains(customer['code']?.toString() ?? ''),
          ),
          ...serverCustomers,
        ];
        onBackgroundUpdate(combined);
      }
    } catch (e) {
      debugPrint('⚠️ Silent background customer refresh skipped: $e');
    }
  }

  static Future<String> queueSalesOrderPost({
    Map<String, dynamic>? tempTransactions,
    required Map<String, dynamic> postData,
  }) async {
    final localDocNo = 'LSO${DateTime.now().millisecondsSinceEpoch}';
    final localTempDocNo = 'T$localDocNo';

    final effectiveTempTransactions = Map<String, dynamic>.from(
      tempTransactions ?? (postData['tempTransactions'] as Map? ?? {}),
    );
    final effectivePostData = Map<String, dynamic>.from(postData)
      ..remove('tempTransactions');

    effectiveTempTransactions['tempDocNo'] = localTempDocNo;
    effectivePostData['tempDocNo'] = localTempDocNo;
    effectivePostData['orgDocNo'] = localDocNo;

    await _appendRecord(_pendingSalesOrdersKey, {
      'localDocNo': localDocNo,
      'tempTransactions': effectiveTempTransactions,
      'postData': effectivePostData,
      'createdAt': DateTime.now().toIso8601String(),
      'lastError': null,
    });
    return localDocNo;
  }

  static Future<String> queueInvoicePost({
    required Map<String, dynamic> tempTransactions,
    required Map<String, dynamic> tempPayments,
    required Map<String, dynamic> postData,
  }) async {
    final localDocNo = 'LINV${DateTime.now().millisecondsSinceEpoch}';
    final localTempDocNo = 'T$localDocNo';

    await _appendRecord(_pendingInvoicesKey, {
      'localDocNo': localDocNo,
      'tempTransactions': {...tempTransactions, 'tempDocNo': localTempDocNo},
      'tempPayments': {...tempPayments, 'tempDocNo': localTempDocNo},
      'postData': {
        ...postData,
        'tempDocNo': localTempDocNo,
        'orgDocNo': localDocNo,
      },
      'createdAt': DateTime.now().toIso8601String(),
      'lastError': null,
    });

    return localDocNo;
  }

  static Future<String> queueCRNPost({
    required Map<String, dynamic> tempTransactions,
    required Map<String, dynamic> tempPayments,
    required Map<String, dynamic> postData,
  }) async {
    final localDocNo = 'LCRN${DateTime.now().millisecondsSinceEpoch}';
    final localTempDocNo = 'T$localDocNo';

    await _appendRecord(_pendingCrnsKey, {
      'localDocNo': localDocNo,
      'tempTransactions': {...tempTransactions, 'tempDocNo': localTempDocNo},
      'tempPayments': {...tempPayments, 'tempDocNo': localTempDocNo},
      'postData': {
        ...postData,
        'tempDocNo': localTempDocNo,
        'orgDocNo': localDocNo,
      },
      'createdAt': DateTime.now().toIso8601String(),
      'lastError': null,
    });

    return localDocNo;
  }

  static Future<OfflineSyncResult> syncPendingCustomers({
    bool fromSyncAll = false,
  }) async {
    if (_isSyncingCustomers || (!fromSyncAll && _isSyncingAll)) {
      final records = await _readPendingCustomers();
      return OfflineSyncResult(
        synced: 0,
        failed: 0,
        remaining: records.length,
        message: 'Customer sync already in progress',
      );
    }
    _isSyncingCustomers = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final records = await _readPendingCustomers();

      if (records.isEmpty) {
        return const OfflineSyncResult(synced: 0, failed: 0, remaining: 0);
      }

      final serverAvailable = await ApiService.checkHealth();
      if (!serverAvailable) {
        debugPrint('⚠️ [Sync] Server not reachable for customer sync');
        return OfflineSyncResult(
          synced: 0,
          failed: records.length,
          remaining: records.length,
          message: 'Server is not reachable',
        );
      }

      var synced = 0;
      var failed = 0;
      final remaining = <Map<String, dynamic>>[];

      for (final record in records) {
        final payload = Map<String, dynamic>.from(
          record['payload'] as Map? ?? {},
        );

        try {
          debugPrint(
            '🔄 [Sync] Syncing pending customer: ${payload['customerName']} (${record['localCode']})...',
          );
          final createdCustomer = await ApiService.createCustomer(
            customerName: payload['customerName']?.toString() ?? '',
            location: payload['location']?.toString() ?? '',
            latitude: payload['latitude'] is num
                ? (payload['latitude'] as num).toDouble()
                : null,
            longitude: payload['longitude'] is num
                ? (payload['longitude'] as num).toDouble()
                : null,
            mobile: payload['mobile']?.toString() ?? '',
            customerId: payload['customerId']?.toString() ?? '',
            address1: payload['address1']?.toString() ?? '',
            address2: payload['address2']?.toString() ?? '',
            address3: payload['address3']?.toString() ?? '',
            customerType: payload['customerType']?.toString() ?? 'Trade',
            taxGroupCode: payload['taxGroupCode']?.toString() ?? '1',
            creditLimit: payload['creditLimit'] is num
                ? (payload['creditLimit'] as num).toDouble()
                : double.tryParse(payload['creditLimit']?.toString() ?? '') ?? 0,
            creditPeriod: payload['creditPeriod'] is num
                ? (payload['creditPeriod'] as num).toDouble()
                : double.tryParse(payload['creditPeriod']?.toString() ?? '') ?? 0,
            contactPerson: payload['contactPerson']?.toString() ?? '',
            companyName: payload['companyName']?.toString() ?? '',
            salesRepCode: payload['salesRepCode']?.toString() ?? '',
            createdSalesman:
                payload['createdSalesman']?.toString() ??
                payload['salesRepCode']?.toString() ??
                '',
            costCenter: payload['costCenter']?.toString() ?? '000001',
            createdUser: payload['createdUser']?.toString() ?? '',
            isOfflineSync: true,
          );
          final localCode = record['localCode']?.toString() ?? '';
          final customerData =
              createdCustomer['customer'] as Map? ?? createdCustomer;
          final serverCode =
              customerData['code']?.toString() ??
              createdCustomer['customerCode']?.toString() ??
              '';
          if (localCode.isNotEmpty && serverCode.isNotEmpty) {
            await _saveCustomerCodeMapping(localCode, serverCode);
          }
          debugPrint(
            '✅ [Sync] Customer synced successfully: $localCode -> $serverCode',
          );
          synced += 1;
        } catch (e) {
          debugPrint(
            '❌ [Sync] Error syncing customer ${record['localCode']}: $e',
          );
          failed += 1;
          remaining.add({...record, 'lastError': e.toString()});
        }
      }

      await prefs.setString(_pendingCustomersKey, json.encode(remaining));
      _notifyQueueChanged();

      return OfflineSyncResult(
        synced: synced,
        failed: failed,
        remaining: remaining.length,
      );
    } finally {
      _isSyncingCustomers = false;
    }
  }

  static Future<OfflineSyncResult> syncPendingSalesOrders({
    bool fromSyncAll = false,
  }) async {
    if (_isSyncingSalesOrders || (!fromSyncAll && _isSyncingAll)) {
      final records = await _readRecords(_pendingSalesOrdersKey);
      return OfflineSyncResult(
        synced: 0,
        failed: 0,
        remaining: records.length,
        message: 'Sales order sync already in progress',
      );
    }
    _isSyncingSalesOrders = true;

    try {
      final records = await _readRecords(_pendingSalesOrdersKey);
      if (records.isEmpty) {
        return const OfflineSyncResult(synced: 0, failed: 0, remaining: 0);
      }

      final serverAvailable = await ApiService.checkHealth();
      if (!serverAvailable) {
        debugPrint('⚠️ [Sync] Server not reachable for sales orders');
        return OfflineSyncResult(
          synced: 0,
          failed: records.length,
          remaining: records.length,
          message: 'Server is not reachable',
        );
      }

      var synced = 0;
      var failed = 0;
      final remaining = <Map<String, dynamic>>[];

      for (final record in records) {
        final postData = Map<String, dynamic>.from(
          record['postData'] as Map? ?? {},
        );
        final tempTransactionsRaw =
            record['tempTransactions'] ?? postData.remove('tempTransactions');

        try {
          await _resolveQueuedCustomerCode(postData);

          final tempTransactions = tempTransactionsRaw is Map
              ? Map<String, dynamic>.from(tempTransactionsRaw)
              : <String, dynamic>{};
          final rawItems = (tempTransactions['transactions'] as List?) ??
              (postData['transactions'] as List?) ??
              [];
          final items = rawItems
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();

          if (items.isEmpty) {
            throw Exception('Cannot sync sales order: 0 items in order');
          }

          String tempDocNo =
              tempTransactions['tempDocNo']?.toString().trim() ?? '';
          if (tempDocNo.isEmpty) {
            tempDocNo = postData['tempDocNo']?.toString().trim() ?? '';
          }
          if (tempDocNo.isEmpty) {
            tempDocNo =
                'T${record['localDocNo'] ?? DateTime.now().millisecondsSinceEpoch}';
            tempTransactions['tempDocNo'] = tempDocNo;
          }
          postData['tempDocNo'] = tempDocNo;
          postData['transactions'] = items;

          final locaCode = tempTransactions['locaCode']?.toString() ??
              postData['locaCode']?.toString() ??
              '01';
          final costCenter = tempTransactions['costCenter']?.toString() ??
              postData['costCenter']?.toString() ??
              '000001';
          final iid = tempTransactions['iid']?.toString() ??
              postData['iid']?.toString() ??
              'SON';

          debugPrint(
            '🔄 [Sync] Syncing pending sales order ${record['localDocNo']} (Temp: $tempDocNo, ${items.length} items)...',
          );

          // 1. Insert temp transactions first
          await ApiService.insertTempTransactions(
            tempDocNo: tempDocNo,
            locaCode: locaCode,
            costCenter: costCenter,
            iid: iid,
            transactions: items,
          );

          // 2. Post sales order using stored procedure (transactions attached for atomic handling)
          final response = await ApiService.postSalesOrder(postData);
          if (response['success'] == true) {
            final docNo = response['documentNo'] ?? '';
            debugPrint(
              '✅ [Sync] Sales order ${record['localDocNo']} synced successfully -> $docNo',
            );
            synced += 1;
          } else {
            throw Exception(
              response['error'] ?? response['message'] ?? 'Failed to sync sales order',
            );
          }
        } catch (e) {
          debugPrint(
            '❌ [Sync] Error syncing sales order ${record['localDocNo']}: $e',
          );
          failed += 1;
          remaining.add({...record, 'lastError': e.toString()});
        }
      }

      await _writeRecords(_pendingSalesOrdersKey, remaining);
      _notifyQueueChanged();
      return OfflineSyncResult(
        synced: synced,
        failed: failed,
        remaining: remaining.length,
      );
    } finally {
      _isSyncingSalesOrders = false;
    }
  }

  static Future<OfflineSyncResult> syncPendingInvoices({
    bool fromSyncAll = false,
  }) async {
    if (_isSyncingInvoices || (!fromSyncAll && _isSyncingAll)) {
      final records = await _readRecords(_pendingInvoicesKey);
      return OfflineSyncResult(
        synced: 0,
        failed: 0,
        remaining: records.length,
        message: 'Invoice sync already in progress',
      );
    }
    _isSyncingInvoices = true;

    try {
      final records = await _readRecords(_pendingInvoicesKey);
      if (records.isEmpty) {
        return const OfflineSyncResult(synced: 0, failed: 0, remaining: 0);
      }

      final serverAvailable = await ApiService.checkHealth();
      if (!serverAvailable) {
        debugPrint('⚠️ [Sync] Server not reachable for invoices');
        return OfflineSyncResult(
          synced: 0,
          failed: records.length,
          remaining: records.length,
          message: 'Server is not reachable',
        );
      }

      var synced = 0;
      var failed = 0;
      final remaining = <Map<String, dynamic>>[];

      for (final record in records) {
        try {
          final tempTransactions = Map<String, dynamic>.from(
            record['tempTransactions'] as Map? ?? {},
          );
          final tempPayments = Map<String, dynamic>.from(
            record['tempPayments'] as Map? ?? {},
          );
          final postData = Map<String, dynamic>.from(
            record['postData'] as Map? ?? {},
          );

          final items = (tempTransactions['transactions'] as List? ?? [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
          if (items.isEmpty) {
            throw Exception('Cannot sync invoice: 0 items in invoice');
          }

          debugPrint(
            '🔄 [Sync] Syncing pending invoice ${record['localDocNo']}...',
          );
          await _resolveQueuedCustomerCode(postData);
          await ApiService.insertTempTransactions(
            tempDocNo: tempTransactions['tempDocNo']?.toString() ?? '',
            locaCode: tempTransactions['locaCode']?.toString() ?? '01',
            costCenter: tempTransactions['costCenter']?.toString() ?? '000001',
            iid: tempTransactions['iid']?.toString() ?? 'INV',
            transactions: items,
          );
          await ApiService.insertTempPayments(
            tempDocNo: tempPayments['tempDocNo']?.toString() ?? '',
            locaCode: tempPayments['locaCode']?.toString() ?? '01',
            payments: (tempPayments['payments'] as List? ?? [])
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList(),
          );
          await ApiService.postInvoicePayload(postData);
          debugPrint(
            '✅ [Sync] Invoice ${record['localDocNo']} synced successfully',
          );
          synced += 1;
        } catch (e) {
          debugPrint(
            '❌ [Sync] Error syncing invoice ${record['localDocNo']}: $e',
          );
          failed += 1;
          remaining.add({...record, 'lastError': e.toString()});
        }
      }

      await _writeRecords(_pendingInvoicesKey, remaining);
      _notifyQueueChanged();
      return OfflineSyncResult(
        synced: synced,
        failed: failed,
        remaining: remaining.length,
      );
    } finally {
      _isSyncingInvoices = false;
    }
  }

  static Future<OfflineSyncResult> syncPendingCRNs({
    bool fromSyncAll = false,
  }) async {
    if (_isSyncingCRNs || (!fromSyncAll && _isSyncingAll)) {
      final records = await _readRecords(_pendingCrnsKey);
      return OfflineSyncResult(
        synced: 0,
        failed: 0,
        remaining: records.length,
        message: 'CRN sync already in progress',
      );
    }
    _isSyncingCRNs = true;

    try {
      final records = await _readRecords(_pendingCrnsKey);
      if (records.isEmpty) {
        return const OfflineSyncResult(synced: 0, failed: 0, remaining: 0);
      }

      final serverAvailable = await ApiService.checkHealth();
      if (!serverAvailable) {
        debugPrint('⚠️ [Sync] Server not reachable for CRNs');
        return OfflineSyncResult(
          synced: 0,
          failed: records.length,
          remaining: records.length,
          message: 'Server is not reachable',
        );
      }

      var synced = 0;
      var failed = 0;
      final remaining = <Map<String, dynamic>>[];

      for (final record in records) {
        try {
          final tempTransactions = Map<String, dynamic>.from(
            record['tempTransactions'] as Map? ?? {},
          );
          final tempPayments = Map<String, dynamic>.from(
            record['tempPayments'] as Map? ?? {},
          );
          final postData = Map<String, dynamic>.from(
            record['postData'] as Map? ?? {},
          );

          final items = (tempTransactions['transactions'] as List? ?? [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
          if (items.isEmpty) {
            throw Exception('Cannot sync CRN: 0 items in CRN');
          }

          debugPrint(
            '🔄 [Sync] Syncing pending CRN ${record['localDocNo']}...',
          );
          await _resolveQueuedCustomerCode(postData);
          await ApiService.insertTempTransactions(
            tempDocNo: tempTransactions['tempDocNo']?.toString() ?? '',
            locaCode: tempTransactions['locaCode']?.toString() ?? '01',
            costCenter: tempTransactions['costCenter']?.toString() ?? '000001',
            iid: tempTransactions['iid']?.toString() ?? 'CRN',
            transactions: items,
          );
          await ApiService.insertTempPayments(
            tempDocNo: tempPayments['tempDocNo']?.toString() ?? '',
            locaCode: tempPayments['locaCode']?.toString() ?? '01',
            payments: (tempPayments['payments'] as List? ?? [])
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList(),
          );
          await ApiService.postCRNPayload(postData);
          debugPrint(
            '✅ [Sync] CRN ${record['localDocNo']} synced successfully',
          );
          synced += 1;
        } catch (e) {
          debugPrint(
            '❌ [Sync] Error syncing CRN ${record['localDocNo']}: $e',
          );
          failed += 1;
          remaining.add({...record, 'lastError': e.toString()});
        }
      }

      await _writeRecords(_pendingCrnsKey, remaining);
      _notifyQueueChanged();
      return OfflineSyncResult(
        synced: synced,
        failed: failed,
        remaining: remaining.length,
      );
    } finally {
      _isSyncingCRNs = false;
    }
  }

  static Future<List<Map<String, dynamic>>> _readPendingCustomers() async {
    return _readRecords(_pendingCustomersKey);
  }

  static Future<void> _appendRecord(
    String key,
    Map<String, dynamic> record,
  ) async {
    final records = await _readRecords(key);
    records.add(record);
    await _writeRecords(key, records);
    _notifyQueueChanged();
  }

  static void _notifyQueueChanged() {
    OfflineAutoSyncService.instance.scheduleSyncAttempt();
  }

  static Future<void> _writeRecords(
    String key,
    List<Map<String, dynamic>> records,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, json.encode(records));
  }

  static Future<List<Map<String, dynamic>>> _readRecords(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];

    final decoded = json.decode(raw) as List<dynamic>;
    return decoded
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  static Future<void> _resolveQueuedCustomerCode(
    Map<String, dynamic> postData,
  ) async {
    final customerCode = postData['customerCode']?.toString() ?? '';
    if (!customerCode.startsWith('LOCAL-CUS-')) return;

    final codeMap = await _readCustomerCodeMap();
    final serverCode = codeMap[customerCode];
    if (serverCode == null || serverCode.isEmpty) {
      throw Exception('Customer $customerCode is not synced yet');
    }

    postData['customerCode'] = serverCode;
  }

  static Future<Map<String, String>> _readCustomerCodeMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_customerCodeMapKey);
    if (raw == null || raw.isEmpty) return {};

    final decoded = json.decode(raw) as Map<String, dynamic>;
    return decoded.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  }

  static Future<void> _saveCustomerCodeMapping(
    String localCode,
    String serverCode,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final codeMap = await _readCustomerCodeMap();
    codeMap[localCode] = serverCode;
    await prefs.setString(_customerCodeMapKey, json.encode(codeMap));
  }
}

class OfflineSyncResult {
  const OfflineSyncResult({
    required this.synced,
    required this.failed,
    required this.remaining,
    this.message,
  });

  final int synced;
  final int failed;
  final int remaining;
  final String? message;
}

class OfflineSyncAllResult {
  const OfflineSyncAllResult({
    required this.totalSynced,
    required this.totalFailed,
    required this.totalRemaining,
    required this.byType,
    this.message,
  });

  final int totalSynced;
  final int totalFailed;
  final int totalRemaining;
  final String? message;
  final Map<String, OfflineSyncResult> byType;
}

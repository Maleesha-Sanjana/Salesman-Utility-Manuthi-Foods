import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'receipt_printer_service.dart';

/// Service to handle WiFi (TCP/IP) connectivity and receipt printing
/// for network thermal printers using raw ESC/POS over TCP port 9100.
class WifiPrinterService {
  static const int defaultPort = 9100;
  static const Duration _connectTimeout = Duration(seconds: 4);

  static const String _prefPrinterIp = 'wifi_printer_ip';
  static const String _prefPrinterPort = 'wifi_printer_port';

  /// Saves the last-used WiFi printer configuration.
  static Future<void> savePrinterConfig({
    required String ip,
    int port = defaultPort,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefPrinterIp, ip.trim());
    await prefs.setInt(_prefPrinterPort, port);
  }

  /// Gets the saved printer IP address.
  static Future<String?> getSavedIp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefPrinterIp);
  }

  /// Gets the saved printer port.
  static Future<int> getSavedPort() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefPrinterPort) ?? defaultPort;
  }

  /// Tests connectivity to a specific printer IP and port.
  static Future<bool> testConnection(String ip, {int port = defaultPort}) async {
    final cleanIp = ip.trim();
    if (cleanIp.isEmpty) return false;
    try {
      final socket = await Socket.connect(cleanIp, port, timeout: _connectTimeout);
      await socket.close();
      return true;
    } catch (e) {
      debugPrint('⚠️ WiFi printer test failed ($cleanIp:$port): $e');
      return false;
    }
  }

  /// Sends raw ESC/POS bytes to the printer over a TCP socket.
  static Future<bool> sendBytes({
    required String ip,
    required List<int> bytes,
    int port = defaultPort,
  }) async {
    Socket? socket;
    final cleanIp = ip.trim();
    try {
      socket = await Socket.connect(cleanIp, port, timeout: _connectTimeout);
      socket.add(bytes);
      await socket.flush();
      await Future.delayed(const Duration(milliseconds: 400));
      await socket.close();
      debugPrint('✅ Sent ${bytes.length} bytes to $cleanIp:$port over WiFi');
      return true;
    } catch (e) {
      debugPrint('⚠️ Error sending bytes to $cleanIp:$port: $e');
      return false;
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  /// Generates the ESC/POS receipt bytes and prints them over WiFi.
  static Future<bool> printReceipt({
    required String ip,
    int port = defaultPort,
    required String documentNo,
    required DateTime documentDate,
    required Map<String, dynamic> customer,
    required List<Map<String, dynamic>> rows,
    required double subtotal,
    required double billDiscountAmount,
    required double discountedAmount,
    required double taxAmount,
    required double netAmount,
    String? remarks,
    String? salesmanName,
    List<Map<String, dynamic>>? payments,
    Map<String, dynamic>? paymentDetails,
    String documentTitle = '*** SALES INVOICE RECEIPT ***',
    String documentNoLabel = 'Inv No',
  }) async {
    try {
      final bytes = await ReceiptPrinterService.generateReceiptBytes(
        documentNo: documentNo,
        documentDate: documentDate,
        customer: customer,
        rows: rows,
        subtotal: subtotal,
        billDiscountAmount: billDiscountAmount,
        discountedAmount: discountedAmount,
        taxAmount: taxAmount,
        netAmount: netAmount,
        remarks: remarks,
        salesmanName: salesmanName,
        payments: payments,
        paymentDetails: paymentDetails,
        documentTitle: documentTitle,
        documentNoLabel: documentNoLabel,
      );

      final success = await sendBytes(ip: ip, bytes: bytes, port: port);
      if (success) {
        await savePrinterConfig(ip: ip, port: port);
      }
      return success;
    } catch (e) {
      debugPrint('⚠️ WiFi printReceipt failed: $e');
      return false;
    }
  }

  /// Detects the local subnet prefix (e.g. 192.168.1) from active network interfaces.
  static Future<String?> getLocalSubnet() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.contains('lo') || name.contains('rmnet')) continue;
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4 && !addr.isLoopback) {
            return '${parts[0]}.${parts[1]}.${parts[2]}';
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Could not determine local subnet: $e');
    }
    return null;
  }

  /// Scans the local subnet for devices with port 9100 open.
  static Future<List<String>> scanSubnet(
    String subnetPrefix, {
    int port = defaultPort,
  }) async {
    final responsive = <String>[];
    final tasks = <Future<void>>[];

    for (int i = 1; i <= 254; i++) {
      final targetIp = '$subnetPrefix.$i';
      tasks.add(
        _probe(targetIp, port).then((isOpen) {
          if (isOpen) responsive.add(targetIp);
        }),
      );
    }

    await Future.wait(tasks);
    return responsive;
  }

  static Future<bool> _probe(String ip, int port) async {
    try {
      final s = await Socket.connect(ip, port, timeout: const Duration(seconds: 2));
      await s.close();
      return true;
    } catch (_) {
      return false;
    }
  }
}


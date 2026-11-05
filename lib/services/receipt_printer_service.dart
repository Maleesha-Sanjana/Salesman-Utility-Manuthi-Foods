import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'company_info.dart';
import 'wifi_printer_service.dart';
import '../utils/payment_utils.dart';

/// Service to handle Bluetooth connectivity and receipt printing for
/// portable thermal printers, specifically optimized for the GOOJPRT PT-210
/// (58mm paper, 48mm print width, 384 dots/line, 32 characters per line).
class ReceiptPrinterService {
  static const String _prefLastPrinterMac = 'last_receipt_printer_mac';
  static const String _prefLastPrinterName = 'last_receipt_printer_name';
  static const int _receiptColumns = 32; // 48mm printable width Font A

  static final NumberFormat _money = NumberFormat('#,##0.00');
  static final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  // ---------------------------------------------------------------------------
  // Bluetooth Permissions & Status
  // ---------------------------------------------------------------------------

  /// Request runtime permissions for Bluetooth connect and scan.
  static Future<bool> requestBluetoothPermissions() async {
    try {
      final statuses = await [
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.locationWhenInUse,
      ].request();

      final connectGranted =
          statuses[Permission.bluetoothConnect]?.isGranted ?? true;
      final scanGranted =
          statuses[Permission.bluetoothScan]?.isGranted ?? true;

      final isGranted =
          await PrintBluetoothThermal.isPermissionBluetoothGranted;
      return (connectGranted && scanGranted) || isGranted;
    } catch (e) {
      debugPrint('⚠️ Error requesting bluetooth permissions: $e');
      return await PrintBluetoothThermal.isPermissionBluetoothGranted;
    }
  }

  /// Checks if device Bluetooth is turned on.
  static Future<bool> isBluetoothEnabled() async {
    try {
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (e) {
      debugPrint('⚠️ Error checking bluetooth enabled: $e');
      return false;
    }
  }

  /// Checks if printer is currently connected.
  static Future<bool> isPrinterConnected() async {
    try {
      return await PrintBluetoothThermal.connectionStatus;
    } catch (e) {
      debugPrint('⚠️ Error checking connection status: $e');
      return false;
    }
  }

  /// Fetches paired Bluetooth devices.
  static Future<List<BluetoothInfo>> getPairedDevices() async {
    try {
      final hasPerm = await requestBluetoothPermissions();
      if (!hasPerm) {
        debugPrint('⚠️ Bluetooth permission not granted');
      }
      return await PrintBluetoothThermal.pairedBluetooths;
    } catch (e) {
      debugPrint('⚠️ Error fetching paired devices: $e');
      return [];
    }
  }

  /// Connects to a specific printer by MAC address.
  static Future<bool> connectPrinter({
    required String macAddress,
    String? printerName,
  }) async {
    try {
      final connected =
          await PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
      if (connected) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefLastPrinterMac, macAddress);
        if (printerName != null && printerName.isNotEmpty) {
          await prefs.setString(_prefLastPrinterName, printerName);
        }
        debugPrint('✅ Connected to printer: $printerName ($macAddress)');
      }
      return connected;
    } catch (e) {
      debugPrint('⚠️ Error connecting to printer: $e');
      return false;
    }
  }

  /// Disconnects from current printer.
  static Future<bool> disconnectPrinter() async {
    try {
      return await PrintBluetoothThermal.disconnect;
    } catch (e) {
      debugPrint('⚠️ Error disconnecting printer: $e');
      return false;
    }
  }

  /// Gets saved printer MAC address.
  static Future<String?> getLastConnectedMac() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefLastPrinterMac);
  }

  /// Gets saved printer name.
  static Future<String?> getLastConnectedName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefLastPrinterName);
  }

  // ---------------------------------------------------------------------------
  // Receipt Data Helpers
  // ---------------------------------------------------------------------------

  static String _padBetween(String left, String right, [int width = _receiptColumns]) {
    final total = left.length + right.length;
    if (total >= width) {
      return '$left $right';
    }
    final spaces = ' ' * (width - total);
    return '$left$spaces$right';
  }

  static String _center(String text, [int width = _receiptColumns]) {
    if (text.length >= width) return text;
    final leftPadding = (width - text.length) ~/ 2;
    final rightPadding = width - text.length - leftPadding;
    return (' ' * leftPadding) + text + (' ' * rightPadding);
  }

  static String _divider([int width = _receiptColumns, String char = '-']) {
    return char * width;
  }

  static List<String> _wrapWords(String text, int width) {
    if (text.length <= width) return [text];
    final words = text.split(' ');
    final lines = <String>[];
    var current = StringBuffer();

    for (final word in words) {
      if (word.isEmpty) continue;
      if (current.isEmpty) {
        current.write(word);
      } else if (current.length + 1 + word.length <= width) {
        current.write(' $word');
      } else {
        lines.add(current.toString());
        current = StringBuffer(word);
      }
    }
    if (current.isNotEmpty) {
      lines.add(current.toString());
    }
    return lines;
  }

  static String _productName(Map<String, dynamic> row) {
    final name = row['name']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;
    final desc = row['description']?.toString().trim() ?? '';
    if (desc.isNotEmpty) return desc;
    final item = row['item']?.toString().trim() ?? '';
    if (item.contains('•')) {
      return item.split('•').skip(1).join('•').trim();
    }
    return item.isNotEmpty ? item : (row['code']?.toString() ?? 'Item');
  }

  static double _lineDiscountAmount(
    Map<String, dynamic> row,
    double price,
    double qty,
  ) {
    final raw = row['discount']?.toString() ?? '0';
    final numeric =
        double.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
    if (numeric <= 0) return 0.0;
    if (raw.contains('%')) return price * qty * (numeric / 100);
    return numeric;
  }

  // ---------------------------------------------------------------------------
  // Plain Text Receipt (for Screen Preview and Monospaced Slip)
  // ---------------------------------------------------------------------------

  static String generateReceiptText({
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
  }) {
    final sb = StringBuffer();

    // Company Header
    sb.writeln(_center(CompanyInfo.name));
    sb.writeln(_center(CompanyInfo.addressLine1));
    sb.writeln(_center(CompanyInfo.addressLine2));
    sb.writeln(_center('Tel: ${CompanyInfo.phone}'));
    sb.writeln(_divider());
    sb.writeln(_center(documentTitle));
    sb.writeln(_divider());

    // Invoice Meta
    sb.writeln('${documentNoLabel.padRight(8)}: $documentNo');
    sb.writeln('Date    : ${_dateFormat.format(documentDate)}');

    final cusCode = customer['code']?.toString().trim() ??
        customer['CusCode']?.toString().trim() ??
        '';
    final cusName = customer['name']?.toString().trim() ??
        customer['CusName']?.toString().trim() ??
        '';
    if (cusCode.isNotEmpty || cusName.isNotEmpty) {
      final combined = cusCode.isNotEmpty && cusName.isNotEmpty
          ? 'Customer: $cusCode - $cusName'
          : 'Customer: ${cusCode.isNotEmpty ? cusCode : cusName}';
      if (combined.length <= _receiptColumns) {
        sb.writeln(combined);
      } else {
        if (cusCode.isNotEmpty) sb.writeln('Customer: $cusCode');
        for (final l in _wrapWords(cusName, _receiptColumns)) {
          sb.writeln(l);
        }
      }
    }

    if (salesmanName != null && salesmanName.trim().isNotEmpty) {
      final line = 'Salesman: ${salesmanName.trim()}';
      if (line.length <= _receiptColumns) {
        sb.writeln(line);
      } else {
        for (final l in _wrapWords(line, _receiptColumns)) {
          sb.writeln(l);
        }
      }
    }
    sb.writeln(_divider());

    // Columns
    sb.writeln('ITEM              QTY      TOTAL');
    sb.writeln(_divider());

    // Rows
    for (final row in rows) {
      final name = _productName(row);
      final qty = (row['qty'] as num?)?.toDouble() ??
          (row['quantity'] as num?)?.toDouble() ??
          1.0;
      final price = (row['price'] as num?)?.toDouble() ?? 0.0;
      final discount = _lineDiscountAmount(row, price, qty);
      final lineTotal = (price * qty) - discount;

      // Item description
      if (name.length <= _receiptColumns) {
        sb.writeln(name);
      } else {
        for (final l in _wrapWords(name, _receiptColumns)) {
          sb.writeln(l);
        }
      }

      // Qty x Price and Line Total
      final qtyStr = '${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)} x ${_money.format(price)}';
      final totalStr = _money.format(lineTotal);
      sb.writeln(_padBetween('  $qtyStr', totalStr));

      if (discount > 0) {
        sb.writeln('  (Disc: -Rs. ${_money.format(discount)})');
      }

      final freeQty = (row['freeQty'] as num?)?.toInt() ?? 0;
      if (freeQty > 0) {
        sb.writeln('  (Free Qty: $freeQty)');
      }
    }

    sb.writeln(_divider());

    // Totals
    sb.writeln(_padBetween('Gross Subtotal:', 'Rs. ${_money.format(subtotal)}'));

    if (billDiscountAmount > 0) {
      sb.writeln(_padBetween(
        'Bill Discount:',
        '-Rs. ${_money.format(billDiscountAmount)}',
      ));
    }

    if (taxAmount > 0) {
      sb.writeln(_padBetween('Tax:', 'Rs. ${_money.format(taxAmount)}'));
    }

    sb.writeln(_divider(_receiptColumns, '='));
    sb.writeln(_padBetween('NET TOTAL:', 'Rs. ${_money.format(netAmount)}'));
    sb.writeln(_divider(_receiptColumns, '='));

    // Payment breakdown
    final paymentRows = payments == null || payments.isEmpty
        ? const <Map<String, String>>[]
        : PaymentUtils.buildPdfPaymentRows(
            payments: payments,
            paymentDetails: paymentDetails,
          );

    if (paymentRows.isNotEmpty) {
      sb.writeln('PAYMENT DETAILS:');
      for (final p in paymentRows) {
        final type = p['type'] ?? p['description'] ?? 'Payment';
        final rawAmt = p['amount'] ?? '';
        final amt = rawAmt.startsWith('Rs.') || rawAmt.isEmpty ? rawAmt : 'Rs. $rawAmt';
        sb.writeln(_padBetween('  $type', amt));

        final details = p['details'];
        if (details != null && details.trim().isNotEmpty) {
          final detailParts = details.split('•').map((e) => e.trim()).where((e) => e.isNotEmpty);
          for (final part in detailParts) {
            for (final line in _wrapWords('    $part', _receiptColumns)) {
              sb.writeln(line);
            }
          }
        }
      }
      sb.writeln(_divider());
    }

    if (remarks != null && remarks.trim().isNotEmpty) {
      sb.writeln('Remarks:');
      for (final line in _wrapWords('  ${remarks.trim()}', _receiptColumns)) {
        sb.writeln(line);
      }
      sb.writeln(_divider());
    }

    // Footer
    sb.writeln(_center('Thank You'));
    sb.writeln(_center('System By Jazz Business'));
    sb.writeln(_center('Solutions (Pvt) Ltd.'));

    return sb.toString();
  }

  // ---------------------------------------------------------------------------
  // ESC/POS Commands (48mm / 58mm Thermal Printer)
  // ---------------------------------------------------------------------------

  /// Generates ESC/POS command byte array optimized for GOOJPRT PT-210.
  static Future<List<int>> generateReceiptBytes({
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
    List<int> bytes = [];

    CapabilityProfile? profile;
    try {
      profile = await CapabilityProfile.load();
    } catch (e) {
      debugPrint('⚠️ Could not load default CapabilityProfile: $e');
    }

    final generator = Generator(
      PaperSize.mm58,
      profile ?? (throw Exception('Failed to initialize ESC/POS profile')),
    );

    // Initialize & clear
    bytes += generator.reset();

    // 1. Header (Company details)
    bytes += generator.text(
      CompanyInfo.name,
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
      ),
    );
    bytes += generator.text(
      CompanyInfo.addressLine1,
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.text(
      CompanyInfo.addressLine2,
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.text(
      'Tel: ${CompanyInfo.phone}',
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.hr();

    // 2. Receipt Title
    bytes += generator.text(
      documentTitle,
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
      ),
    );
    bytes += generator.hr();

    // 3. Invoice Meta
    bytes += generator.text('${documentNoLabel.padRight(8)}: $documentNo');
    bytes += generator.text('Date    : ${_dateFormat.format(documentDate)}');

    final cusCode = customer['code']?.toString().trim() ??
        customer['CusCode']?.toString().trim() ??
        '';
    final cusName = customer['name']?.toString().trim() ??
        customer['CusName']?.toString().trim() ??
        '';
    if (cusCode.isNotEmpty || cusName.isNotEmpty) {
      bytes += generator.text('Customer: $cusCode - $cusName');
    }

    if (salesmanName != null && salesmanName.trim().isNotEmpty) {
      bytes += generator.text('Salesman: ${salesmanName.trim()}');
    }
    bytes += generator.hr();

    // 4. Line Items Table Header
    bytes += generator.row([
      PosColumn(
        text: 'ITEM',
        width: 6,
        styles: const PosStyles(bold: true),
      ),
      PosColumn(
        text: 'QTY',
        width: 2,
        styles: const PosStyles(bold: true, align: PosAlign.center),
      ),
      PosColumn(
        text: 'TOTAL',
        width: 4,
        styles: const PosStyles(bold: true, align: PosAlign.right),
      ),
    ]);
    bytes += generator.hr();

    // 5. Line items
    for (final row in rows) {
      final name = _productName(row);
      final qty = (row['qty'] as num?)?.toDouble() ??
          (row['quantity'] as num?)?.toDouble() ??
          1.0;
      final price = (row['price'] as num?)?.toDouble() ?? 0.0;
      final discount = _lineDiscountAmount(row, price, qty);
      final lineTotal = (price * qty) - discount;

      // Item Name
      bytes += generator.text(name, styles: const PosStyles(bold: true));

      // Qty x Price and Line Total
      final qtyText = qty % 1 == 0 ? qty.toInt().toString() : qty.toStringAsFixed(2);
      final rateText = '$qtyText x ${_money.format(price)}';
      bytes += generator.row([
        PosColumn(
          text: '  $rateText',
          width: 8,
        ),
        PosColumn(
          text: _money.format(lineTotal),
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);

      if (discount > 0) {
        bytes += generator.text(
          '  Disc: -Rs. ${_money.format(discount)}',
          styles: const PosStyles(fontType: PosFontType.fontB),
        );
      }

      final freeQty = (row['freeQty'] as num?)?.toInt() ?? 0;
      if (freeQty > 0) {
        bytes += generator.text(
          '  Free Qty: $freeQty',
          styles: const PosStyles(fontType: PosFontType.fontB),
        );
      }
    }

    bytes += generator.hr();

    // 6. Summary Totals
    bytes += generator.row([
      PosColumn(text: 'Gross Subtotal:', width: 7),
      PosColumn(
        text: 'Rs. ${_money.format(subtotal)}',
        width: 5,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);

    if (billDiscountAmount > 0) {
      bytes += generator.row([
        PosColumn(text: 'Bill Discount:', width: 7),
        PosColumn(
          text: '-Rs. ${_money.format(billDiscountAmount)}',
          width: 5,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    if (taxAmount > 0) {
      bytes += generator.row([
        PosColumn(text: 'Tax Amount:', width: 7),
        PosColumn(
          text: 'Rs. ${_money.format(taxAmount)}',
          width: 5,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    bytes += generator.hr(ch: '=');
    bytes += generator.row([
      PosColumn(
        text: 'NET TOTAL:',
        width: 6,
        styles: const PosStyles(bold: true, height: PosTextSize.size2),
      ),
      PosColumn(
        text: 'Rs. ${_money.format(netAmount)}',
        width: 6,
        styles: const PosStyles(
          bold: true,
          align: PosAlign.right,
          height: PosTextSize.size2,
        ),
      ),
    ]);
    bytes += generator.hr(ch: '=');

    // 7. Payment details
    final paymentRows = payments == null || payments.isEmpty
        ? const <Map<String, String>>[]
        : PaymentUtils.buildPdfPaymentRows(
            payments: payments,
            paymentDetails: paymentDetails,
          );

    if (paymentRows.isNotEmpty) {
      bytes += generator.text(
        'PAYMENT DETAILS:',
        styles: const PosStyles(bold: true),
      );
      for (final p in paymentRows) {
        final type = p['type'] ?? p['description'] ?? 'Payment';
        final rawAmt = p['amount'] ?? '';
        final amt = rawAmt.startsWith('Rs.') || rawAmt.isEmpty ? rawAmt : 'Rs. $rawAmt';
        bytes += generator.row([
          PosColumn(text: '  $type', width: 7, styles: const PosStyles(bold: true)),
          PosColumn(
            text: amt,
            width: 5,
            styles: const PosStyles(align: PosAlign.right, bold: true),
          ),
        ]);

        final details = p['details'];
        if (details != null && details.trim().isNotEmpty) {
          final detailParts = details.split('•').map((e) => e.trim()).where((e) => e.isNotEmpty);
          for (final part in detailParts) {
            bytes += generator.text(
              '    $part',
              styles: const PosStyles(fontType: PosFontType.fontB),
            );
          }
        }
      }
      bytes += generator.hr();
    }

    if (remarks != null && remarks.trim().isNotEmpty) {
      bytes += generator.text('Remarks: ${remarks.trim()}');
      bytes += generator.hr();
    }

    // 8. Footer
    bytes += generator.text(
      'Thank You',
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    bytes += generator.text(
      'System By Jazz Business',
      styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB),
    );
    bytes += generator.text(
      'Solutions (Pvt) Ltd.',
      styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB),
    );

    // 9. Feed paper past the PT-210 manual tear bar (no cut command; PT-210 has no auto-cutter)
    bytes += generator.feed(2);

    return bytes;
  }

  // ---------------------------------------------------------------------------
  // Direct Print Operation
  // ---------------------------------------------------------------------------

  /// Sends the formatted receipt bytes to the connected Bluetooth printer.
  static Future<bool> printReceipt({
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
      final isConnected = await PrintBluetoothThermal.connectionStatus;
      if (!isConnected) {
        debugPrint('⚠️ Printer not connected');
        return false;
      }

      final bytes = await generateReceiptBytes(
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

      // Send bytes in 256-byte chunks with short delay so PT-210 hardware buffer
      // never overflows or drops footer commands
      const chunkSize = 256;
      bool result = true;
      for (int i = 0; i < bytes.length; i += chunkSize) {
        final end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        final chunk = bytes.sublist(i, end);
        final chunkOk = await PrintBluetoothThermal.writeBytes(chunk);
        if (!chunkOk) result = false;
        await Future.delayed(const Duration(milliseconds: 30));
      }
      debugPrint('🖨️ Receipt sent to printer in chunks. Result: $result');
      return result;
    } catch (e) {
      debugPrint('⚠️ Error printing receipt: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // User-Facing UI Dialog: Connect & Print Receipt
  // ---------------------------------------------------------------------------

  /// Displays the interactive receipt generator modal with printer selector,
  /// connection status, slip preview, and one-tap print button.
  static Future<void> showPrintReceiptDialog({
    required BuildContext context,
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
    final receiptPreview = generateReceiptText(
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

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _ReceiptPrinterBottomSheet(
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
          receiptPreview: receiptPreview,
          documentTitle: documentTitle,
          documentNoLabel: documentNoLabel,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Stateful Bottom Sheet Widget
// ---------------------------------------------------------------------------

class _ReceiptPrinterBottomSheet extends StatefulWidget {
  final String documentNo;
  final DateTime documentDate;
  final Map<String, dynamic> customer;
  final List<Map<String, dynamic>> rows;
  final double subtotal;
  final double billDiscountAmount;
  final double discountedAmount;
  final double taxAmount;
  final double netAmount;
  final String? remarks;
  final String? salesmanName;
  final List<Map<String, dynamic>>? payments;
  final Map<String, dynamic>? paymentDetails;
  final String receiptPreview;
  final String documentTitle;
  final String documentNoLabel;

  const _ReceiptPrinterBottomSheet({
    required this.documentNo,
    required this.documentDate,
    required this.customer,
    required this.rows,
    required this.subtotal,
    required this.billDiscountAmount,
    required this.discountedAmount,
    required this.taxAmount,
    required this.netAmount,
    this.remarks,
    this.salesmanName,
    this.payments,
    this.paymentDetails,
    required this.receiptPreview,
    this.documentTitle = '*** SALES INVOICE RECEIPT ***',
    this.documentNoLabel = 'Inv No',
  });

  @override
  State<_ReceiptPrinterBottomSheet> createState() =>
      _ReceiptPrinterBottomSheetState();
}

class _ReceiptPrinterBottomSheetState
    extends State<_ReceiptPrinterBottomSheet> {
  // Connection Mode (0 = Bluetooth, 1 = WiFi)
  int _connectionMode = 0;

  // Bluetooth state
  List<BluetoothInfo> _devices = [];
  BluetoothInfo? _selectedDevice;
  bool _isLoadingDevices = false;
  bool _isConnecting = false;
  bool _isPrinting = false;
  bool _isConnected = false;
  String? _statusMessage;
  bool _showPreview = false;

  // WiFi state
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(text: '9100');
  bool _isTestingWifi = false;
  bool _isWifiConnected = false;
  bool _isScanningWifi = false;
  List<String> _scannedIps = [];

  @override
  void initState() {
    super.initState();
    _initPrinter();
    _initWifi();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _initWifi() async {
    final savedIp = await WifiPrinterService.getSavedIp();
    final savedPort = await WifiPrinterService.getSavedPort();
    if (savedIp != null && savedIp.isNotEmpty) {
      if (mounted) {
        setState(() {
          _ipController.text = savedIp;
          _portController.text = savedPort.toString();
        });
        _testWifi(silent: true);
      }
    }
  }

  Future<void> _testWifi({bool silent = false}) async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 9100;
    if (ip.isEmpty) {
      if (!silent) {
        setState(() => _statusMessage = 'Please enter printer IP address');
      }
      return;
    }

    setState(() {
      _isTestingWifi = true;
      if (!silent) _statusMessage = 'Connecting to $ip:$port...';
    });

    final ok = await WifiPrinterService.testConnection(ip, port: port);
    if (mounted) {
      setState(() {
        _isTestingWifi = false;
        _isWifiConnected = ok;
        if (!silent) {
          _statusMessage = ok
              ? '✅ WiFi Printer connected ($ip:$port)'
              : '❌ Cannot reach printer at $ip:$port';
        }
      });
      if (ok) {
        await WifiPrinterService.savePrinterConfig(ip: ip, port: port);
      }
    }
  }

  Future<void> _scanWifi() async {
    setState(() {
      _isScanningWifi = true;
      _scannedIps = [];
      _statusMessage = 'Scanning local network on port 9100...';
    });

    try {
      final subnet = await WifiPrinterService.getLocalSubnet();
      if (subnet == null) {
        if (mounted) {
          setState(() {
            _isScanningWifi = false;
            _statusMessage = 'Could not detect WiFi subnet. Make sure WiFi is on.';
          });
        }
        return;
      }

      final port = int.tryParse(_portController.text.trim()) ?? 9100;
      final found = await WifiPrinterService.scanSubnet(subnet, port: port);
      if (mounted) {
        setState(() {
          _isScanningWifi = false;
          _scannedIps = found;
          if (found.isEmpty) {
            _statusMessage = 'No printers found on $subnet.x:9100';
          } else {
            _ipController.text = found.first;
            _statusMessage = 'Found ${found.length} printer(s)';
            _testWifi(silent: true);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanningWifi = false;
          _statusMessage = 'Scan error: $e';
        });
      }
    }
  }

  Future<void> _printViaWifi() async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 9100;
    if (ip.isEmpty) {
      setState(() => _statusMessage = 'Please enter printer IP address');
      return;
    }

    setState(() {
      _isPrinting = true;
      _statusMessage = 'Sending receipt to $ip:$port...';
    });

    try {
      final success = await WifiPrinterService.printReceipt(
        ip: ip,
        port: port,
        documentNo: widget.documentNo,
        documentDate: widget.documentDate,
        customer: widget.customer,
        rows: widget.rows,
        subtotal: widget.subtotal,
        billDiscountAmount: widget.billDiscountAmount,
        discountedAmount: widget.discountedAmount,
        taxAmount: widget.taxAmount,
        netAmount: widget.netAmount,
        remarks: widget.remarks,
        salesmanName: widget.salesmanName,
        payments: widget.payments,
        paymentDetails: widget.paymentDetails,
        documentTitle: widget.documentTitle,
        documentNoLabel: widget.documentNoLabel,
      );

      if (mounted) {
        setState(() {
          _isPrinting = false;
          _statusMessage = success
              ? 'Receipt printed successfully via WiFi! ✅'
              : 'Failed to print. Check printer IP & connection.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPrinting = false;
          _statusMessage = 'Print error: $e';
        });
      }
    }
  }

  Future<void> _initPrinter() async {
    setState(() {
      _isLoadingDevices = true;
      _statusMessage = null;
    });

    try {
      final connected = await ReceiptPrinterService.isPrinterConnected();
      final devices = await ReceiptPrinterService.getPairedDevices();
      final lastMac = await ReceiptPrinterService.getLastConnectedMac();

      BluetoothInfo? match;
      if (lastMac != null && devices.isNotEmpty) {
        match = devices.firstWhere(
          (d) => d.macAdress == lastMac,
          orElse: () => devices.first,
        );
      } else if (devices.isNotEmpty) {
        // Prefer GOOJPRT / PT-210 device if found
        match = devices.firstWhere(
          (d) {
            final n = d.name.toUpperCase();
            return n.contains('PT-210') ||
                n.contains('PT210') ||
                n.contains('GOOJPRT') ||
                n.contains('MTP') ||
                n.contains('POS');
          },
          orElse: () => devices.first,
        );
      }

      if (mounted) {
        setState(() {
          _isConnected = connected;
          _devices = devices;
          _selectedDevice = match;
          _isLoadingDevices = false;
        });

        // Auto-connect if not connected and we found the saved printer
        if (!connected && match != null && lastMac != null && match.macAdress == lastMac) {
          _connectToDevice(match, auto: true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingDevices = false;
          _statusMessage = 'Bluetooth error: $e';
        });
      }
    }
  }

  Future<void> _connectToDevice(BluetoothInfo device, {bool auto = false}) async {
    setState(() {
      _isConnecting = true;
      _statusMessage = 'Connecting to ${device.name}...';
    });

    try {
      final success = await ReceiptPrinterService.connectPrinter(
        macAddress: device.macAdress,
        printerName: device.name,
      );

      if (mounted) {
        setState(() {
          _isConnected = success;
          _isConnecting = false;
          _statusMessage = success
              ? 'Connected to ${device.name}'
              : 'Failed to connect to ${device.name}. Please ensure printer is turned on.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _isConnected = false;
          _statusMessage = 'Connection error: $e';
        });
      }
    }
  }

  Future<void> _disconnect() async {
    await ReceiptPrinterService.disconnectPrinter();
    if (mounted) {
      setState(() {
        _isConnected = false;
        _statusMessage = 'Printer disconnected';
      });
    }
  }

  Future<void> _printReceipt() async {
    // If not connected, attempt connection to selected device first
    if (!_isConnected) {
      if (_selectedDevice == null) {
        setState(() {
          _statusMessage = 'Please select a Bluetooth printer first';
        });
        return;
      }

      setState(() {
        _isConnecting = true;
        _statusMessage = 'Connecting to ${_selectedDevice!.name}...';
      });

      final connected = await ReceiptPrinterService.connectPrinter(
        macAddress: _selectedDevice!.macAdress,
        printerName: _selectedDevice!.name,
      );

      if (!connected) {
        if (mounted) {
          setState(() {
            _isConnecting = false;
            _statusMessage =
                'Could not connect to ${_selectedDevice!.name}. Make sure it is paired & turned on.';
          });
        }
        return;
      }

      _isConnected = true;
      _isConnecting = false;
    }

    setState(() {
      _isPrinting = true;
      _statusMessage = 'Printing receipt to GOOJPRT PT-210...';
    });

    try {
      final success = await ReceiptPrinterService.printReceipt(
        documentNo: widget.documentNo,
        documentDate: widget.documentDate,
        customer: widget.customer,
        rows: widget.rows,
        subtotal: widget.subtotal,
        billDiscountAmount: widget.billDiscountAmount,
        discountedAmount: widget.discountedAmount,
        taxAmount: widget.taxAmount,
        netAmount: widget.netAmount,
        remarks: widget.remarks,
        salesmanName: widget.salesmanName,
        payments: widget.payments,
        paymentDetails: widget.paymentDetails,
        documentTitle: widget.documentTitle,
        documentNoLabel: widget.documentNoLabel,
      );

      if (mounted) {
        setState(() {
          _isPrinting = false;
          _statusMessage = success
              ? 'Receipt printed successfully! ✅'
              : 'Failed to print receipt. Please check printer paper.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPrinting = false;
          _statusMessage = 'Print error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.print_rounded, color: primaryColor, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'GOOJPRT Portable Printer',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'PT-210 • 48mm Print Width • 90mm/s',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),

          const Divider(height: 20),

          // Connection Mode Tabs: Bluetooth vs WiFi
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(3),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      setState(() {
                        _connectionMode = 0;
                        _statusMessage = null;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _connectionMode == 0 ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: _connectionMode == 0
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                )
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.bluetooth_rounded,
                            size: 18,
                            color: _connectionMode == 0 ? primaryColor : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Bluetooth (PT-210)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: _connectionMode == 0 ? FontWeight.bold : FontWeight.normal,
                              color: _connectionMode == 0 ? primaryColor : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      setState(() {
                        _connectionMode = 1;
                        _statusMessage = null;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _connectionMode == 1 ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: _connectionMode == 1
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                )
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.wifi_rounded,
                            size: 18,
                            color: _connectionMode == 1 ? primaryColor : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'WiFi (Network)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: _connectionMode == 1 ? FontWeight.bold : FontWeight.normal,
                              color: _connectionMode == 1 ? primaryColor : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // TAB 0: BLUETOOTH
          if (_connectionMode == 0) ...[
            // Connection Status Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _isConnected
                    ? Colors.green.shade50
                    : (_isConnecting ? Colors.blue.shade50 : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isConnected
                      ? Colors.green.shade300
                      : (_isConnecting
                          ? Colors.blue.shade300
                          : Colors.grey.shade300),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isConnected
                        ? Icons.bluetooth_connected_rounded
                        : (_isConnecting
                            ? Icons.bluetooth_searching_rounded
                            : Icons.bluetooth_disabled_rounded),
                    color: _isConnected
                        ? Colors.green.shade700
                        : (_isConnecting
                            ? Colors.blue.shade700
                            : Colors.grey.shade600),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isConnected
                          ? 'Connected: ${_selectedDevice?.name ?? 'Thermal Printer'}'
                          : (_isConnecting
                              ? 'Connecting...'
                              : 'Printer Not Connected'),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: _isConnected
                            ? Colors.green.shade800
                            : (_isConnecting
                                ? Colors.blue.shade800
                                : Colors.grey.shade700),
                      ),
                    ),
                  ),
                  if (_isConnected)
                    TextButton(
                      onPressed: _disconnect,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Disconnect', style: TextStyle(fontSize: 12)),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      tooltip: 'Refresh devices',
                      onPressed: _isLoadingDevices ? null : _initPrinter,
                    ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Printer Selector
            if (_isLoadingDevices) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              ),
            ] else if (_devices.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: Colors.amber.shade800),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No paired Bluetooth printers found. Please pair your GOOJPRT PT-210 in Android Bluetooth settings first.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              DropdownButtonFormField<BluetoothInfo>(
                initialValue: _selectedDevice,
                decoration: InputDecoration(
                  labelText: 'Select Bluetooth Printer',
                  prefixIcon: const Icon(Icons.print_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                items: _devices.map((device) {
                  final isPt210 = device.name.toUpperCase().contains('PT-210') ||
                      device.name.toUpperCase().contains('PT210') ||
                      device.name.toUpperCase().contains('GOOJPRT');
                  return DropdownMenuItem<BluetoothInfo>(
                    value: device,
                    child: Text(
                      isPt210
                          ? '⭐ ${device.name} (${device.macAdress})'
                          : '${device.name} (${device.macAdress})',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isPt210 ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (newDevice) {
                  if (newDevice != null) {
                    setState(() {
                      _selectedDevice = newDevice;
                      _isConnected = false;
                    });
                    _connectToDevice(newDevice);
                  }
                },
              ),
            ],
          ] else ...[
            // TAB 1: WIFI
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _isWifiConnected
                    ? Colors.green.shade50
                    : (_isTestingWifi ? Colors.blue.shade50 : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isWifiConnected
                      ? Colors.green.shade300
                      : (_isTestingWifi
                          ? Colors.blue.shade300
                          : Colors.grey.shade300),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isWifiConnected
                        ? Icons.wifi_rounded
                        : (_isTestingWifi
                            ? Icons.wifi_find_rounded
                            : Icons.wifi_off_rounded),
                    color: _isWifiConnected
                        ? Colors.green.shade700
                        : (_isTestingWifi
                            ? Colors.blue.shade700
                            : Colors.grey.shade600),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isWifiConnected
                          ? 'Connected: ${_ipController.text}:${_portController.text}'
                          : (_isTestingWifi
                              ? 'Testing connection...'
                              : 'WiFi Printer Not Connected'),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: _isWifiConnected
                            ? Colors.green.shade800
                            : (_isTestingWifi
                                ? Colors.blue.shade800
                                : Colors.grey.shade700),
                      ),
                    ),
                  ),
                  if (_isWifiConnected)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isWifiConnected = false;
                          _statusMessage = 'WiFi disconnected';
                        });
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Disconnect', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _ipController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Printer IP Address',
                      hintText: '192.168.1.100',
                      prefixIcon: const Icon(Icons.router_rounded, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (_) {
                      if (_isWifiConnected) {
                        setState(() => _isWifiConnected = false);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Port',
                      hintText: '9100',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isScanningWifi ? null : _scanWifi,
                    icon: _isScanningWifi
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.radar_rounded, size: 16),
                    label: Text(
                      _isScanningWifi ? 'Scanning...' : 'Scan Subnet',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isTestingWifi ? null : () => _testWifi(),
                    icon: _isTestingWifi
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline_rounded, size: 16),
                    label: Text(
                      _isTestingWifi ? 'Testing...' : 'Test Connection',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],

          if (_statusMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _statusMessage!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _statusMessage!.contains('successfully')
                    ? Colors.green.shade700
                    : (_statusMessage!.contains('Error') ||
                            _statusMessage!.contains('Failed')
                        ? Colors.red.shade700
                        : Colors.grey.shade700),
              ),
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: 10),

          // Toggle Slip Preview
          InkWell(
            onTap: () {
              setState(() {
                _showPreview = !_showPreview;
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _showPreview
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: primaryColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _showPreview ? 'Hide Receipt Slip' : 'Preview 48mm Receipt Slip',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_showPreview) ...[
            const SizedBox(height: 8),
            Flexible(
              child: Center(
                child: Container(
                  width: 300,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCFAF5), // stylized receipt paper color
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: FittedBox(
                      fit: BoxFit.fitWidth,
                      child: Text(
                        widget.receiptPreview,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          letterSpacing: 0,
                          height: 1.32,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Action Button: Print Receipt
          FilledButton.icon(
            onPressed: (_isPrinting || _isConnecting || _isTestingWifi || _isScanningWifi)
                ? null
                : (_connectionMode == 0 ? _printReceipt : _printViaWifi),
            icon: _isPrinting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(_connectionMode == 0 ? Icons.print_rounded : Icons.wifi_rounded),
            label: Text(
              _isPrinting
                  ? 'Sending to printer...'
                  : (_connectionMode == 0
                      ? (_isConnected ? 'Print Receipt (Bluetooth)' : 'Connect & Print (Bluetooth)')
                      : (_isWifiConnected ? 'Print Receipt (WiFi)' : 'Connect & Print (WiFi)')),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: (_connectionMode == 0 ? _isConnected : _isWifiConnected)
                  ? Colors.green.shade600
                  : primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

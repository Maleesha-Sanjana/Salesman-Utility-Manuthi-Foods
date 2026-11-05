import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/receipt_printer_service.dart';
import '../../services/rep_document_recall_service.dart';
import 'super_admin_back_button.dart';

enum DocumentReceiptKind {
  invoice('Invoice', '*** SALES INVOICE RECEIPT ***', 'Inv No', Icons.receipt_long_rounded),
  salesOrder('Sales Order', '*** SALES ORDER RECEIPT ***', 'Order No', Icons.shopping_cart_checkout_rounded),
  quotation('Quotation', '*** QUOTATION RECEIPT ***', 'Quot No', Icons.request_quote_rounded),
  crn('CRN (Return)', '*** CREDIT RETURN NOTE (CRN) ***', 'CRN No', Icons.assignment_return_rounded),
  collectionReceipt('Payment Receipt', '*** PAYMENT RECEIPT ***', 'Rcpt No', Icons.payments_rounded);

  final String label;
  final String title;
  final String noLabel;
  final IconData icon;
  const DocumentReceiptKind(this.label, this.title, this.noLabel, this.icon);
}

class SuperAdminReceiptLayoutPage extends StatefulWidget {
  const SuperAdminReceiptLayoutPage({super.key, this.appBarLeading});

  final Widget? appBarLeading;

  @override
  State<SuperAdminReceiptLayoutPage> createState() =>
      _SuperAdminReceiptLayoutPageState();
}

class _SuperAdminReceiptLayoutPageState
    extends State<SuperAdminReceiptLayoutPage> {
  DocumentReceiptKind _selectedKind = DocumentReceiptKind.invoice;

  // Layout customization toggles
  bool _includeDiscounts = true;
  bool _includeFreeQty = true;
  bool _includeMultiPayment = true;
  bool _includeRemarks = true;
  bool _includeTax = false;
  bool _showRawMonospace = false;

  // Custom live document recall state
  bool _isLoadingLiveDoc = false;
  String? _loadedDocNo;
  Map<String, dynamic>? _liveDocCustomer;
  List<Map<String, dynamic>>? _liveDocRows;
  double? _liveDocSubtotal;
  double? _liveDocBillDiscount;
  double? _liveDocTax;
  double? _liveDocNet;
  String? _liveDocRemarks;
  List<Map<String, dynamic>>? _liveDocPayments;
  Map<String, dynamic>? _liveDocPaymentDetails;

  final TextEditingController _docNoController = TextEditingController();

  @override
  void dispose() {
    _docNoController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Sample Data Generators
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _getCustomer() {
    if (_liveDocCustomer != null) return _liveDocCustomer!;
    switch (_selectedKind) {
      case DocumentReceiptKind.invoice:
        return {
          'code': 'C0602',
          'name': 'Sampath Super Store',
          'address': 'No. 45, High Level Rd, Maharagama',
          'location': 'Maharagama',
        };
      case DocumentReceiptKind.salesOrder:
        return {
          'code': 'C0144',
          'name': 'Wickrama Wholesale Center',
          'address': 'Main Street, Kandy',
          'location': 'Kandy',
        };
      case DocumentReceiptKind.quotation:
        return {
          'code': 'C0220',
          'name': 'Perera & Sons Mini Mart',
          'address': 'Galle Road, Dehiwala',
          'location': 'Dehiwala',
        };
      case DocumentReceiptKind.crn:
        return {
          'code': 'C0602',
          'name': 'Sampath Super Store',
          'address': 'No. 45, High Level Rd, Maharagama',
          'location': 'Maharagama',
        };
      case DocumentReceiptKind.collectionReceipt:
        return {
          'code': 'C0602',
          'name': 'Sampath Super Store',
          'address': 'No. 45, High Level Rd, Maharagama',
          'location': 'Maharagama',
        };
    }
  }

  List<Map<String, dynamic>> _getRows() {
    if (_liveDocRows != null) return _liveDocRows!;
    switch (_selectedKind) {
      case DocumentReceiptKind.invoice:
        return [
          {
            'code': 'P001',
            'name': 'Munchee Choc Cream 200g',
            'qty': 10.0,
            'price': 240.0,
            'discount': _includeDiscounts ? '5%' : '0',
            'freeQty': _includeFreeQty ? 1 : 0,
          },
          {
            'code': 'P002',
            'name': 'Munchee Super Marie 100g',
            'qty': 15.0,
            'price': 120.0,
            'discount': '0',
            'freeQty': 0,
          },
          {
            'code': 'P003',
            'name': 'Kist Mixed Fruit Jam 500g',
            'qty': 4.0,
            'price': 550.0,
            'discount': _includeDiscounts ? '100' : '0',
            'freeQty': 0,
          },
          {
            'code': 'P004',
            'name': 'Manuthi Roasted Curry 250g',
            'qty': 8.0,
            'price': 320.0,
            'discount': '0',
            'freeQty': _includeFreeQty ? 1 : 0,
          },
        ];
      case DocumentReceiptKind.salesOrder:
        return [
          {
            'code': 'P010',
            'name': 'Manuthi Chilli Powder 500g',
            'qty': 24.0,
            'price': 420.0,
            'discount': _includeDiscounts ? '2%' : '0',
            'freeQty': _includeFreeQty ? 2 : 0,
          },
          {
            'code': 'P011',
            'name': 'Manuthi Turmeric Powder 100g',
            'qty': 50.0,
            'price': 160.0,
            'discount': '0',
            'freeQty': 0,
          },
          {
            'code': 'P012',
            'name': 'Kist Tomato Sauce 400g',
            'qty': 12.0,
            'price': 380.0,
            'discount': '0',
            'freeQty': 0,
          },
        ];
      case DocumentReceiptKind.quotation:
        return [
          {
            'code': 'P020',
            'name': 'Manuthi Premium Curry Pack',
            'qty': 50.0,
            'price': 650.0,
            'discount': _includeDiscounts ? '5%' : '0',
            'freeQty': _includeFreeQty ? 5 : 0,
          },
          {
            'code': 'P021',
            'name': 'White Sugar Packet 1kg',
            'qty': 100.0,
            'price': 230.0,
            'discount': '0',
            'freeQty': 0,
          },
        ];
      case DocumentReceiptKind.crn:
        return [
          {
            'code': 'P001',
            'name': 'Munchee Choc Cream 200g (Exp)',
            'qty': 4.0,
            'price': 240.0,
            'discount': '0',
            'freeQty': 0,
          },
          {
            'code': 'P003',
            'name': 'Kist Mixed Fruit Jam (Damaged)',
            'qty': 2.0,
            'price': 550.0,
            'discount': '0',
            'freeQty': 0,
          },
        ];
      case DocumentReceiptKind.collectionReceipt:
        return [
          {
            'code': 'REC01',
            'name': 'Settlement of Invoice INV-00412',
            'qty': 1.0,
            'price': 7500.0,
            'discount': '0',
            'freeQty': 0,
          },
        ];
    }
  }

  String _getDocumentNo() {
    if (_loadedDocNo != null && _loadedDocNo!.isNotEmpty) {
      return _loadedDocNo!;
    }
    final now = DateTime.now();
    final year = now.year;
    switch (_selectedKind) {
      case DocumentReceiptKind.invoice:
        return 'INV-$year-00821';
      case DocumentReceiptKind.salesOrder:
        return 'SO-$year-00342';
      case DocumentReceiptKind.quotation:
        return 'QUO-$year-00105';
      case DocumentReceiptKind.crn:
        return 'CRN-$year-00049';
      case DocumentReceiptKind.collectionReceipt:
        return 'RCP-$year-00091';
    }
  }

  String _getSalesmanName() {
    final auth = context.read<AuthProvider>();
    if (auth.salesmanName.isNotEmpty) {
      return '${auth.salesmanName} (${auth.salesmanCode})';
    }
    return 'Kamal Silva (REP001)';
  }

  String? _getRemarks() {
    if (!_includeRemarks) return null;
    if (_liveDocRemarks != null && _liveDocRemarks!.isNotEmpty) {
      return _liveDocRemarks;
    }
    switch (_selectedKind) {
      case DocumentReceiptKind.invoice:
        return 'Thank you! Prompt delivery requested.';
      case DocumentReceiptKind.salesOrder:
        return 'PO Ref: PO-88492. Delivery on Monday.';
      case DocumentReceiptKind.quotation:
        return 'Valid for 14 days from issue date.';
      case DocumentReceiptKind.crn:
        return 'Returned due to near-expiry and package tear.';
      case DocumentReceiptKind.collectionReceipt:
        return 'Received with thanks. Balance settled.';
    }
  }

  double _calculateSubtotal(List<Map<String, dynamic>> rows) {
    if (_liveDocSubtotal != null) return _liveDocSubtotal!;
    double sum = 0.0;
    for (final row in rows) {
      final qty = (row['qty'] as num?)?.toDouble() ?? 1.0;
      final price = (row['price'] as num?)?.toDouble() ?? 0.0;
      sum += (price * qty);
    }
    return sum;
  }

  double _calculateLineDiscounts(List<Map<String, dynamic>> rows) {
    if (!_includeDiscounts) return 0.0;
    double sum = 0.0;
    for (final row in rows) {
      final qty = (row['qty'] as num?)?.toDouble() ?? 1.0;
      final price = (row['price'] as num?)?.toDouble() ?? 0.0;
      final raw = row['discount']?.toString() ?? '0';
      final val = double.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
      if (val > 0) {
        sum += raw.contains('%') ? (price * qty * val / 100) : val;
      }
    }
    return sum;
  }

  double _getBillDiscount() {
    if (!_includeDiscounts) return 0.0;
    if (_liveDocBillDiscount != null) return _liveDocBillDiscount!;
    return _selectedKind == DocumentReceiptKind.invoice ? 150.0 : 0.0;
  }

  double _getTax() {
    if (!_includeTax) return 0.0;
    if (_liveDocTax != null) return _liveDocTax!;
    return 120.0;
  }

  List<Map<String, dynamic>>? _getPayments(double netAmount) {
    if (_selectedKind != DocumentReceiptKind.invoice &&
        _selectedKind != DocumentReceiptKind.collectionReceipt) {
      return null;
    }
    if (_liveDocPayments != null) return _liveDocPayments;

    if (!_includeMultiPayment) {
      return [
        {
          'paymentCode': '001',
          'amount': netAmount,
        },
      ];
    }

    // Split payment: Cash + Cheque
    final cashAmount = (netAmount * 0.4).roundToDouble();
    final chequeAmount = netAmount - cashAmount;

    return [
      {
        'paymentCode': '001',
        'amount': cashAmount,
      },
      {
        'paymentCode': '007',
        'amount': chequeAmount,
        'chequeNo': '839201',
        'bankCode': '7010',
        'bankName': 'Bank of Ceylon',
        'branchCode': '001',
        'branchName': 'City Office',
        'chequeDate': DateFormat('yyyy-MM-dd').format(
          DateTime.now().add(const Duration(days: 14)),
        ),
      },
    ];
  }

  // ---------------------------------------------------------------------------
  // Receipt Text Computation
  // ---------------------------------------------------------------------------

  String _buildCurrentReceiptText() {
    final customer = _getCustomer();
    final rows = _getRows();
    final grossSubtotal = _calculateSubtotal(rows);
    final lineDiscounts = _calculateLineDiscounts(rows);
    final billDiscount = _getBillDiscount();
    final totalDiscount = lineDiscounts + billDiscount;
    final discountedAmount = grossSubtotal - totalDiscount;
    final tax = _getTax();
    final netAmount = _liveDocNet ?? (discountedAmount + tax);
    final payments = _getPayments(netAmount);

    return ReceiptPrinterService.generateReceiptText(
      documentNo: _getDocumentNo(),
      documentDate: DateTime.now(),
      customer: customer,
      rows: rows,
      subtotal: grossSubtotal,
      billDiscountAmount: billDiscount,
      discountedAmount: discountedAmount,
      taxAmount: tax,
      netAmount: netAmount,
      remarks: _getRemarks(),
      salesmanName: _getSalesmanName(),
      payments: payments,
      paymentDetails: _liveDocPaymentDetails,
      documentTitle: _selectedKind.title,
      documentNoLabel: _selectedKind.noLabel,
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _testPrintReceipt() async {
    final customer = _getCustomer();
    final rows = _getRows();
    final grossSubtotal = _calculateSubtotal(rows);
    final lineDiscounts = _calculateLineDiscounts(rows);
    final billDiscount = _getBillDiscount();
    final discountedAmount = grossSubtotal - (lineDiscounts + billDiscount);
    final tax = _getTax();
    final netAmount = _liveDocNet ?? (discountedAmount + tax);
    final payments = _getPayments(netAmount);

    await ReceiptPrinterService.showPrintReceiptDialog(
      context: context,
      documentNo: _getDocumentNo(),
      documentDate: DateTime.now(),
      customer: customer,
      rows: rows,
      subtotal: grossSubtotal,
      billDiscountAmount: billDiscount,
      discountedAmount: discountedAmount,
      taxAmount: tax,
      netAmount: netAmount,
      remarks: _getRemarks(),
      salesmanName: _getSalesmanName(),
      payments: payments,
      paymentDetails: _liveDocPaymentDetails,
      documentTitle: _selectedKind.title,
      documentNoLabel: _selectedKind.noLabel,
    );
  }

  void _copyReceiptText() {
    final text = _buildCurrentReceiptText();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Receipt text (32-column monospace) copied to clipboard!'),
        backgroundColor: Color(0xFF0284C7),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showRecallRealDocumentDialog() async {
    _docNoController.clear();
    String docType = 'invoice';
    switch (_selectedKind) {
      case DocumentReceiptKind.invoice:
        docType = 'invoice';
        break;
      case DocumentReceiptKind.salesOrder:
        docType = 'sales-order';
        break;
      case DocumentReceiptKind.quotation:
        docType = 'quotation';
        break;
      case DocumentReceiptKind.crn:
        docType = 'crn';
        break;
      case DocumentReceiptKind.collectionReceipt:
        docType = 'invoice';
        break;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Load Production Document'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Enter a document number from database to test the layout with live server data:',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: docType,
                    decoration: const InputDecoration(
                      labelText: 'Document Type',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'invoice', child: Text('Invoice (IN)')),
                      DropdownMenuItem(value: 'sales-order', child: Text('Sales Order (SO)')),
                      DropdownMenuItem(value: 'quotation', child: Text('Quotation (QUO)')),
                      DropdownMenuItem(value: 'crn', child: Text('Customer Return (CRN)')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => docType = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _docNoController,
                    decoration: const InputDecoration(
                      labelText: 'Document Number',
                      hintText: 'e.g. IN0001, SO0002, CRN0001',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    autofocus: true,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Fetch & Preview'),
                  onPressed: () {
                    final docNo = _docNoController.text.trim();
                    if (docNo.isEmpty) return;
                    Navigator.pop(dialogCtx);
                    _fetchAndApplyLiveDocument(docType, docNo);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _fetchAndApplyLiveDocument(String docType, String docNo) async {
    setState(() => _isLoadingLiveDoc = true);
    try {
      final recall = await RepDocumentRecallService.fetchRecall(
        documentType: docType,
        documentNo: docNo,
      );

      final header = Map<String, dynamic>.from(recall['header'] as Map? ?? {});
      final details = (recall['details'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      if (details.isEmpty) {
        throw Exception('No line items found for document $docNo');
      }

      final rows = details.map((d) {
        final qty = (d['Qty'] as num?)?.toDouble() ??
            (d['BQTY'] as num?)?.toDouble() ??
            1.0;
        final unitPrice = (d['UnitPrice'] as num?)?.toDouble() ?? 0.0;
        final name = d['ProductDescription']?.toString() ??
            d['ItemDescription']?.toString() ??
            d['ProductCode']?.toString() ??
            'Item';
        return {
          'code': d['ProductCode']?.toString() ?? '',
          'name': name,
          'qty': qty,
          'price': unitPrice,
          'discount': d['DiscPer']?.toString() ?? d['DiscAmount']?.toString() ?? '0',
          'freeQty': (d['FreeQty'] as num?)?.toInt() ?? 0,
        };
      }).toList();

      final gross = (header['GrossAmount'] as num?)?.toDouble() ?? 0.0;
      final disc = (header['DiscAmount'] as num?)?.toDouble() ?? 0.0;
      final tax = (header['TaxAmount'] as num?)?.toDouble() ?? 0.0;
      final net = (header['NetAmount'] as num?)?.toDouble() ?? (gross - disc + tax);

      DocumentReceiptKind targetKind;
      switch (docType) {
        case 'sales-order':
          targetKind = DocumentReceiptKind.salesOrder;
          break;
        case 'quotation':
          targetKind = DocumentReceiptKind.quotation;
          break;
        case 'crn':
          targetKind = DocumentReceiptKind.crn;
          break;
        case 'invoice':
        default:
          targetKind = DocumentReceiptKind.invoice;
          break;
      }

      if (!mounted) return;
      setState(() {
        _selectedKind = targetKind;
        _loadedDocNo = docNo;
        _liveDocCustomer = {
          'code': header['CustomerCode']?.toString() ?? '',
          'name': header['CustomerName']?.toString() ?? 'Customer',
          'address': header['CustomerAddress']?.toString() ?? '',
        };
        _liveDocRows = rows;
        _liveDocSubtotal = gross > 0 ? gross : net;
        _liveDocBillDiscount = disc;
        _liveDocTax = tax;
        _liveDocNet = net;
        _liveDocRemarks = header['Remarks']?.toString();
        _isLoadingLiveDoc = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Loaded $docNo (${rows.length} items) successfully!'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingLiveDoc = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load document: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _resetToSampleData() {
    setState(() {
      _loadedDocNo = null;
      _liveDocCustomer = null;
      _liveDocRows = null;
      _liveDocSubtotal = null;
      _liveDocBillDiscount = null;
      _liveDocTax = null;
      _liveDocNet = null;
      _liveDocRemarks = null;
      _liveDocPayments = null;
      _liveDocPaymentDetails = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reset to standard sample data.')),
    );
  }

  // ---------------------------------------------------------------------------
  // Build Methods
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final receiptText = _buildCurrentReceiptText();

    return Scaffold(
      appBar: AppBar(
        leading: widget.appBarLeading ?? superAdminBackButton(context),
        title: const Text('Receipt Layout View'),
        backgroundColor: const Color(0xFF0284C7).withValues(alpha: 0.08),
        actions: [
          IconButton(
            tooltip: 'Copy 32-col text',
            icon: const Icon(Icons.copy_rounded),
            onPressed: _copyReceiptText,
          ),
          IconButton(
            tooltip: 'Load document from server',
            icon: const Icon(Icons.cloud_download_rounded),
            onPressed: _showRecallRealDocumentDialog,
          ),
          IconButton(
            tooltip: 'Test Print to PT-210',
            icon: const Icon(Icons.print_rounded),
            onPressed: _testPrintReceipt,
          ),
        ],
      ),
      body: _isLoadingLiveDoc
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Fetching document details...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Hardware Specification Badge
                  _buildHardwareBadge(theme),
                  const SizedBox(height: 12),

                  // 2. Document Type Selector Tabs
                  _buildDocumentTypeSelector(theme),
                  const SizedBox(height: 12),

                  // 3. Layout Options & Toggles Card
                  _buildControlsCard(theme),
                  const SizedBox(height: 16),

                  // 4. Live Loaded Doc banner if active
                  if (_loadedDocNo != null) ...[
                    _buildActiveDocBanner(theme),
                    const SizedBox(height: 12),
                  ],

                  // 5. Action Buttons (Print & Copy)
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _testPrintReceipt,
                          icon: const Icon(Icons.print_rounded),
                          label: const Text('Print on PT-210 (58mm)'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0284C7),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _copyReceiptText,
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('Copy Text'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 6. Thermal Paper Receipt Slip
                  Center(
                    child: _buildReceiptContainer(receiptText),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildHardwareBadge(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0284C7).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF0284C7).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.print_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text(
                      'GOOJPRT PT-210 Portable Printer',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _buildPill('Paper: 58mm'),
                    _buildPill('Width: 48mm'),
                    _buildPill('Cols: 32 Font A'),
                    _buildPill('ESC/POS'),
                    _buildPill('Bluetooth BLE/SPP'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Color(0xFF334155),
        ),
      ),
    );
  }

  Widget _buildDocumentTypeSelector(ThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: DocumentReceiptKind.values.map((kind) {
          final isSelected = kind == _selectedKind;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    kind.icon,
                    size: 16,
                    color: isSelected ? Colors.white : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(kind.label),
                ],
              ),
              selected: isSelected,
              selectedColor: const Color(0xFF0284C7),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedKind = kind;
                    // Reset live doc if switching kind manually
                    if (_loadedDocNo != null) {
                      _loadedDocNo = null;
                      _liveDocCustomer = null;
                      _liveDocRows = null;
                      _liveDocSubtotal = null;
                      _liveDocNet = null;
                    }
                  });
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildControlsCard(ThemeData theme) {
    return Card(
      elevation: 0,
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Layout Options & Toggles',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() => _showRawMonospace = !_showRawMonospace);
                  },
                  icon: Icon(
                    _showRawMonospace
                        ? Icons.receipt_long_rounded
                        : Icons.code_rounded,
                    size: 16,
                  ),
                  label: Text(
                    _showRawMonospace ? 'Slip View' : 'Raw View',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilterChip(
                  label: const Text('Discounts'),
                  selected: _includeDiscounts,
                  onSelected: (val) => setState(() => _includeDiscounts = val),
                  visualDensity: VisualDensity.compact,
                ),
                FilterChip(
                  label: const Text('Free Qty'),
                  selected: _includeFreeQty,
                  onSelected: (val) => setState(() => _includeFreeQty = val),
                  visualDensity: VisualDensity.compact,
                ),
                FilterChip(
                  label: const Text('Tax'),
                  selected: _includeTax,
                  onSelected: (val) => setState(() => _includeTax = val),
                  visualDensity: VisualDensity.compact,
                ),
                FilterChip(
                  label: const Text('Multi-Payment (Cheque)'),
                  selected: _includeMultiPayment,
                  onSelected: (val) => setState(() => _includeMultiPayment = val),
                  visualDensity: VisualDensity.compact,
                ),
                FilterChip(
                  label: const Text('Remarks'),
                  selected: _includeRemarks,
                  onSelected: (val) => setState(() => _includeRemarks = val),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveDocBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: Colors.green.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Showing live data for: $_loadedDocNo',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.green.shade900,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(
            onPressed: _resetToSampleData,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
            child: const Text('Reset Sample'),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptContainer(String text) {
    if (_showRawMonospace) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black26),
        ),
        child: SelectableText(
          text,
          style: const TextStyle(
            fontFamily: 'monospace',
            color: Color(0xFF38BDF8),
            fontSize: 12.5,
            height: 1.35,
          ),
        ),
      );
    }

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: const Color(0xFFFCFAF5), // authentic thermal paper off-white
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 16,
            spreadRadius: 2,
            offset: Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFE2DED4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Perforated Top Edge
          _buildPerforatedEdge(),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Logo Icon & Company name
                Center(
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: Colors.black87,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // 32-Column Monospaced Receipt Content - Justified Edge-to-Edge
                FittedBox(
                  fit: BoxFit.fitWidth,
                  child: Text(
                    text,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      height: 1.36,
                      color: Color(0xFF18181B),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // Simulated Barcode - matched to receipt width
                Center(
                  child: Column(
                    children: [
                      Container(
                        height: 34,
                        width: 240,
                        decoration: BoxDecoration(
                          border: Border.symmetric(
                            horizontal: BorderSide(
                              color: Colors.black.withValues(alpha: 0.6),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(42, (i) {
                            final w = (i % 3 == 0) ? 3.0 : (i % 2 == 0 ? 1.5 : 1.0);
                            return Container(
                              width: w,
                              color: (i % 5 == 0) ? Colors.transparent : Colors.black87,
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getDocumentNo(),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Perforated Bottom Edge
          _buildPerforatedEdge(isBottom: true),
        ],
      ),
    );
  }

  Widget _buildPerforatedEdge({bool isBottom = false}) {
    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: const Color(0xFFE5E0D5),
        borderRadius: BorderRadius.vertical(
          top: isBottom ? Radius.zero : const Radius.circular(8),
          bottom: isBottom ? const Radius.circular(8) : Radius.zero,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(
          24,
          (i) => Container(
            width: 6,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

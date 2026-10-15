import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../services/offline_sync_service.dart';
import '../providers/auth_provider.dart';

class QueueReportPage extends StatefulWidget {
  const QueueReportPage({super.key});

  @override
  State<QueueReportPage> createState() => _QueueReportPageState();
}

class _QueueReportPageState extends State<QueueReportPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _queuedItems = [];

  @override
  void initState() {
    super.initState();
    _loadQueuedItems();
  }

  Future<void> _loadQueuedItems() async {
    setState(() => _isLoading = true);
    
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final code = auth.salesmanCode;

      final salesOrders = await OfflineSyncService.getPendingDocumentsForRep(
        documentType: 'sales-order',
        salesmanCode: code,
      );
      final invoices = await OfflineSyncService.getPendingDocumentsForRep(
        documentType: 'invoice',
        salesmanCode: code,
      );
      final crns = await OfflineSyncService.getPendingDocumentsForRep(
        documentType: 'crn',
        salesmanCode: code,
      );

      final combined = <Map<String, dynamic>>[];
      for (var item in salesOrders) {
        combined.add({...item, 'type': 'Sales Order'});
      }
      for (var item in invoices) {
        combined.add({...item, 'type': 'Invoice'});
      }
      for (var item in crns) {
        combined.add({...item, 'type': 'CRN'});
      }

      // Sort by date descending
      combined.sort((a, b) {
        final aDate = a['documentDate']?.toString() ?? '';
        final bDate = b['documentDate']?.toString() ?? '';
        return bDate.compareTo(aDate);
      });

      setState(() {
        _queuedItems = combined;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading queue: $e')),
        );
      }
    }
  }

  Widget _buildStatusChip(String? error) {
    if (error != null && error.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.error_outline, size: 14, color: Colors.red),
            SizedBox(width: 4),
            Text('Failed', style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.pending_actions, size: 14, color: Colors.orange),
          SizedBox(width: 4),
          Text('Queued', style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Queue Report'),
        actions: [
          // Removed PDF dropdown as per user request
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadQueuedItems,
            tooltip: 'Refresh Queue',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _queuedItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline, size: 64, color: Colors.green.withValues(alpha: 0.6)),
                      const SizedBox(height: 16),
                      Text(
                        'No queued items!',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Everything is synced successfully.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadQueuedItems,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _queuedItems.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = _queuedItems[index];
                      final type = item['type'] as String;
                      final docNo = item['documentNo']?.toString() ?? 'Pending';
                      final customerName = item['customerName']?.toString() ?? 'Unknown Customer';
                      final amount = double.tryParse(item['netAmount']?.toString() ?? '0') ?? 0;
                      
                      IconData typeIcon;
                      Color typeColor;
                      if (type == 'Sales Order') {
                        typeIcon = Icons.shopping_cart_checkout_rounded;
                        typeColor = const Color(0xFF598DC9);
                      } else if (type == 'Invoice') {
                        typeIcon = Icons.receipt_long_rounded;
                        typeColor = const Color(0xFF10B981);
                      } else {
                        typeIcon = Icons.assignment_return_rounded;
                        typeColor = const Color(0xFFEF4444);
                      }

                      return Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            final auth = Provider.of<AuthProvider>(context, listen: false);
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => QueuePdfPreviewPage(
                                  items: [item],
                                  salesmanName: auth.salesmanName,
                                  reportTitle: '$type Report',
                                ),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: typeColor.withValues(alpha: 0.15),
                                    child: Icon(typeIcon, size: 16, color: typeColor),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      type,
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: typeColor,
                                      ),
                                    ),
                                  ),
                                  _buildStatusChip(item['lastError']?.toString()),
                                ],
                              ),
                              if (item['lastError'] != null && item['lastError'].toString().isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.info_outline, size: 16, color: Colors.red),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          item['lastError'].toString(),
                                          style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const Divider(height: 24),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          docNo,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          customerName,
                                          style: TextStyle(color: Colors.grey[700]),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        NumberFormat.currency(symbol: '', decimalDigits: 2).format(amount),
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item['documentDate']?.toString() ?? '',
                                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  ),
                ),
    );
  }
}

class QueuePdfPreviewPage extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final String salesmanName;
  final String? reportTitle;

  const QueuePdfPreviewPage({
    super.key,
    required this.items,
    required this.salesmanName,
    this.reportTitle,
  });

  Future<Uint8List> _generatePdf(PdfPageFormat format) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        build: (context) {
          final types = ['Sales Order', 'Quotation', 'Invoice', 'CRN'];
          final groupedItems = <String, List<Map<String, dynamic>>>{};
          for (var t in types) {
            groupedItems[t] = items.where((i) => i['type'] == t).toList();
          }

          final content = <pw.Widget>[
            pw.Header(
              level: 0,
              child: pw.Text(reportTitle ?? 'Pending Sync Queue Report',
                  style: pw.TextStyle(
                      fontSize: 24, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 10),
            pw.Text('Salesman: $salesmanName',
                style: const pw.TextStyle(fontSize: 16)),
            pw.Text(
                'Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 14)),
            pw.SizedBox(height: 20),
          ];

          if (items.isEmpty) {
            content.add(pw.Text('No pending items in queue.',
                style: const pw.TextStyle(fontSize: 14)));
            return content;
          }

          for (var t in types) {
            final typeItems = groupedItems[t]!;
            if (typeItems.isEmpty) continue; // Skip empty categories

            content.add(
              pw.Header(
                level: 1,
                child: pw.Text(t,
                    style: pw.TextStyle(
                        fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
              ),
            );
            content.add(pw.SizedBox(height: 10));

            content.add(
              pw.TableHelper.fromTextArray(
                headers: ['Doc No', 'Customer', 'Amount', 'Status'],
                data: typeItems.map((item) {
                  final hasError = item['lastError'] != null &&
                      item['lastError'].toString().isNotEmpty;
                  return [
                    item['documentNo']?.toString() ?? '',
                    item['customerName']?.toString() ?? '',
                    item['netAmount']?.toString() ?? '0',
                    hasError ? 'Failed' : 'Queued',
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey300,
                ),
                cellHeight: 30,
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.center,
                },
              ),
            );
            content.add(pw.SizedBox(height: 20));
          }

          return content;
        },
      ),
    );
    return pdf.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF Preview')),
      body: PdfPreview(
        build: (format) => _generatePdf(format),
      ),
    );
  }
}


import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/offline_sync_service.dart';
import '../../services/rep_document_recall_service.dart';
import '../../widgets/history_date_filter.dart';

class RepDocumentHistoryPage extends StatefulWidget {
  const RepDocumentHistoryPage({
    super.key,
    required this.title,
    required this.documentType,
    required this.icon,
    this.accentColor = const Color(0xFF598DC9),
    this.emptyMessage = 'No records found yet.',
    this.appBarLeading,
  });

  final String title;
  final String documentType;
  final IconData icon;
  final Color accentColor;
  final String emptyMessage;
  final Widget? appBarLeading;

  @override
  State<RepDocumentHistoryPage> createState() => _RepDocumentHistoryPageState();
}

class _RepDocumentHistoryPageState extends State<RepDocumentHistoryPage> {
  final _searchController = TextEditingController();
  final _currency = NumberFormat('#,##0.00');

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _entries = [];
  DateTime? _fromDate;
  DateTime? _toDate;
  String? _busyDocumentNo;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEntries() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      if (auth.salesmanCode.isEmpty) {
        throw Exception('Salesman information not available');
      }

      final serverEntries = await ApiService.getRepDocumentHistory(
        salesmanCode: auth.salesmanCode,
        documentType: widget.documentType,
        fromDate: HistoryDateFilter.toApiDate(_fromDate),
        toDate: HistoryDateFilter.toApiDate(_toDate),
      );
      final pendingEntries = await _loadPendingEntries(auth.salesmanCode);
      final merged = [
        ...pendingEntries,
        ...serverEntries,
      ].where(_matchesDateFilter).toList();

      if (!mounted) return;
      setState(() {
        _entries = merged;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadPendingEntries(
    String salesmanCode,
  ) async {
    switch (widget.documentType) {
      case 'invoice':
        return OfflineSyncService.getPendingDocumentsForRep(
          documentType: 'invoice',
          salesmanCode: salesmanCode,
        );
      case 'sales-order':
        return OfflineSyncService.getPendingDocumentsForRep(
          documentType: 'sales-order',
          salesmanCode: salesmanCode,
        );
      case 'crn':
        return OfflineSyncService.getPendingDocumentsForRep(
          documentType: 'crn',
          salesmanCode: salesmanCode,
        );
      default:
        return [];
    }
  }

  bool _matchesDateFilter(Map<String, dynamic> entry) {
    if (_fromDate == null && _toDate == null) return true;

    final rawDate = entry['documentDate']?.toString();
    if (rawDate == null || rawDate.isEmpty || rawDate == '-') {
      return _fromDate == null && _toDate == null;
    }

    final parsed = DateTime.tryParse(rawDate);
    if (parsed == null) return false;

    final day = DateTime(parsed.year, parsed.month, parsed.day);
    if (_fromDate != null && day.isBefore(_fromDate!)) return false;
    if (_toDate != null && day.isAfter(_toDate!)) return false;
    return true;
  }

  List<Map<String, dynamic>> get _filteredEntries {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _entries;

    return _entries.where((entry) {
      final documentNo = entry['documentNo']?.toString().toLowerCase() ?? '';
      final customerName =
          entry['customerName']?.toString().toLowerCase() ?? '';
      final customerCode =
          entry['customerCode']?.toString().toLowerCase() ?? '';
      return documentNo.contains(query) ||
          customerName.contains(query) ||
          customerCode.contains(query);
    }).toList();
  }

  int get _totalCount => _filteredEntries.length;

  double get _totalAmount {
    return _filteredEntries.fold(0.0, (sum, entry) {
      final val = entry['netAmount'];
      final amount = val is num
          ? val.toDouble()
          : double.tryParse('$val') ?? 0.0;
      return sum + amount;
    });
  }

  String _formatAmount(dynamic value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse('$value') ?? 0;
    return _currency.format(amount);
  }

  Future<void> _previewPdf(Map<String, dynamic> entry) async {
    final documentNo = entry['documentNo']?.toString() ?? '';
    if (documentNo.isEmpty) return;

    setState(() => _busyDocumentNo = documentNo);
    try {
      await RepDocumentRecallService.previewPdfFromHistoryEntry(
        context: context,
        documentType: widget.documentType,
        entry: entry,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyDocumentNo = null);
    }
  }

  void _showDocumentActions(Map<String, dynamic> entry) {
    final isPending =
        entry['isPendingSync'] == true || entry['isOffline'] == true;
    final documentNo = entry['documentNo']?.toString() ?? '-';
    final customerName =
        entry['customerName']?.toString() ??
        entry['customerCode']?.toString() ??
        'Customer';
    final documentDate = entry['documentDate']?.toString() ?? '-';
    final amount = _formatAmount(entry['netAmount']);

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  documentNo,
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text('$customerName\nDate: $documentDate\nAmount: Rs. $amount'),
                const SizedBox(height: 16),
                if (isPending)
                  Text(
                    'This document is still pending sync. Sync it before recalling or sharing.',
                    style: Theme.of(sheetContext).textTheme.bodyMedium
                        ?.copyWith(color: Colors.orange.shade800),
                  )
                else ...[
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _previewPdf(entry);
                    },
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: const Text('View & Share PDF'),
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.accentColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Recalls this document from the database and opens a PDF preview. Use the share button in the preview to send it.',
                    style: Theme.of(
                      sheetContext,
                    ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredEntries;

    return Scaffold(
      appBar: AppBar(
        leading: widget.appBarLeading,
        automaticallyImplyLeading: widget.appBarLeading == null,
        title: Text(widget.title),
        backgroundColor: widget.accentColor.withValues(alpha: 0.08),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadEntries,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _ReportSummaryCard(
              accentColor: widget.accentColor,
              documentCount: _totalCount,
              grandTotal: _formatAmount(_totalAmount),
            ),
            const SizedBox(height: 12),
            HistoryDateFilter(
              fromDate: _fromDate,
              toDate: _toDate,
              accentColor: widget.accentColor,
              onFromDateChanged: (date) {
                setState(() => _fromDate = date);
                _loadEntries();
              },
              onToDateChanged: (date) {
                setState(() => _toDate = date);
                _loadEntries();
              },
              onClear: () {
                setState(() {
                  _fromDate = null;
                  _toDate = null;
                });
                _loadEntries();
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () {
                      final now = DateTime.now();
                      setState(() {
                        _fromDate = DateTime(now.year, now.month, now.day);
                        _toDate = DateTime(now.year, now.month, now.day);
                      });
                      _loadEntries();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.accentColor.withValues(
                        alpha: 0.1,
                      ),
                      foregroundColor: widget.accentColor,
                    ),
                    child: const Text('Daily'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () {
                      final now = DateTime.now();
                      setState(() {
                        _fromDate = DateTime(now.year, now.month, 1);
                        _toDate = DateTime(
                          now.year,
                          now.month + 1,
                          0,
                        ); // Last day of month
                      });
                      _loadEntries();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.accentColor.withValues(
                        alpha: 0.1,
                      ),
                      foregroundColor: widget.accentColor,
                    ),
                    child: const Text('Monthly'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search document or customer',
                prefixIcon: Icon(widget.icon, color: widget.accentColor),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? _ErrorState(message: _error!, onRetry: _loadEntries)
                  : filtered.isEmpty
                  ? _EmptyState(message: widget.emptyMessage)
                  : RefreshIndicator(
                      onRefresh: _loadEntries,
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final entry = filtered[index];
                          final isPending =
                              entry['isPendingSync'] == true ||
                              entry['isOffline'] == true;
                          final documentNo =
                              entry['documentNo']?.toString() ?? '-';
                          final customerName =
                              entry['customerName']?.toString() ??
                              entry['customerCode']?.toString() ??
                              'Customer';
                          final documentDate =
                              entry['documentDate']?.toString() ?? '-';
                          final isBusy = _busyDocumentNo == documentNo;

                          return ListTile(
                            onTap: () => _showDocumentActions(entry),
                            tileColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: theme.colorScheme.outline.withValues(
                                  alpha: 0.15,
                                ),
                              ),
                            ),
                            leading: CircleAvatar(
                              backgroundColor: widget.accentColor.withValues(
                                alpha: 0.12,
                              ),
                              child: Icon(
                                widget.icon,
                                color: widget.accentColor,
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    documentNo,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (entry['isApproved'] == 1 ||
                                    entry['isApproved'] == true)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Approved',
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                else if (entry['isReject'] == 1 ||
                                    entry['isReject'] == true)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Rejected',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                else if (entry['isPending'] == 1 ||
                                    entry['isPending'] == true)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Pending Approval',
                                      style: TextStyle(
                                        color: Colors.orange,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  '$customerName\nDate: $documentDate · Rs. ${_formatAmount(entry['netAmount'])}',
                                ),
                                if ((entry['isReject'] == 1 ||
                                        entry['isReject'] == true) &&
                                    entry['rejReason'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Reason: ${entry['rejReason']}',
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            isThreeLine: true,
                            trailing: _HistoryTrailingActions(
                              accentColor: widget.accentColor,
                              isPending: isPending,
                              isBusy: isBusy,
                              onPreviewPdf: () => _previewPdf(entry),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTrailingActions extends StatelessWidget {
  const _HistoryTrailingActions({
    required this.accentColor,
    required this.isPending,
    required this.isBusy,
    required this.onPreviewPdf,
  });

  final Color accentColor;
  final bool isPending;
  final bool isBusy;
  final VoidCallback onPreviewPdf;

  @override
  Widget build(BuildContext context) {
    if (isPending) {
      return Icon(
        Icons.cloud_upload_outlined,
        color: Colors.orange.shade700,
        size: 22,
      );
    }

    if (isBusy) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return IconButton(
      tooltip: 'View & Share PDF',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      icon: Icon(Icons.picture_as_pdf_rounded, color: accentColor, size: 22),
      onPressed: onPreviewPdf,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(color: Colors.black54),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _ReportSummaryCard extends StatelessWidget {
  const _ReportSummaryCard({
    required this.accentColor,
    required this.documentCount,
    required this.grandTotal,
  });

  final Color accentColor;
  final int documentCount;
  final String grandTotal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accentColor.withValues(alpha: 0.12),
            accentColor.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryItem(
              label: 'Documents',
              value: '$documentCount',
              theme: theme,
            ),
          ),
          Expanded(
            child: _SummaryItem(
              label: 'Total amount',
              value: 'Rs. $grandTotal',
              theme: theme,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.value,
    required this.theme,
  });

  final String label;
  final String value;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

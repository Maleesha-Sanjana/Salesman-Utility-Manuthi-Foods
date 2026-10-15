import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/offline_sync_service.dart';

class MySalesAndHistoryPage extends StatefulWidget {
  const MySalesAndHistoryPage({
    super.key,
    this.appBarLeading,
    this.superAdminMode = false,
  });

  final Widget? appBarLeading;
  final bool superAdminMode;

  @override
  State<MySalesAndHistoryPage> createState() => _MySalesAndHistoryPageState();
}

class _MySalesAndHistoryPageState extends State<MySalesAndHistoryPage> {
  final NumberFormat _currency = NumberFormat('#,##0.00');

  bool _isLoadingSummary = true;
  double _todayInvoiceAmount = 0.0;
  int _todayInvoiceCount = 0;
  double _todayReturnAmount = 0.0;
  int _todayReturnCount = 0;
  double _todayNetAmount = 0.0;

  @override
  void initState() {
    super.initState();
    _loadTodaySummary();
  }

  Future<void> _loadTodaySummary() async {
    if (!mounted) return;
    setState(() => _isLoadingSummary = true);

    try {
      final auth = context.read<AuthProvider>();
      final salesmanCode = auth.salesmanCode;

      double invAmount = 0.0;
      int invCount = 0;
      double rtnAmount = 0.0;
      int rtnCount = 0;
      double netAmount = 0.0;

      if (salesmanCode.isNotEmpty) {
        // 1. Fetch server today summary
        try {
          final summary = await ApiService.getRepTodaySalesSummary(
            salesmanCode: salesmanCode,
          );
          if (summary['success'] == true) {
            invAmount = (summary['invoiceAmount'] as num?)?.toDouble() ?? 0.0;
            invCount = (summary['invoiceCount'] as num?)?.toInt() ?? 0;
            rtnAmount = (summary['returnAmount'] as num?)?.toDouble() ?? 0.0;
            rtnCount = (summary['returnCount'] as num?)?.toInt() ?? 0;
            netAmount = (summary['netAmount'] as num?)?.toDouble() ?? (invAmount - rtnAmount);
          }
        } catch (e) {
          debugPrint('Server today-summary unavailable, falling back: $e');
        }

        // 2. Incorporate pending offline items for today if any
        try {
          final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
          final pendingInvoices = await OfflineSyncService.getPendingDocumentsForRep(
            documentType: 'invoice',
            salesmanCode: salesmanCode,
          );
          final pendingCrns = await OfflineSyncService.getPendingDocumentsForRep(
            documentType: 'crn',
            salesmanCode: salesmanCode,
          );

          for (final doc in pendingInvoices) {
            final docDate = doc['documentDate']?.toString() ?? '';
            if (docDate.startsWith(todayStr)) {
              final amt = (doc['netAmount'] as num?)?.toDouble() ?? 0.0;
              invAmount += amt;
              invCount += 1;
            }
          }

          for (final doc in pendingCrns) {
            final docDate = doc['documentDate']?.toString() ?? '';
            if (docDate.startsWith(todayStr)) {
              final amt = (doc['netAmount'] as num?)?.toDouble() ?? 0.0;
              rtnAmount += amt;
              rtnCount += 1;
            }
          }

          netAmount = invAmount - rtnAmount;
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _todayInvoiceAmount = invAmount;
        _todayInvoiceCount = invCount;
        _todayReturnAmount = rtnAmount;
        _todayReturnCount = rtnCount;
        _todayNetAmount = netAmount;
        _isLoadingSummary = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingSummary = false);
    }
  }

  Widget _buildMetricTile({
    required ThemeData theme,
    required String title,
    required String amount,
    required String subtitle,
    required Color color,
    required IconData icon,
    bool isHighlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isHighlight ? 0.09 : 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: isHighlight ? 0.35 : 0.18),
          width: isHighlight ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              amount,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: color,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: isHighlight
                  ? color
                  : theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodaySummaryCard(ThemeData theme) {
    final todayStr = DateFormat('EEE, d MMM').format(DateTime.now());

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_graph_rounded,
                    size: 18,
                    color: Color(0xFF2362EC),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "Today's Sales Breakdown",
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2362EC).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      todayStr,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2362EC),
                      ),
                    ),
                  ),
                  if (_isLoadingSummary) ...[
                    const SizedBox(width: 6),
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Single row with 3 key metrics: Today's Invoices, Deduction (CRN), Now Your Sale
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  theme: theme,
                  title: "Today's Invoices",
                  amount: 'Rs. ${_currency.format(_todayInvoiceAmount)}',
                  subtitle: '$_todayInvoiceCount ${_todayInvoiceCount == 1 ? 'invoice' : 'invoices'}',
                  color: const Color(0xFF10B981),
                  icon: Icons.receipt_long_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  theme: theme,
                  title: 'Deduction (CRN)',
                  amount: _todayReturnAmount > 0
                      ? '-Rs. ${_currency.format(_todayReturnAmount)}'
                      : 'Rs. 0.00',
                  subtitle: '$_todayReturnCount ${_todayReturnCount == 1 ? 'return' : 'returns'}',
                  color: const Color(0xFFEF4444),
                  icon: Icons.assignment_return_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  theme: theme,
                  title: 'Now Your Sale',
                  amount: 'Rs. ${_currency.format(_todayNetAmount)}',
                  subtitle: '(After deduction)',
                  color: const Color(0xFF2362EC),
                  icon: Icons.account_balance_wallet_rounded,
                  isHighlight: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget buildCard({
      required IconData icon,
      required String title,
      String? subtitle,
      required VoidCallback onTap,
      Color color = const Color(0xFF598DC9),
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: 0.2,
                    color: theme.colorScheme.onSurface,
                    height: 1.2,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.black54,
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final cards = [
      (
        icon: Icons.receipt_long_rounded,
        title: 'Invoice history',
        subtitle: 'View invoice history',
        route: widget.superAdminMode
            ? '/super-admin/ref/history/invoice'
            : '/my-history/invoices',
        color: const Color(0xFF10B981),
      ),
      (
        icon: Icons.shopping_cart_checkout_rounded,
        title: 'Sales order history',
        subtitle: 'View sales order history',
        route: widget.superAdminMode
            ? '/super-admin/ref/history/sales-order'
        : '/my-history/sales-orders',
        color: const Color(0xFF598DC9),
      ),
      (
        icon: Icons.request_quote_rounded,
        title: 'Quotation history',
        subtitle: 'View quotation history',
        route: widget.superAdminMode
            ? '/super-admin/ref/history/quotation'
            : '/my-history/quotations',
        color: const Color(0xFF8B5CF6),
      ),
      (
        icon: Icons.assignment_return_rounded,
        title: 'CRN history',
        subtitle: 'View CRN history',
        route: widget.superAdminMode
            ? '/super-admin/ref/history/crn'
            : '/my-history/crn',
        color: const Color(0xFFEF4444),
      ),
      (
        icon: Icons.location_on_rounded,
        title: 'Location history',
        subtitle: 'View location history',
        route: widget.superAdminMode
            ? '/super-admin/ref/history/location'
            : '/my-history/locations',
        color: const Color(0xFF0D9488),
      ),
      if (!widget.superAdminMode)
        (
          icon: Icons.sync_problem_rounded,
          title: 'Queue report',
          subtitle: 'View pending offline items',
          route: '/queue-report',
          color: Colors.orange,
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        leading:
            widget.appBarLeading ??
            IconButton(
              icon: const Icon(Icons.arrow_back),
              color: Theme.of(context).colorScheme.onSurface,
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).pop(),
            ),
        title: const Text('My Sales & History'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadTodaySummary,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Summary card with Today's Invoices, Deduction (CRN), and Now Your Sale in a single row
              _buildTodaySummaryCard(theme),
              const SizedBox(height: 14),
              // Category history cards
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final crossAxisCount = width >= 1100
                        ? 3
                        : width >= 800
                        ? 3
                        : 2;
                    final spacing = 16.0;
                    final cellWidth =
                        (width - spacing * (crossAxisCount - 1)) / crossAxisCount;
                    // Taller cells on narrow screens so title + subtitle never overflow.
                    final targetCellHeight = crossAxisCount == 2 ? 156.0 : 140.0;
                    final aspect = cellWidth / targetCellHeight;

                    return GridView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 20),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: aspect,
                      ),
                      itemCount: cards.length,
                      itemBuilder: (context, index) {
                        final card = cards[index];
                        return buildCard(
                          icon: card.icon,
                          title: card.title,
                          subtitle: card.subtitle,
                          onTap: () => Navigator.of(context).pushNamed(card.route),
                          color: card.color,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

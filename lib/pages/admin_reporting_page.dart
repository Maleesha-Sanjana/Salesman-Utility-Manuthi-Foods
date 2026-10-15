import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class AdminReportingPage extends StatefulWidget {
  final Widget? appBarLeading;
  final VoidCallback? onStatusChanged;
  const AdminReportingPage({super.key, this.appBarLeading, this.onStatusChanged});

  @override
  State<AdminReportingPage> createState() => _AdminReportingPageState();
}

class _AdminReportingPageState extends State<AdminReportingPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _approved = [];
  List<Map<String, dynamic>> _rejected = [];
  bool _isLoading = true;

  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) _loadData(showLoading: false);
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _isLoading = true);
    }
    final pending = await ApiService.getSalesOrdersForReporting(status: 'pending');
    final approved = await ApiService.getSalesOrdersForReporting(status: 'approved');
    final rejected = await ApiService.getSalesOrdersForReporting(status: 'rejected');
    
    if (mounted) {
      setState(() {
        _pending = pending;
        _approved = approved;
        _rejected = rejected;
        _isLoading = false;
      });
    }
  }

  Future<void> _approveOrder(String documentNo) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Are you sure?'),
        content: const Text('Are you sure want to Approve?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), 
            child: const Text('Cancel')
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('Approve')
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await ApiService.approveSalesOrder(documentNo);
    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order Approved')));
        widget.onStatusChanged?.call();
        _loadData();
      }
    }
  }

  Future<void> _rejectOrder(String documentNo) async {
    final reasonController = TextEditingController();
    final bool? submit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Order'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(labelText: 'Reason for rejection'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reject')),
        ],
      ),
    );

    if (submit == true && reasonController.text.isNotEmpty) {
      final success = await ApiService.rejectSalesOrder(documentNo, reasonController.text);
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order Rejected')));
          widget.onStatusChanged?.call();
          _loadData();
        }
      }
    }
  }

  Widget _buildList(List<Map<String, dynamic>> items, String type) {
    if (items.isEmpty) return const Center(child: Text('No orders found'));
    
    return ListView.builder(
      itemCount: items.length,
      padding: const EdgeInsets.all(8),
      itemBuilder: (context, index) {
        final item = items[index];
        final docNo = item['DocumentNo']?.toString() ?? '';
        final date = item['Created_Date'] != null ? DateTime.tryParse(item['Created_Date']) : null;
        final dateStr = date != null ? DateFormat('yyyy-MM-dd HH:mm').format(date) : '';
        final amount = item['NetAmount']?.toString() ?? '0.00';
        
        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SO: $docNo', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text('Amount: Rs. $amount', style: const TextStyle(fontSize: 15, color: Colors.green, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Salesman: ${item['SalesmanCode']} | Customer: ${item['CustomerCode']}'),
                Text('Date: $dateStr'),
                if (type == 'rejected' && item['rejReason'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Reason: ${item['rejReason']}', style: const TextStyle(color: Colors.red)),
                  ),
                if (type == 'pending') ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.cancel, size: 20),
                          label: const Text('Cancel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          onPressed: () => _rejectOrder(docNo),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.check_circle, size: 20),
                          label: const Text('Approve', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          onPressed: () => _approveOrder(docNo),
                        ),
                      ),
                    ],
                  ),
                ]
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.appBarLeading,
        title: const Text('Sales Orders Approval'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Approved'),
            Tab(text: 'Rejected'),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : TabBarView(
            controller: _tabController,
            children: [
              _buildList(_pending, 'pending'),
              _buildList(_approved, 'approved'),
              _buildList(_rejected, 'rejected'),
            ],
          ),
    );
  }
}

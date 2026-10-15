import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class SalesmanReportingPage extends StatefulWidget {
  final Widget? appBarLeading;
  const SalesmanReportingPage({super.key, this.appBarLeading});

  @override
  State<SalesmanReportingPage> createState() => _SalesmanReportingPageState();
}

class _SalesmanReportingPageState extends State<SalesmanReportingPage> with SingleTickerProviderStateMixin {
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
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
    if (!mounted) return;
    if (showLoading) {
      setState(() => _isLoading = true);
    }
    final salesmanCode = context.read<AuthProvider>().salesmanCode;
    
    final pending = await ApiService.getSalesOrdersForReporting(salesmanCode: salesmanCode, status: 'pending');
    final approved = await ApiService.getSalesOrdersForReporting(salesmanCode: salesmanCode, status: 'approved');
    final rejected = await ApiService.getSalesOrdersForReporting(salesmanCode: salesmanCode, status: 'rejected');
    
    if (mounted) {
      setState(() {
        _pending = pending;
        _approved = approved;
        _rejected = rejected;
        _isLoading = false;
      });
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
          child: ListTile(
            title: Text('SO: $docNo (Rs. $amount)'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Customer: ${item['CustomerCode']}'),
                Text('Date: $dateStr'),
                if (type == 'rejected' && item['rejReason'] != null)
                  Text('Reason: ${item['rejReason']}', style: const TextStyle(color: Colors.red)),
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
        title: const Text('My Orders Status'),
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

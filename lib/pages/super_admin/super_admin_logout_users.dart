import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../models/salesman.dart';

class SuperAdminLogoutUsersPage extends StatefulWidget {
  final Widget? appBarLeading;

  const SuperAdminLogoutUsersPage({super.key, this.appBarLeading});

  @override
  State<SuperAdminLogoutUsersPage> createState() => _SuperAdminLogoutUsersPageState();
}

class _SuperAdminLogoutUsersPageState extends State<SuperAdminLogoutUsersPage> {
  bool _isLoadingAll = false;
  bool _isLoadingList = false;
  List<Salesman> _activeUsers = [];

  @override
  void initState() {
    super.initState();
    _fetchActiveUsers();
  }

  Future<void> _fetchActiveUsers() async {
    if (!mounted) return;
    setState(() => _isLoadingList = true);
    
    try {
      final allSalesmen = await ApiService.getSalesmen();
      if (!mounted) return;
      setState(() {
        _activeUsers = allSalesmen.where((s) => s.isLogged == true).toList();
      });
    } catch (e) {
      debugPrint('Error fetching active users: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingList = false);
      }
    }
  }

  Future<void> _logoutAllUsers() async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout All Users'),
        content: const Text(
          'Are you sure you want to force logout all salesmen currently logged into the system? They will be required to log in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            child: const Text('Force Logout All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      setState(() => _isLoadingAll = true);
      
      await ApiService.logoutAllUsers();
      await _fetchActiveUsers();
      
      if (!mounted) return;
      setState(() => _isLoadingAll = false);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Successfully logged out all users.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _logoutSingleUser(Salesman user) async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout User'),
        content: Text(
          'Force logout ${user.salesmanName} (${user.salesmanCode})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      
      // We will show loading on the list to block interactions during the call
      setState(() => _isLoadingList = true);
      
      await ApiService.logout(user.salesmanCode);
      await _fetchActiveUsers();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully logged out ${user.salesmanCode}.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: widget.appBarLeading,
        title: const Text('Manage Active Sessions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh list',
            onPressed: _isLoadingList ? null : _fetchActiveUsers,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top section: Master logout
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Mass Session Revocation',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Instantly invalidate the session for all logged-in users. They will be kicked out to the login screen.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: _isLoadingAll ? null : _logoutAllUsers,
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.error,
                            foregroundColor: theme.colorScheme.onError,
                          ),
                          icon: _isLoadingAll
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.group_remove_rounded),
                          label: const Text(
                            'Force Logout All Users',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            const Divider(height: 1),
            
            // Header for active users
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text(
                    'Active Logged-In Users',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (_isLoadingList)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_activeUsers.length}',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            
            // List of active users
            Expanded(
              child: _isLoadingList && _activeUsers.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _activeUsers.isEmpty
                      ? Center(
                          child: Text(
                            'No active users found.',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _fetchActiveUsers,
                          child: ListView.separated(
                            itemCount: _activeUsers.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final user = _activeUsers[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                                  child: Text(
                                    user.salesmanCode.substring(0, 1).toUpperCase(),
                                    style: TextStyle(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  user.salesmanName ?? 'Unknown',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text('Code: ${user.salesmanCode}'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.logout_rounded),
                                  color: theme.colorScheme.error,
                                  tooltip: 'Logout User',
                                  onPressed: _isLoadingList 
                                      ? null 
                                      : () => _logoutSingleUser(user),
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

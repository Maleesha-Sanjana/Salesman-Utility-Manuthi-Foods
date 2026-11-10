import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class CustomerSelectionDialog extends StatefulWidget {
  const CustomerSelectionDialog({
    super.key,
    required this.customers,
    this.isLoading = false,
    this.requireLocation = false,
  });

  final List<Map<String, String>> customers;
  final bool isLoading;
  final bool requireLocation;

  @override
  State<CustomerSelectionDialog> createState() =>
      _CustomerSelectionDialogState();
}

class _CustomerSelectionDialogState extends State<CustomerSelectionDialog> {
  late final TextEditingController _searchController;
  late List<Map<String, String>> _filteredCustomers;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _filteredCustomers = List.from(widget.customers);
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void didUpdateWidget(covariant CustomerSelectionDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.customers, widget.customers) ||
        oldWidget.isLoading != widget.isLoading) {
      setState(() {
        _filteredCustomers = List.from(widget.customers);
      });
      _applyFilter(_searchController.text);
    }
  }

  void _handleSearchChanged() {
    _applyFilter(_searchController.text);
  }

  void _applyFilter(String query) {
    final lowerQuery = query.trim().toLowerCase();
    setState(() {
      if (lowerQuery.isEmpty) {
        _filteredCustomers = List.from(widget.customers);
        return;
      }

      _filteredCustomers = widget.customers.where((customer) {
        final code = customer['code']?.toLowerCase() ?? '';
        final name = customer['name']?.toLowerCase() ?? '';
        final phone = customer['phone']?.toLowerCase() ?? '';
        final contactPerson = customer['contactPerson']?.toLowerCase() ?? '';
        return code.contains(lowerQuery) ||
            name.contains(lowerQuery) ||
            phone.contains(lowerQuery) ||
            contactPerson.contains(lowerQuery);
      }).toList();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final keyboardOpen = media.viewInsets.bottom > 0;
    final availableHeight = media.size.height - media.viewInsets.bottom - 160;
    double dialogHeight;

    if (availableHeight.isFinite && availableHeight > 0) {
      dialogHeight = availableHeight;
      if (dialogHeight > 480.0) dialogHeight = 480.0;
      final minHeight = keyboardOpen ? 220.0 : 260.0;
      if (dialogHeight < minHeight) dialogHeight = minHeight;
    } else {
      dialogHeight = media.size.height * 0.6;
    }

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('Select Customer'),
      content: SizedBox(
        width: double.maxFinite,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search by name, code, phone, contact person',
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: widget.isLoading
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Loading customers...'),
                        ],
                      ),
                    )
                  : _filteredCustomers.isEmpty
                      ? const Center(child: Text('No customers found'))
                      : ListView.separated(
                          itemCount: _filteredCustomers.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final customer = _filteredCustomers[index];
                            final code = customer['code'] ?? '';
                            final name = customer['name'] ?? '';
                            final phone = customer['phone'] ?? '';
                            final contactPerson =
                                customer['contactPerson'] ?? '';
                            final location =
                                (customer['location'] ?? '').trim();
                            final hasLocation = location.isNotEmpty;
                            final subtitleParts = <String>[
                              if (phone.isNotEmpty) phone,
                              if (contactPerson.isNotEmpty) contactPerson,
                            ];
                            return ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: theme.colorScheme.outline.withValues(alpha: 0.2),
                                ),
                              ),
                              leading: CircleAvatar(
                                backgroundColor:
                                    theme.colorScheme.secondaryContainer,
                                foregroundColor:
                                    theme.colorScheme.onSecondaryContainer,
                                child: const Icon(Icons.person_rounded),
                              ),
                              title: Text('$code • $name'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (subtitleParts.isNotEmpty)
                                    Text(subtitleParts.join(' • ')),
                                  if (widget.requireLocation && !hasLocation)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.warning_amber_rounded,
                                            size: 14,
                                            color: Colors.red.shade700,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'No Location (Cannot Invoice)',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.red.shade700,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              onTap: () {
                                if (widget.requireLocation && !hasLocation) {
                                  showDialog<void>(
                                    context: context,
                                    builder: (dialogCtx) => AlertDialog(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      title: Row(
                                        children: [
                                          Icon(
                                            Icons.error_outline_rounded,
                                            color: Colors.red.shade700,
                                            size: 28,
                                          ),
                                          const SizedBox(width: 10),
                                          const Expanded(
                                            child: Text(
                                              'Invoicing Not Allowed',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      content: Text(
                                        'Customer "$name" ($code) has no location assigned in the system.\n\nSales reps cannot invoice customers without an assigned location.\n\nPlease contact Head Office to assign a location to this customer.',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          height: 1.4,
                                        ),
                                      ),
                                      actions: [
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.of(dialogCtx).pop(),
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                Colors.red.shade700,
                                          ),
                                          child: const Text('OK'),
                                        ),
                                      ],
                                    ),
                                  );
                                  return;
                                }
                                FocusScope.of(context).unfocus();
                                Navigator.of(context).pop(customer);
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(<String, String>{}),
          child: const Text('None'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}


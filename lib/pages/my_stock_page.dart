import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class MyStockPage extends StatefulWidget {
  const MyStockPage({super.key});

  @override
  State<MyStockPage> createState() => _MyStockPageState();
}

class _MyStockPageState extends State<MyStockPage> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _resolvedLocation = '01';
  String? _resolvedLocationDescription;

  // View By selection and dependent lists
  String _viewBy = 'Product Wise';
  String? _chosenFilter; // Selected department/sub-dept/category/etc.
  bool _displayAll = false; // Display all toggle
  int? _sortColumnIndex;
  bool _sortAscending = true;

  List<String> _departments = [];
  List<String> _subDepartments = [];
  List<String> _categories = [];
  List<String> _subCategories = [];
  List<String> _suppliers = [];

  @override
  void initState() {
    super.initState();
    _loadStockData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStockData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final sm = auth.currentSalesman;
      final rawLoc = (sm?.locationCode?.trim().isNotEmpty == true)
          ? sm!.locationCode!.trim()
          : (sm?.location?.trim().isNotEmpty == true ? sm!.location!.trim() : '01');

      final res = await ApiService.fetchMyStock(
        location: rawLoc,
        salesmanCode: sm?.salesmanCode,
      );

      if (!mounted) return;

      if (res['success'] == true && res['data'] is List) {
        final rawList = res['data'] as List;
        final List<Map<String, dynamic>> loaded = [];
        final Set<String> depts = {};
        final Set<String> subDepts = {};
        final Set<String> cats = {};
        final Set<String> subCats = {};
        final Set<String> supps = {};

        for (final row in rawList) {
          if (row is! Map) continue;
          final r = Map<String, dynamic>.from(row);
          final code = (r['ProductCode'] ?? '').toString().trim();
          final name = (r['ProductName'] ?? r['ProductCode'] ?? '').toString().trim();
          final dept = (r['Department'] ?? '').toString().trim();
          final subDept = (r['SubDepartment'] ?? '').toString().trim();
          final cat = (r['Category'] ?? '').toString().trim();
          final subCat = (r['SubCategory'] ?? '').toString().trim();
          final supp = (r['Supplier'] ?? '').toString().trim();

          if (dept.isNotEmpty && dept != 'General') depts.add(dept);
          if (subDept.isNotEmpty && subDept != 'General') subDepts.add(subDept);
          if (cat.isNotEmpty && cat != 'General') cats.add(cat);
          if (subCat.isNotEmpty && subCat != 'General') subCats.add(subCat);
          if (supp.isNotEmpty && supp != 'N/A') supps.add(supp);

          loaded.add({
            'idx': r['idx'],
            'code': code,
            'name': name.isNotEmpty ? name : code,
            'qty': (r['StockQty'] as num?)?.toInt() ?? 0,
            'price': (r['Price'] as num?)?.toDouble() ?? 0.0,
            'costPrice': (r['CostPrice'] as num?)?.toDouble() ?? 0.0,
            'wholeSalePrice': (r['WholeSalePrice'] as num?)?.toDouble() ?? 0.0,
            'department': dept.isNotEmpty ? dept : 'General',
            'subDepartment': subDept.isNotEmpty ? subDept : 'General',
            'category': cat.isNotEmpty ? cat : 'General',
            'subCategory': subCat.isNotEmpty ? subCat : 'General',
            'supplier': supp.isNotEmpty ? supp : 'N/A',
            'reOrderQty': (r['ReOrderQty'] as num?)?.toInt() ?? 0,
            'reOrderLevel': (r['ReOrderLevel'] as num?)?.toInt() ?? 0,
          });
        }

        setState(() {
          _items = loaded;
          _isLoading = false;
          _errorMessage = null;
          _resolvedLocation = (res['location'] ?? rawLoc).toString().trim();
          _resolvedLocationDescription = (res['locationDescription'] ?? sm?.locationDescription)?.toString().trim();
          _departments = depts.toList()..sort();
          _subDepartments = subDepts.toList()..sort();
          _categories = cats.toList()..sort();
          _subCategories = subCats.toList()..sort();
          _suppliers = supps.toList()..sort();
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = res['error']?.toString() ?? 'Failed to load stock data';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Network error: $e';
      });
    }
  }

  String _formatLkrPlain(num value) {
    final negative = value < 0;
    final absVal = value.abs();
    final whole = absVal.floor();
    final frac = ((absVal - whole) * 100).round();
    String wholeStr = whole.toString();
    final buf = StringBuffer();
    for (int i = 0; i < wholeStr.length; i++) {
      final idxFromRight = wholeStr.length - i;
      buf.write(wholeStr[i]);
      if (idxFromRight > 1 && idxFromRight % 3 == 1) {
        buf.write(',');
      }
    }
    final formattedWhole = buf.toString();
    final formattedFrac = frac.toString().padLeft(2, '0');
    return '${negative ? '-' : ''}$formattedWhole.$formattedFrac';
  }

  Widget _buildAdaptiveSearch() {
    List<String> dataset;
    String label;
    switch (_viewBy) {
      case 'Department Wise':
        dataset = _departments;
        label = 'Search Departments';
        break;
      case 'Sub-Department Wise':
        dataset = _subDepartments;
        label = 'Search Sub Departments';
        break;
      case 'Category Wise':
        dataset = _categories;
        label = 'Search Categories';
        break;
      case 'Sub Category Wise':
        dataset = _subCategories;
        label = 'Search Sub Categories';
        break;
      case 'Supplier Wise':
        dataset = _suppliers;
        label = 'Search Suppliers';
        break;
      default:
        dataset = _items.map((e) => e['name'] as String).toList();
        label = 'Search Products or Code';
    }

    return Autocomplete<String>(
      optionsBuilder: (TextEditingValue tev) {
        final q = tev.text.trim().toLowerCase();
        if (q.isEmpty) return const Iterable<String>.empty();
        return dataset.where((e) => e.toLowerCase().contains(q));
      },
      onSelected: (val) {
        _searchController.text = val;
        setState(() {});
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        // Keep the shared controller in sync
        controller.text = _searchController.text;
        controller.selection = _searchController.selection;
        controller.addListener(() {
          if (controller.text != _searchController.text) {
            _searchController.value = controller.value;
            setState(() {});
          }
        });
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      _searchController.clear();
                      controller.clear();
                      setState(() {});
                    },
                  )
                : null,
          ),
          onSubmitted: (_) => onFieldSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, minWidth: 280),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final opt = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(opt),
                    onTap: () => onSelected(opt),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _showViewBy() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        Widget option(String label, IconData icon) => ListTile(
              leading: Icon(icon),
              title: Text(label),
              onTap: () {
                setState(() {
                  _viewBy = label;
                  _chosenFilter = null; // reset dependent selection
                });
                Navigator.pop(context);
              },
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'View By',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                option('Product Wise', Icons.inventory_2_rounded),
                option('Department Wise', Icons.apartment_rounded),
                option('Sub-Department Wise', Icons.account_tree_rounded),
                if (_categories.isNotEmpty)
                  option('Category Wise', Icons.category_rounded),
                if (_subCategories.isNotEmpty)
                  option('Sub Category Wise', Icons.dashboard_customize_rounded),
                if (_suppliers.isNotEmpty)
                  option('Supplier Wise', Icons.local_shipping_rounded),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSelectionPicker(String title, List<String> options) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              if (options.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No options available', style: TextStyle(color: Colors.grey)),
                )
              else
                ...options.map((e) => ListTile(
                      title: Text(e),
                      onTap: () {
                        setState(() => _chosenFilter = e);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Selected: $e')),
                        );
                      },
                    )),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showProductDetails(Map<String, dynamic> item) {
    final theme = Theme.of(context);
    final qty = (item['qty'] as num?)?.toInt() ?? 0;
    final price = (item['price'] as num?)?.toDouble() ?? 0.0;
    final costPrice = (item['costPrice'] as num?)?.toDouble() ?? 0.0;
    final wholeSale = (item['wholeSalePrice'] as num?)?.toDouble() ?? 0.0;
    final inStock = qty > 0;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: inStock
                          ? const Color(0xFF10B981).withValues(alpha: 0.15)
                          : const Color(0xFFEF4444).withValues(alpha: 0.15),
                      child: Icon(
                        inStock ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                        color: inStock ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['name'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Code: ${item['code']}',
                            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                _detailRow('Assigned Location', '$_resolvedLocation${_resolvedLocationDescription != null ? " ($_resolvedLocationDescription)" : ""}'),
                _detailRow('Current Stock Qty', '$qty units', isBold: true, valueColor: inStock ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
                _detailRow('Selling Price', 'Rs. ${_formatLkrPlain(price)}'),
                if (costPrice > 0)
                  _detailRow('Cost Price', 'Rs. ${_formatLkrPlain(costPrice)}'),
                if (wholeSale > 0)
                  _detailRow('Wholesale Price', 'Rs. ${_formatLkrPlain(wholeSale)}'),
                if (item['department'] != null && item['department'] != 'General')
                  _detailRow('Department', item['department']),
                if (item['subDepartment'] != null && item['subDepartment'] != 'General')
                  _detailRow('Sub-Department', item['subDepartment']),
                if (item['supplier'] != null && item['supplier'] != 'N/A')
                  _detailRow('Supplier', item['supplier']),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value, {bool isBold = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              fontSize: 14,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _searchController.text.trim().toLowerCase();
    final filtered = _items.where((e) {
      final name = (e['name'] as String).toLowerCase();
      final code = (e['code'] as String? ?? '').toLowerCase();
      final nameMatch = _viewBy == 'Product Wise'
          ? (q.isEmpty || name.contains(q) || code.contains(q))
          : true;
      final qty = e['qty'] as int;
      final stockMatch = _displayAll ? true : qty > 0;
      return nameMatch && stockMatch;
    }).toList();

    // Apply sorting
    int compareName(a, b) => (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase());
    int compareQty(a, b) => (a['qty'] as num).compareTo(b['qty'] as num);
    int comparePrice(a, b) => ((a['price'] as num?) ?? 0).compareTo(((b['price'] as num?) ?? 0));
    if (_sortColumnIndex != null) {
      switch (_sortColumnIndex) {
        case 0:
          filtered.sort(compareName);
          break;
        case 1:
          filtered.sort(compareQty);
          break;
        case 2:
          filtered.sort(comparePrice);
          break;
      }
      if (!_sortAscending) {
        filtered.setAll(0, filtered.reversed);
      }
    }

    final totalItemsInDb = _items.length;
    final totalInStock = _items.where((e) => (e['qty'] as int) > 0).length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('My Stock'),
            Text(
              'Location: $_resolvedLocation${_resolvedLocationDescription != null && _resolvedLocationDescription!.isNotEmpty ? " ($_resolvedLocationDescription)" : ""}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Stock',
            onPressed: _loadStockData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading real-time stock...'),
                ],
              ),
            )
          : _errorMessage != null && _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.red, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadStockData,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Location & Count Status Strip
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.place_rounded, size: 16, color: Color(0xFF10B981)),
                                const SizedBox(width: 4),
                                Text(
                                  'Loc: $_resolvedLocation',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
                            Text(
                              'In Stock: $totalInStock / Total: $totalItemsInDb',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _showViewBy,
                              icon: const Icon(Icons.tune),
                              label: Text(
                                _viewBy,
                                textAlign: TextAlign.justify,
                              ),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide(
                                  color: Theme.of(context).colorScheme.outlineVariant,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _viewBy == 'Product Wise'
                                  ? null
                                  : () {
                                      switch (_viewBy) {
                                        case 'Department Wise':
                                          _showSelectionPicker('Main Departments', _departments);
                                          break;
                                        case 'Sub-Department Wise':
                                          _showSelectionPicker('Sub Departments', _subDepartments);
                                          break;
                                        case 'Category Wise':
                                          _showSelectionPicker('Main Categories', _categories);
                                          break;
                                        case 'Sub Category Wise':
                                          _showSelectionPicker('Sub Categories', _subCategories);
                                          break;
                                        case 'Supplier Wise':
                                          _showSelectionPicker('Main Suppliers', _suppliers);
                                          break;
                                      }
                                    },
                              icon: const Icon(Icons.list_alt),
                              label: Text(() {
                                switch (_viewBy) {
                                  case 'Department Wise':
                                    return _chosenFilter == null ? 'Main Departments' : _chosenFilter!;
                                  case 'Sub-Department Wise':
                                    return _chosenFilter == null ? 'Sub Departments' : _chosenFilter!;
                                  case 'Category Wise':
                                    return _chosenFilter == null ? 'Main Categories' : _chosenFilter!;
                                  case 'Sub Category Wise':
                                    return _chosenFilter == null ? 'Sub Categories' : _chosenFilter!;
                                  case 'Supplier Wise':
                                    return _chosenFilter == null ? 'Main Suppliers' : _chosenFilter!;
                                  default:
                                    return 'Select';
                                }
                              }(), textAlign: TextAlign.justify),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: _displayAll,
                                visualDensity: VisualDensity.compact,
                                onChanged: (v) => setState(() => _displayAll = v ?? false),
                              ),
                              const SizedBox(width: 6),
                              const Text('Display All (Include 0 Stock)'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildAdaptiveSearch(),
                      const SizedBox(height: 12),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _loadStockData,
                          child: filtered.isEmpty
                              ? ListView(
                                  children: [
                                    const SizedBox(height: 60),
                                    Center(
                                      child: Column(
                                        children: [
                                          Icon(
                                            Icons.inventory_2_outlined,
                                            size: 64,
                                            color: theme.colorScheme.outline,
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            _items.isEmpty
                                                ? 'No products found for Location $_resolvedLocation'
                                                : 'No items match your filter.\nTry enabling "Display All".',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: theme.colorScheme.onSurfaceVariant,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : Card(
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: LayoutBuilder(
                                      builder: (context, box) {
                                        // Real-time width from the table container
                                        const double hMargin = 4;
                                        const double colSpacing = 12;
                                        const double stockW = 56;
                                        const double priceW = 84;
                                        final double available = box.maxWidth - (hMargin * 2) - (colSpacing * 2) - stockW - priceW;
                                        final double itemW = available.clamp(120.0, box.maxWidth);

                                        return Scrollbar(
                                          thumbVisibility: true,
                                          child: SingleChildScrollView(
                                            physics: const AlwaysScrollableScrollPhysics(),
                                            scrollDirection: Axis.vertical,
                                            child: DataTable(
                                              showCheckboxColumn: false,
                                              columnSpacing: colSpacing,
                                              headingRowHeight: 40,
                                              dataRowMinHeight: 38,
                                              dataRowMaxHeight: 46,
                                              columns: [
                                                DataColumn(
                                                  label: const Text('Item'),
                                                  onSort: (col, asc) => setState(() {
                                                    _sortColumnIndex = col;
                                                    _sortAscending = asc;
                                                  }),
                                                ),
                                                DataColumn(
                                                  numeric: true,
                                                  label: const Text('Stock'),
                                                  onSort: (col, asc) => setState(() {
                                                    _sortColumnIndex = col;
                                                    _sortAscending = asc;
                                                  }),
                                                ),
                                                DataColumn(
                                                  numeric: true,
                                                  label: const Text('Price (Rs.)'),
                                                  onSort: (col, asc) => setState(() {
                                                    _sortColumnIndex = col;
                                                    _sortAscending = asc;
                                                  }),
                                                ),
                                              ],
                                              rows: _buildGroupedRows(
                                                context: context,
                                                theme: theme,
                                                rows: filtered,
                                                itemW: itemW,
                                                stockW: stockW,
                                                priceW: priceW,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  List<DataRow> _buildGroupedRows({
    required BuildContext context,
    required ThemeData theme,
    required List<Map<String, dynamic>> rows,
    required double itemW,
    required double stockW,
    required double priceW,
  }) {
    // Helper to truncate with custom dots
    String trunc(String text, double width) {
      final maxChars = (width / 7).floor().clamp(6, 120);
      if (text.length > maxChars) {
        return '${text.substring(0, (maxChars - 5).clamp(0, text.length))}.....';
      }
      return text;
    }

    // Decide grouping mode
    final mode = _viewBy;
    final selected = _chosenFilter;

    // Utility to add a group header row
    DataRow headerRow(String title) => DataRow(
          color: WidgetStateProperty.resolveWith(
            (_) => theme.colorScheme.primary.withValues(alpha: 0.06),
          ),
          cells: [
            DataCell(SizedBox(
              width: itemW,
              child: Text(
                title,
                maxLines: 1,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            )),
            const DataCell(Text('')),
            const DataCell(Text('')),
          ],
        );

    // Product row builder
    DataRow productRow(Map<String, dynamic> it, int index) {
      final qty = (it['qty'] as num?)?.toInt() ?? 0;
      final price = (it['price'] as num?) ?? 0;
      final inStock = qty > 0;
      final name = (it['name'] as String?) ?? '';
      return DataRow(
        onSelectChanged: (_) => _showProductDetails(it),
        color: WidgetStateProperty.resolveWith(
          (_) => index.isEven ? theme.colorScheme.surface : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        ),
        cells: [
          DataCell(SizedBox(width: itemW, child: Text(trunc(name, itemW), maxLines: 1))),
          DataCell(SizedBox(
            width: stockW,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '$qty',
                style: TextStyle(
                  fontWeight: inStock ? FontWeight.w600 : FontWeight.normal,
                  color: inStock ? theme.colorScheme.onSurface : const Color(0xFFEF4444),
                ),
              ),
            ),
          )),
          DataCell(SizedBox(
            width: priceW,
            child: Align(alignment: Alignment.centerRight, child: Text(_formatLkrPlain(price))),
          )),
        ],
      );
    }

    final List<DataRow> out = [];

    // No grouping (Product Wise)
    if (mode == 'Product Wise') {
      for (var i = 0; i < rows.length; i++) {
        out.add(productRow(rows[i], i));
      }
      return out;
    }

    // Single-level grouping helper
    void groupByKey(String key) {
      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final it in rows) {
        final k = (it[key] as String?) ?? 'Unknown';
        if (selected != null && selected.isNotEmpty && selected != k) continue;
        grouped.putIfAbsent(k, () => []).add(it);
      }
      final sortedKeys = grouped.keys.toList()..sort();
      for (final k in sortedKeys) {
        out.add(headerRow(k));
        final list = grouped[k]!;
        for (var i = 0; i < list.length; i++) {
          out.add(productRow(list[i], i));
        }
      }
    }

    // Two-level grouping helper (parentKey -> childKey)
    void groupByTwo(String parentKey, String childKey) {
      final parents = <String, List<Map<String, dynamic>>>{};
      for (final it in rows) {
        final pk = (it[parentKey] as String?) ?? 'Unknown';
        parents.putIfAbsent(pk, () => []).add(it);
      }
      final sortedParents = parents.keys.toList()..sort();
      for (final pk in sortedParents) {
        if (selected != null && selected.isNotEmpty && selected != pk) continue;
        out.add(headerRow(pk));
        final children = <String, List<Map<String, dynamic>>>{};
        for (final it in parents[pk]!) {
          final ck = (it[childKey] as String?) ?? 'Unknown';
          children.putIfAbsent(ck, () => []).add(it);
        }
        final sortedChildren = children.keys.toList()..sort();
        for (final ck in sortedChildren) {
          out.add(headerRow('  • $ck'));
          final list = children[ck]!;
          for (var i = 0; i < list.length; i++) {
            out.add(productRow(list[i], i));
          }
        }
      }
    }

    switch (mode) {
      case 'Department Wise':
        groupByKey('department');
        break;
      case 'Sub-Department Wise':
        groupByTwo('department', 'subDepartment');
        break;
      case 'Category Wise':
        groupByKey('category');
        break;
      case 'Sub Category Wise':
        groupByTwo('category', 'subCategory');
        break;
      case 'Supplier Wise':
        groupByKey('supplier');
        break;
      default:
        for (var i = 0; i < rows.length; i++) {
          out.add(productRow(rows[i], i));
        }
    }

    return out;
  }
}

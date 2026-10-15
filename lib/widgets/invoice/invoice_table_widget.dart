import 'package:flutter/material.dart';
import 'dart:math' as math;


class InvoiceTableWidget extends StatelessWidget {
  const InvoiceTableWidget({
    super.key,
    required this.rows,
    required this.onRemoveItem,
    required this.onChangeQuantity,
    required this.getPriceFromRow,
    required this.calculateSubTotal,
    required this.invoiceDiscount,
    required this.isPercentageDiscount,
    required this.shortItemLabel,
    required this.accentColor,
  });

  final List<Map<String, dynamic>> rows;
  final void Function(int index) onRemoveItem;
  final void Function(int index, int delta) onChangeQuantity;
  final double Function(Map<String, dynamic>) getPriceFromRow;
  final double Function() calculateSubTotal;
  final double invoiceDiscount;
  final bool isPercentageDiscount;
  final String Function(String?) shortItemLabel;
  final Color accentColor;

  // Define fixed column widths to ensure headers align perfectly with rows
  static const double colItem = 90;
  static const double colItemName = 160;
  static const double colQty = 60;
  static const double colFree = 60;
  static const double colDisc = 100;
  static const double colPrice = 100;
  static const double colSubtotal = 110;
  static const double colDiscount = 110;
  static const double colTotal = 100;
  static const double colAction = 140;

  Widget _buildCell(Widget child, double width, {Alignment alignment = Alignment.centerLeft, bool isHeader = false}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      alignment: alignment,
      child: isHeader 
          ? DefaultTextStyle(
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87, fontSize: 14),
              child: child,
            )
          : child,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Total calculation that matches the exact original logic
    final totalItemsNet = calculateSubTotal();
    final billDiscountAmount = invoiceDiscount > 0
        ? (isPercentageDiscount ? totalItemsNet * (invoiceDiscount / 100) : invoiceDiscount)
        : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(constraints.maxWidth, 1030),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ==============================
                // HEADER ROW (Fixed at top)
                // ==============================
                Container(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 2)),
                    color: Colors.black.withValues(alpha: 0.04), // Subtle background for header
                  ),
                  child: Row(
                    children: [
                      _buildCell(const Text('Item'), colItem, isHeader: true),
                      _buildCell(const Text('Item Name'), colItemName, isHeader: true),
                      _buildCell(const Text('Qty'), colQty, alignment: Alignment.centerRight, isHeader: true),
                      _buildCell(const Text('Free'), colFree, alignment: Alignment.centerRight, isHeader: true),
                      _buildCell(const Text('Disc ( Rs. )'), colDisc, alignment: Alignment.centerRight, isHeader: true),
                      _buildCell(const Text('Price (Rs.)'), colPrice, alignment: Alignment.centerRight, isHeader: true),
                      _buildCell(const Text('Subtotal (Rs.)'), colSubtotal, alignment: Alignment.centerRight, isHeader: true),
                      _buildCell(const Text('Discount (Rs.)'), colDiscount, alignment: Alignment.centerRight, isHeader: true),
                      _buildCell(const Text('Total (Rs.)'), colTotal, alignment: Alignment.centerRight, isHeader: true),
                      _buildCell(const Text('Action', textAlign: TextAlign.center), colAction, alignment: Alignment.center, isHeader: true),
                    ],
                  ),
                ),
                // ==============================
                // DATA ROWS (Lazy Loaded)
                // ==============================
                Expanded(
                  child: ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final r = rows[index];
                      final price = getPriceFromRow(r);
                      final qty = (r['qty'] as num?)?.toInt() ?? 1;
                      final itemSubtotal = price * qty;

                      final discountStr = (r['discount'] as String?)?.replaceAll(RegExp(r'[^0-9.]'), '') ?? '0';
                      final discountValue = double.tryParse(discountStr) ?? 0.0;
                      final isItemDiscountPercent = (r['discount'] as String?)?.contains('%') ?? false;
                      final itemDiscountAmount = isItemDiscountPercent ? itemSubtotal * (discountValue / 100) : discountValue;

                      final freeQty = (r['freeQty'] as num?)?.toInt() ?? 0;
                      final itemFreeAmount = price * freeQty;

                      final itemNetAfterDiscount = itemSubtotal - itemDiscountAmount - itemFreeAmount;

                      double combinedDiscountAmount = itemDiscountAmount;
                      if (billDiscountAmount > 0 && totalItemsNet > 0) {
                        final itemProportion = itemNetAfterDiscount / totalItemsNet;
                        final itemBillDiscountPortion = billDiscountAmount * itemProportion;
                        combinedDiscountAmount = itemDiscountAmount + itemBillDiscountPortion;
                      }

                      final itemFinalTotal = itemSubtotal - combinedDiscountAmount - itemFreeAmount;

                      return Container(
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.5))),
                        ),
                        child: Row(
                          children: [
                            _buildCell(Text(shortItemLabel(r['item'] as String?), overflow: TextOverflow.ellipsis), colItem),
                            _buildCell(Text(r['item']?.toString().split('•').last.trim() ?? '', overflow: TextOverflow.ellipsis), colItemName),
                            _buildCell(Text('$qty'), colQty, alignment: Alignment.centerRight),
                            _buildCell(Text('${r['freeQty'] ?? 0}'), colFree, alignment: Alignment.centerRight),
                            _buildCell(Text(itemDiscountAmount.toStringAsFixed(2)), colDisc, alignment: Alignment.centerRight),
                            _buildCell(Text(price.toStringAsFixed(2)), colPrice, alignment: Alignment.centerRight),
                            _buildCell(Text(itemSubtotal.toStringAsFixed(2)), colSubtotal, alignment: Alignment.centerRight),
                            _buildCell(Text(combinedDiscountAmount.toStringAsFixed(2)), colDiscount, alignment: Alignment.centerRight),
                            _buildCell(Text(itemFinalTotal.toStringAsFixed(2)), colTotal, alignment: Alignment.centerRight),
                            _buildCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    tooltip: 'Reduce quantity',
                                    onPressed: qty <= 1 ? null : () => onChangeQuantity(index, -1),
                                    icon: const Icon(Icons.remove_rounded, size: 24),
                                    style: IconButton.styleFrom(
                                      minimumSize: const Size(40, 40),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      foregroundColor: accentColor,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Increase quantity',
                                    onPressed: () => onChangeQuantity(index, 1),
                                    icon: const Icon(Icons.add_rounded, size: 24),
                                    style: IconButton.styleFrom(
                                      minimumSize: const Size(40, 40),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      foregroundColor: accentColor,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove item',
                                    onPressed: () => onRemoveItem(index),
                                    icon: const Icon(Icons.delete_outline_rounded, size: 24),
                                    style: IconButton.styleFrom(
                                      minimumSize: const Size(40, 40),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
                                      backgroundColor: Theme.of(context).colorScheme.errorContainer,
                                    ),
                                  ),
                                ],
                              ),
                              colAction,
                              alignment: Alignment.center,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

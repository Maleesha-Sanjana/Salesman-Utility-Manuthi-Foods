import 'package:flutter/foundation.dart';

class CartProvider extends ChangeNotifier {
  String? _customerName;
  String? _customerLocation;
  String? _tableNumber;
  String? _seatNumber;

  String? get customerName => _customerName;
  String? get customerLocation => _customerLocation;
  String? get tableNumber => _tableNumber;
  String? get seatNumber => _seatNumber;

  void setCustomerInfo({
    String? name,
    String? location,
    String? tableNumber,
    String? seatNumber,
  }) {
    _customerName = name;
    _customerLocation = location;
    _tableNumber = tableNumber;
    _seatNumber = seatNumber;
    notifyListeners();
  }

  void clearCart() {
    _customerName = null;
    _customerLocation = null;
    _tableNumber = null;
    _seatNumber = null;
    notifyListeners();
  }
}

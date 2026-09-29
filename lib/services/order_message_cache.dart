import '../models/order_message.dart';

/// In-memory thread so opening Messages is instant after the first load.
class OrderMessageCache {
  static final Map<String, List<OrderMessage>> _byOrder = {};

  static List<OrderMessage> peek(String orderId) {
    return List<OrderMessage>.from(_byOrder[orderId] ?? const []);
  }

  static bool has(String orderId) => _byOrder.containsKey(orderId);

  static void replace(String orderId, List<OrderMessage> messages) {
    _byOrder[orderId] = List<OrderMessage>.from(messages);
  }

  static void clear() => _byOrder.clear();
}

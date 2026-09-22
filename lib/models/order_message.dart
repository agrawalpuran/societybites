class OrderMessage {
  final String id;
  final String orderId;
  final String senderId;
  final String message;
  final DateTime createdAt;
  final DateTime? readAt;
  final String senderRole;

  const OrderMessage({
    required this.id,
    required this.orderId,
    required this.senderId,
    required this.message,
    required this.createdAt,
    this.readAt,
    this.senderRole = 'buyer',
  });

  bool get isFromBuyer => senderRole == 'buyer';

  factory OrderMessage.fromJson(Map<String, dynamic> json) {
    return OrderMessage(
      id: json['id'] as String,
      orderId: json['orderId'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      message: json['message'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      readAt: DateTime.tryParse(json['readAt']?.toString() ?? ''),
      senderRole: json['senderRole'] as String? ?? 'buyer',
    );
  }
}

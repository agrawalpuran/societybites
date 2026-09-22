import 'dart:async';

import 'package:flutter/material.dart';

import '../models/order_message.dart';
import '../services/api_service.dart';

typedef OrderMessagesLoader = Future<List<Map<String, dynamic>>> Function(
  String orderId,
);
typedef OrderMessageSender =
    Future<Map<String, dynamic>> Function(String orderId, String message);

class OrderConversationScreen extends StatefulWidget {
  const OrderConversationScreen({
    super.key,
    required this.orderId,
    required this.orderNumber,
    required this.viewerIsSeller,
    this.fetchMessages,
    this.sendMessage,
    this.pollInterval = const Duration(seconds: 8),
  });

  final String orderId;
  final String orderNumber;
  final bool viewerIsSeller;
  final OrderMessagesLoader? fetchMessages;
  final OrderMessageSender? sendMessage;
  final Duration pollInterval;

  @override
  State<OrderConversationScreen> createState() =>
      _OrderConversationScreenState();
}

class _OrderConversationScreenState extends State<OrderConversationScreen>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<OrderMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    if (widget.pollInterval > Duration.zero) {
      _pollTimer = Timer.periodic(widget.pollInterval, (_) => _load(silent: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load(silent: true);
    }
  }

  Future<List<Map<String, dynamic>>> _fetch(String orderId) {
    return widget.fetchMessages != null
        ? widget.fetchMessages!(orderId)
        : ApiService.getOrderMessages(orderId);
  }

  Future<Map<String, dynamic>> _send(String orderId, String message) {
    return widget.sendMessage != null
        ? widget.sendMessage!(orderId, message)
        : ApiService.sendOrderMessage(orderId: orderId, message: message);
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final rows = await _fetch(widget.orderId);
      if (!mounted) return;
      setState(() {
        _messages = rows.map(OrderMessage.fromJson).toList();
        _loading = false;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLatest());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = 'Could not load messages. Please try again.';
      });
    }
  }

  void _scrollToLatest() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  Future<void> _submit() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final created = await _send(widget.orderId, text);
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, OrderMessage.fromJson(created)];
        _sending = false;
        _error = null;
      });
      _input.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLatest());
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send message. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final emptyHint = widget.viewerIsSeller
        ? 'Use this space to communicate with the buyer about this order.'
        : 'Use this space to communicate with the seller about your order.';

    return Scaffold(
      key: const Key('order-conversation-screen'),
      backgroundColor: const Color(0xFFF7F8F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF101617),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Messages',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            Text(
              'Order #${widget.orderNumber}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6A7774),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF6A7774)),
                      ),
                    ),
                  )
                : _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'No messages yet',
                            key: Key('empty-messages'),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF101617),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            emptyHint,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF6A7774),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return _MessageBubble(message: _messages[index]);
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('message-input'),
                      controller: _input,
                      enabled: !_sending,
                      maxLength: 500,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: 'Type a message...',
                        filled: true,
                        fillColor: const Color(0xFFF5F7F6),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      key: const Key('send-message-button'),
                      onPressed: _sending ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0E5A47),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Send',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final OrderMessage message;

  @override
  Widget build(BuildContext context) {
    final isBuyer = message.isFromBuyer;
    final time = _formatTime(message.createdAt);
    return Align(
      alignment: isBuyer ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          decoration: BoxDecoration(
            color: isBuyer ? const Color(0xFF0E5A47) : const Color(0xFFF0F2F1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isBuyer ? 'Buyer' : 'Seller',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isBuyer ? const Color(0xFFD4E8DF) : const Color(0xFF6A7774),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                message.message,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: isBuyer ? Colors.white : const Color(0xFF101617),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                time,
                style: TextStyle(
                  fontSize: 10,
                  color: isBuyer ? const Color(0xFFD4E8DF) : const Color(0xFF8A9491),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour > 12
        ? local.hour - 12
        : (local.hour == 0 ? 12 : local.hour);
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} $ampm';
  }
}

/// Seller/buyer order lifecycle after the simplified pickup workflow.
///
/// Formal statuses: pending → accepted → ready → completed
///                  pending → rejected
/// Legacy preparing/picked_up are displayed as accepted/ready.
class SellerOrderLifecycle {
  const SellerOrderLifecycle({
    required this.showAccept,
    required this.showReject,
    required this.showMarkReady,
    required this.showComplete,
    required this.treatAsReady,
    required this.badge,
    this.headline,
    this.detail,
    required this.primaryLabel,
  });

  final bool showAccept;
  final bool showReject;
  final bool showMarkReady;
  final bool showComplete;
  final bool treatAsReady;
  final String badge;
  final String? headline;
  final String? detail;
  final String primaryLabel;

  static const none = SellerOrderLifecycle(
    showAccept: false,
    showReject: false,
    showMarkReady: false,
    showComplete: false,
    treatAsReady: false,
    badge: 'ACTIVE',
    primaryLabel: '',
  );

  factory SellerOrderLifecycle.forStatus(String status) {
    switch (status) {
      case 'pending':
        return const SellerOrderLifecycle(
          showAccept: true,
          showReject: true,
          showMarkReady: false,
          showComplete: false,
          treatAsReady: false,
          badge: 'NEW',
          primaryLabel: 'Accept Order',
        );
      case 'accepted':
      case 'preparing':
        return const SellerOrderLifecycle(
          showAccept: false,
          showReject: false,
          showMarkReady: true,
          showComplete: false,
          treatAsReady: false,
          badge: 'ACCEPTED',
          headline: 'Order Accepted',
          detail: 'Your order is being prepared.',
          primaryLabel: 'Mark Ready',
        );
      case 'ready':
      case 'picked_up':
        return const SellerOrderLifecycle(
          showAccept: false,
          showReject: false,
          showMarkReady: false,
          showComplete: true,
          treatAsReady: true,
          badge: 'READY',
          headline: 'Ready for Pickup',
          primaryLabel: 'Complete Order',
        );
      default:
        return none;
    }
  }

  bool get hasPrimaryAction => showAccept || showMarkReady || showComplete;
}

class SellerPaymentActions {
  const SellerPaymentActions({
    required this.isCash,
    required this.showPaymentPending,
    required this.showConfirmOrderAndChooseTime,
    required this.showMarkReady,
    required this.canSetReadyBy,
    required this.promptReadyByOnAccept,
  });

  final bool isCash;
  final bool showPaymentPending;
  final bool showConfirmOrderAndChooseTime;
  final bool showMarkReady;
  final bool canSetReadyBy;
  final bool promptReadyByOnAccept;

  factory SellerPaymentActions.fromOrder({
    required String status,
    String? paymentMethod,
    required String paymentStatus,
  }) {
    final lifecycle = SellerOrderLifecycle.forStatus(status);
    final cash = (paymentMethod ?? 'upi').toLowerCase() == 'cash';
    final confirmed =
        paymentStatus == 'seller_confirmed' || paymentStatus == 'paid';
    final inPrepWindow = lifecycle.showMarkReady;
    return SellerPaymentActions(
      isCash: cash,
      showPaymentPending: !cash && inPrepWindow && !confirmed,
      showConfirmOrderAndChooseTime:
          !cash && paymentStatus == 'buyer_marked_paid',
      showMarkReady: lifecycle.showMarkReady && (cash || confirmed),
      canSetReadyBy: lifecycle.showMarkReady && (cash || confirmed),
      promptReadyByOnAccept: cash,
    );
  }
}

class BuyerOrderLifecycle {
  static const progressSteps = [
    'Order Placed',
    'Confirmed',
    'Ready for Pickup',
    'Completed',
  ];

  static int progressStep(String status) {
    switch (status) {
      case 'pending':
        return 0;
      case 'accepted':
      case 'preparing':
        return 1;
      case 'ready':
      case 'picked_up':
        return 2;
      case 'completed':
        return 3;
      default:
        return -1;
    }
  }

  static String headline(String status) {
    switch (status) {
      case 'pending':
        return 'Waiting for seller confirmation';
      case 'accepted':
      case 'preparing':
        return 'Order confirmed';
      case 'ready':
      case 'picked_up':
        return 'Ready for Pickup';
      case 'completed':
        return 'Order completed';
      case 'rejected':
        return 'Order rejected';
      case 'cancelled':
        return 'Order cancelled';
      default:
        return status;
    }
  }

  static String? detail(String status) {
    switch (status) {
      case 'accepted':
      case 'preparing':
        return 'Your order is being prepared.';
      case 'ready':
      case 'picked_up':
        return 'Please collect your order from the seller.';
      case 'rejected':
        return 'Unfortunately, the seller could not fulfil this order.';
      default:
        return null;
    }
  }

  /// Buyer lifecycle after placing the order is seller-driven.
  /// Cancel remains a separate existing action, not a status-progress action.
  static bool hasProgressAction(String status) => false;

  /// UPI: until the buyer taps I've Paid. COD: until the seller accepts.
  static bool canCancel({
    required String status,
    required String paymentStatus,
    String? paymentMethod,
  }) {
    final method = (paymentMethod ?? 'upi').toLowerCase();
    final isCash = method == 'cash';
    if (isCash) return status == 'pending';

    final paymentLocked = paymentStatus == 'buyer_marked_paid' ||
        paymentStatus == 'seller_confirmed' ||
        paymentStatus == 'paid';
    if (paymentLocked) return false;
    return status == 'pending' || status == 'accepted';
  }

  static bool canPayNow({
    required String status,
    required String paymentStatus,
    String? paymentMethod,
  }) {
    final method = (paymentMethod ?? 'upi').toLowerCase();
    if (method != 'upi' || paymentStatus != 'pending') return false;
    return status == 'accepted' ||
        status == 'preparing' ||
        status == 'ready';
  }
}

/// Status steps to try for Mark Ready.
/// New API: accepted|preparing → ready.
/// Legacy API: accepted → preparing → ready (payment confirm left some
/// orders on preparing).
List<List<String>> markReadyStatusPaths(String currentStatus) {
  switch (currentStatus) {
    case 'accepted':
      return const [
        ['ready'],
        ['preparing', 'ready'],
      ];
    case 'preparing':
      return const [
        ['ready'],
      ];
    default:
      return const [
        ['ready'],
      ];
  }
}

bool isOpenPaymentStatus(String status) =>
    status == 'accepted' || status == 'preparing' || status == 'ready';

bool isTerminalPaymentLeaveStatus(String status) =>
    status == 'cancelled' || status == 'rejected' || status == 'completed';

bool isPaymentFinished(String paymentStatus) =>
    paymentStatus == 'seller_confirmed' ||
    paymentStatus == 'paid' ||
    paymentStatus == 'failed';

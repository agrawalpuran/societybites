import 'data.dart';

/// Client-side My Kitchen grouping. Does not change catalogType or order status.
enum KitchenOrderCategory { orders, madeToOrder, preorders }

KitchenOrderCategory kitchenCategoryForOrder(Order order) {
  if (order.isPreOrder) return KitchenOrderCategory.preorders;
  if (order.hasMadeToOrderItems && !order.hasReadyNowItems) {
    return KitchenOrderCategory.madeToOrder;
  }
  return KitchenOrderCategory.orders;
}

/// Made to Order tab: active MTO orders only.
/// Pre-orders tab: active pre-order orders **or** kitchen campaigns (including closed).
List<KitchenOrderCategory> visibleKitchenCategories({
  required List<Order> orders,
  List<PreOrderCampaign> campaigns = const [],
}) {
  var hasOrders = false;
  var hasMadeToOrder = false;
  var hasPreorderOrders = false;
  for (final order in orders) {
    switch (kitchenCategoryForOrder(order)) {
      case KitchenOrderCategory.orders:
        hasOrders = true;
      case KitchenOrderCategory.madeToOrder:
        hasMadeToOrder = true;
      case KitchenOrderCategory.preorders:
        hasPreorderOrders = true;
    }
  }
  final hasPreorders = hasPreorderOrders || campaigns.isNotEmpty;
  return [
    if (hasOrders) KitchenOrderCategory.orders,
    if (hasMadeToOrder) KitchenOrderCategory.madeToOrder,
    if (hasPreorders) KitchenOrderCategory.preorders,
  ];
}

int kitchenCategoryActionCount({
  required KitchenOrderCategory category,
  required List<Order> orders,
  required List<KitchenOrderCategory> visible,
  required bool Function(Order order) needsAction,
}) {
  return ordersForKitchenCategory(
    source: orders,
    selected: category,
    visible: visible,
  ).where(needsAction).length;
}

List<Order> ordersForKitchenCategory({
  required List<Order> source,
  required KitchenOrderCategory? selected,
  required List<KitchenOrderCategory> visible,
}) {
  if (selected == null || visible.length <= 1) return source;
  return source.where((order) {
    final cat = kitchenCategoryForOrder(order);
    if (selected == KitchenOrderCategory.orders) {
      return cat == KitchenOrderCategory.orders || !visible.contains(cat);
    }
    return cat == selected;
  }).toList();
}

String kitchenCategoryLabel(KitchenOrderCategory category) {
  switch (category) {
    case KitchenOrderCategory.orders:
      return 'Orders';
    case KitchenOrderCategory.madeToOrder:
      return 'Made to Order';
    case KitchenOrderCategory.preorders:
      return 'Pre-orders';
  }
}

KitchenOrderCategory? resolveKitchenCategory({
  required List<KitchenOrderCategory> visible,
  KitchenOrderCategory? selected,
}) {
  if (visible.isEmpty) return null;
  if (visible.length == 1) return visible.first;
  if (selected != null && visible.contains(selected)) return selected;
  return visible.first;
}

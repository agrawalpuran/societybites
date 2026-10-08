import 'package:flutter/material.dart';

class HelpFaq {
  const HelpFaq({
    required this.id,
    required this.question,
    required this.answer,
    this.keywords = const [],
  });

  final String id;
  final String question;
  final String answer;
  final List<String> keywords;
}

class HelpCategory {
  const HelpCategory({
    required this.id,
    required this.title,
    required this.icon,
    required this.faqs,
  });

  final String id;
  final String title;
  final IconData icon;
  final List<HelpFaq> faqs;
}

class HelpSearchHit {
  const HelpSearchHit({required this.category, required this.faq});

  final HelpCategory category;
  final HelpFaq faq;
}

const helpCategories = <HelpCategory>[
  HelpCategory(
    id: 'buying',
    title: '🛒 Buying',
    icon: Icons.shopping_cart_outlined,
    faqs: [
      HelpFaq(
        id: 'buying-what',
        question: 'What is SocietyEats?',
        answer:
            'SocietyEats is a homegrown food marketplace for your apartment community. Neighbours cook, neighbours buy, and you pick up from each other.',
        keywords: ['what is', 'app', 'community', 'homemade', 'marketplace'],
      ),
      HelpFaq(
        id: 'buying-how',
        question: 'How do I buy something?',
        answer:
            'Open Home, tap a dish or a seller, add items to your cart, then checkout with UPI or cash. For UPI, use Pay Now on the order after checkout. For cash, pay the seller when you collect the food.',
        keywords: ['order', 'cart', 'checkout', 'buy', 'purchase'],
      ),
      HelpFaq(
        id: 'buying-other-society',
        question: 'Can I buy from another society?',
        answer:
            'Yes, through Explore Nearby, if a seller nearby has chosen to sell beyond their own society. You cannot order from another city.',
        keywords: ['cross society', 'nearby', 'other society', 'outside'],
      ),
      HelpFaq(
        id: 'buying-one-seller',
        question: 'Can I buy from more than one seller?',
        answer:
            'Your cart can hold items from one seller at a time. If you try to order from someone else, you will be asked to complete or clear your current cart first.',
        keywords: ['multi seller', 'cart', 'another kitchen', 'two sellers'],
      ),
      HelpFaq(
        id: 'buying-no-sellers',
        question: 'What if there are no sellers in my society?',
        answer:
            'You can be the first to start selling, or tap Explore Nearby to see home cooks in neighbouring societies who have opted in.',
        keywords: ['empty', 'no listings', 'first seller', 'home'],
      ),
    ],
  ),
  HelpCategory(
    id: 'selling',
    title: '👩‍🍳 Selling',
    icon: Icons.soup_kitchen_outlined,
    faqs: [
      HelpFaq(
        id: 'selling-start',
        question: 'How do I start selling?',
        answer:
            'Go to Profile and tap Start Selling. Complete Seller Settings — payment methods, UPI, selling reach, fulfilment, and FSSAI — then add a listing from My Kitchen.',
        keywords: ['become seller', 'enable selling', 'onboard'],
      ),
      HelpFaq(
        id: 'selling-upi',
        question: 'Do I need a UPI ID to sell?',
        answer:
            'Yes. Buyers pay you directly. Add your UPI ID in Profile → Seller Settings before you publish a listing.',
        keywords: ['upi', 'payment', 'payout'],
      ),
      HelpFaq(
        id: 'selling-listing',
        question: 'How do I add or edit a listing?',
        answer:
            'Open My Kitchen or My Listings and tap Add Listing. Choose Available now, Made to Order, or Pre-Order, then complete the form. Open any item in My Listings to edit, pause, resume, renew, or remove it.',
        keywords: ['create listing', 'edit', 'my listings', 'publish'],
      ),
      HelpFaq(
        id: 'selling-reach',
        question: 'What is Selling Reach?',
        answer:
            'Selling Reach decides who can find you. My Society stays inside your community. Nearby and Extended let buyers in your city see you, up to the distance set for your city.',
        keywords: ['reach', 'nearby', 'extended', 'visibility'],
      ),
      HelpFaq(
        id: 'selling-pause-renew',
        question: 'How do I pause or renew a listing?',
        answer:
            'Pause hides a dish from buyers until you resume it. If a listing expires after its available-until time, use Renew and pick a new time.',
        keywords: ['pause', 'resume', 'expired', 'available until'],
      ),
      HelpFaq(
        id: 'selling-orders',
        question: 'How do I manage seller orders?',
        answer:
            'Open My Kitchen → Orders. Available-now regular orders are confirmed when placed — use Mark Ready when the food is prepared, then Complete Order after handoff. If you cannot fulfil an auto-confirmed order, use Can\'t fulfil before you mark it ready. For UPI, after the buyer taps I\'ve paid, confirm you received the payment — Mark Ready stays hidden until you do. Made to order and pre-order requests start as pending — Accept or Reject them first. For cash, confirm cash received when prompted. Cross-society orders can include the delivery charge you set in Seller Settings.',
        keywords: [
          'accept',
          'ready',
          'dashboard',
          'reject',
          'delivery',
          'cannot fulfil',
        ],
      ),
    ],
  ),
  HelpCategory(
    id: 'nearby',
    title: '📍 Explore Nearby',
    icon: Icons.location_on_outlined,
    faqs: [
      HelpFaq(
        id: 'nearby-what',
        question: 'What is Explore Nearby?',
        answer:
            'Explore Nearby lets you discover sellers from nearby societies who have chosen to sell beyond their own society.',
        keywords: ['explore', 'nearby', 'discover', 'distance'],
      ),
      HelpFaq(
        id: 'nearby-empty',
        question: 'Why don\'t I see nearby sellers?',
        answer:
            'Sellers appear here only if they choose Nearby or Extended selling. Many cooks stay on My Society, so they will not show up even if they live close by.',
        keywords: ['empty', 'no sellers', 'opt in', 'my society'],
      ),
      HelpFaq(
        id: 'nearby-order',
        question: 'Can I order from a nearby seller?',
        answer:
            'Yes. Open their menu from Explore Nearby and checkout as usual. Pickup or seller delivery depends on how that seller fulfils orders.',
        keywords: ['order nearby', 'cross society', 'storefront'],
      ),
      HelpFaq(
        id: 'nearby-distance',
        question: 'How far is Nearby and Extended?',
        answer:
            'The distance is set for your city, not by each seller. Nearby is the closer radius. Extended reaches a little farther in the same city.',
        keywords: ['km', 'radius', 'extended', 'city', 'how far'],
      ),
      HelpFaq(
        id: 'nearby-home-distance',
        question: 'How do I choose how far Home looks?',
        answer:
            'On the phone Home screen, tap the distance chip under search. It may say My Society, Within 1 km, or Extended. Choose how far you want to explore, then tap Apply. My Society keeps your own community. Shorter steps, such as 500 m, 1 km, or 3 km, also keep closer dishes. Extended is the widest range your city allows, and Home opens on that range. Your choice lasts for this visit. Dishes from your own society stay in the list.',
        keywords: [
          'distance',
          'wizard',
          'how far',
          'home filter',
          'within',
          'my society',
          'km',
        ],
      ),
      HelpFaq(
        id: 'nearby-opt-in',
        question: 'How do I appear in Explore Nearby as a seller?',
        answer:
            'After you start selling, open Profile and change Selling Reach to Nearby or Extended, if your city has those options turned on.',
        keywords: ['opt in', 'appear', 'selling reach', 'show up'],
      ),
    ],
  ),
  HelpCategory(
    id: 'fulfilment',
    title: '🚚 Pickup & Delivery',
    icon: Icons.local_shipping_outlined,
    faqs: [
      HelpFaq(
        id: 'fulfilment-society-pickup',
        question: 'How do I collect an order in my society?',
        answer:
            'Most same-society orders are pickup. After the seller marks the order ready, collect it from their home or the pickup note on the order.',
        keywords: ['pickup', 'collect', 'same society', 'home'],
      ),
      HelpFaq(
        id: 'fulfilment-seller-delivery',
        question: 'What is Seller Delivery?',
        answer:
            'Some sellers can bring the order to you themselves. This is arranged by the seller, not by a SocietyEats driver.',
        keywords: ['delivery', 'seller delivery', 'drop'],
      ),
      HelpFaq(
        id: 'fulfilment-charge',
        question: 'Who pays the delivery charge?',
        answer:
            'If you choose seller delivery, the seller\'s delivery charge is added at checkout. Pickup has no delivery charge.',
        keywords: ['delivery charge', 'fee', 'cost', 'free delivery'],
      ),
      HelpFaq(
        id: 'fulfilment-track',
        question: 'Can I track a delivery live?',
        answer:
            'No. SocietyEats does not show live tracking or a delivery ETA. Follow the order status and message the seller if you need an update.',
        keywords: ['tracking', 'eta', 'driver', 'live', 'gps'],
      ),
      HelpFaq(
        id: 'fulfilment-choose',
        question: 'Can I choose pickup or delivery?',
        answer:
            'On nearby orders, you can choose if the seller offers both. If they only offer pickup or only delivery, that option is used.',
        keywords: ['both', 'choose', 'option', 'fulfilment'],
      ),
    ],
  ),
  HelpCategory(
    id: 'orders',
    title: '📦 Orders',
    icon: Icons.inventory_2_outlined,
    faqs: [
      HelpFaq(
        id: 'orders-where',
        question: 'Where do I see my orders?',
        answer:
            'Open Orders in the bottom bar, or tap My Orders on Profile. Active orders stay on top. An order that has just finished, been cancelled or been declined stays in Active for 24 hours so you do not miss the outcome, then moves to past orders. Pickup and delivery details stay on the order if it came from a nearby seller.',
        keywords: ['my orders', 'history', 'track', 'delivery'],
      ),
      HelpFaq(
        id: 'orders-status',
        question: 'What do order statuses mean?',
        answer:
            'Pending means waiting for the seller to accept (made to order and pre-orders). Regular available-now orders usually start at accepted. The seller then marks ready when you can collect. After handoff they mark completed. For UPI you may see payment steps before or alongside preparation — pay in your UPI app, tap I\'ve paid, and wait for the seller to confirm.',
        keywords: ['status', 'pending', 'accepted', 'ready', 'completed', 'upi'],
      ),
      HelpFaq(
        id: 'orders-collect',
        question: 'When do I collect my order?',
        answer:
            'Watch the order in the Orders tab. When the seller marks it ready, you will see ready for pickup with their flat and block. Collect the food in person. The seller marks the order complete after handoff — you do not need a separate picked-up button in the app.',
        keywords: ['picked up', 'collected', 'pickup', 'ready'],
      ),
      HelpFaq(
        id: 'orders-upi',
        question: 'How does UPI payment work?',
        answer:
            'Choose UPI at checkout, then open Pay Now on the order. Pay the seller in your UPI app using the ID shown, return to SocietyEats, and tap I\'ve paid. The seller confirms they received the money. SocietyEats does not hold your payment — it goes directly to the seller.',
        keywords: ['upi', 'pay now', 'ive paid', 'payment', 'confirm'],
      ),
      HelpFaq(
        id: 'orders-cancel',
        question: 'Can I cancel an order?',
        answer:
            'Use Cancel Order while it still appears on your order. For UPI, that is until you tap I\'ve paid. For cash, until the seller marks the order ready (regular orders are confirmed immediately, so you can still cancel while accepted). Pre-orders can be cancelled before the campaign Order by time. After that, message the seller or email support.societyeats@gmail.com.',
        keywords: ['cancel', 'reject', 'stop order'],
      ),
      HelpFaq(
        id: 'orders-seller-cannot-fulfil',
        question: 'What if the seller cannot make my order?',
        answer:
            'For made to order or pre-orders, the seller can reject while the order is still pending. For regular orders they may use Can\'t fulfil until the food is ready. You will see the reason on the order. If you had already paid by UPI, settle any refund with the seller through Messages. SocietyEats does not hold your money.',
        keywords: ['cannot fulfil', 'rejected', 'refund', 'money back'],
      ),
      HelpFaq(
        id: 'orders-cash',
        question: 'What if I paid cash?',
        answer:
            'Pay the seller when you collect the order. The seller confirms cash received before the order can be completed.',
        keywords: ['cash', 'cod', 'confirm payment'],
      ),
    ],
  ),
  HelpCategory(
    id: 'made-to-order',
    title: '🍳 Made to Order',
    icon: Icons.restaurant_outlined,
    faqs: [
      HelpFaq(
        id: 'mto-what',
        question: 'What is Made to Order?',
        answer:
            'The seller prepares this only after you place an order. It is not ready now, and it is not a group pre-order for a fixed date.',
        keywords: ['made to order', 'mto', 'prepare after', 'not ready now'],
      ),
      HelpFaq(
        id: 'mto-order',
        question: 'How do I order a Made to Order item?',
        answer:
            'Add it from Home or the seller\'s menu and checkout as usual. You can request when you need it. The order stays pending until the seller accepts or rejects it, then they prepare it on the timeline shown on the listing.',
        keywords: ['need by', 'checkout', 'confirm availability', 'lead time'],
      ),
      HelpFaq(
        id: 'mto-time',
        question: 'How long does Made to Order take?',
        answer:
            'The listing shows the seller\'s usual preparation time. They still confirm availability after you order. If it says currently unavailable, you cannot order it until the seller turns it back on.',
        keywords: ['preparation time', 'unavailable', 'how long', 'lead'],
      ),
      HelpFaq(
        id: 'mto-seller',
        question: 'How do I sell a Made to Order item?',
        answer:
            'From Add Listing, choose Made to Order and set a preparation time. It appears under My Listings → Made to Order. New orders show in My Kitchen under Made to Order.',
        keywords: ['add listing', 'my kitchen', 'my listings', 'seller'],
      ),
      HelpFaq(
        id: 'mto-vs-preorder',
        question: 'How is Made to Order different from a pre-order?',
        answer:
            'Made to Order is your own request, cooked after you order. A pre-order collects many orders in a set window and is fulfilled together on a planned date.',
        keywords: ['difference', 'pre-order', 'campaign', 'batch'],
      ),
    ],
  ),
  HelpCategory(
    id: 'preorders',
    title: '❤️ Pre-orders',
    icon: Icons.favorite_outline,
    faqs: [
      HelpFaq(
        id: 'preorders-what',
        question: 'What is a pre-order?',
        answer:
            'A pre-order collects orders during a set window. The seller then prepares them together for a planned fulfilment time. It is not ready-now food.',
        keywords: ['campaign', 'preorder', 'batch', 'future date'],
      ),
      HelpFaq(
        id: 'preorders-join',
        question: 'How do I join a pre-order?',
        answer:
            'Open the campaign on Home. Before the opening time it shows Coming soon. While it is open, choose products and place the pre-order before the Order by time. A pre-order checks out separately from a regular cart.',
        keywords: ['join', 'book', 'home', 'campaign', 'coming soon', 'cart'],
      ),
      HelpFaq(
        id: 'preorders-cutoff',
        question: 'When does a pre-order close?',
        answer:
            'New orders stop at the Order by time. After that, the campaign can still be seen until fulfilment, marked Orders closed. You can cancel your own pre-order from Orders before that cutoff.',
        keywords: ['cutoff', 'close', 'deadline', 'order by', 'cancel'],
      ),
      HelpFaq(
        id: 'preorders-fulfilment',
        question: 'How is a pre-order fulfilled?',
        answer:
            'The campaign shows a fulfilment date and time. You collect it, or the seller delivers it, using the options they offered. That time is scheduled. It is not immediate pickup.',
        keywords: ['fulfilment', 'pickup notes', 'when ready', 'delivery'],
      ),
      HelpFaq(
        id: 'preorders-change',
        question: 'Can a seller change a pre-order after people have ordered?',
        answer:
            'After the first order, the opening time, cutoff, fulfilment time, fulfilment options, delivery charge, and existing products stay locked. The seller can still update the description, fulfilment notes, and cover image.',
        keywords: ['edit campaign', 'locked', 'already ordered'],
      ),
    ],
  ),
  HelpCategory(
    id: 'ratings',
    title: '⭐ Ratings & Feedback',
    icon: Icons.star_outline,
    faqs: [
      HelpFaq(
        id: 'ratings-when',
        question: 'When can I leave a rating?',
        answer:
            'After an order is completed, you can leave feedback from that order. You can do this once per order.',
        keywords: ['review', 'rating', 'feedback', 'completed'],
      ),
      HelpFaq(
        id: 'ratings-what',
        question: 'What can I rate?',
        answer:
            'You can give stars, write a short note, add tags, and say whether you would order again.',
        keywords: ['stars', 'comment', 'would order again', 'tags'],
      ),
      HelpFaq(
        id: 'ratings-see',
        question: 'Can I see other buyers\' reviews?',
        answer:
            'Yes. Dish and seller pages show ratings and reviews from neighbours who have ordered before.',
        keywords: ['reviews', 'avg rating', 'storefront'],
      ),
      HelpFaq(
        id: 'ratings-edit',
        question: 'Can I edit a review later?',
        answer:
            'Once you submit feedback for an order, it stays as you wrote it. Leave a new review the next time you order.',
        keywords: ['edit review', 'change feedback'],
      ),
    ],
  ),
  HelpCategory(
    id: 'profile',
    title: '👤 Profile & Payments',
    icon: Icons.person_outline,
    faqs: [
      HelpFaq(
        id: 'profile-name',
        question: 'How do I update my name?',
        answer:
            'Open Profile, tap Edit Profile, change your display name, and save.',
        keywords: ['edit profile', 'name', 'display name'],
      ),
      HelpFaq(
        id: 'profile-pay',
        question: 'How do payments work?',
        answer:
            'SocietyEats does not process payments or hold your money. You pay the seller directly by UPI (Pay Now on the order, then I\'ve paid after your UPI app) or in cash at pickup. There is no in-app payment gateway.',
        keywords: ['upi', 'cash', 'gateway', 'razorpay', 'pay'],
      ),
      HelpFaq(
        id: 'profile-society',
        question: 'Can I change my society?',
        answer:
            'Your society cannot be changed after you join. Email support.societyeats@gmail.com if you have moved and need help.',
        keywords: ['change society', 'move', 'wrong society'],
      ),
      HelpFaq(
        id: 'profile-fee',
        question: 'What is the platform fee?',
        answer:
            'Checkout may add a small platform fee set by SocietyEats. You will see it on the bill before you place the order.',
        keywords: ['platform fee', 'community fee', 'charges'],
      ),
      HelpFaq(
        id: 'profile-upi',
        question: 'How do I add my UPI ID?',
        answer:
            'Open Profile → Seller Settings → UPI for Payments. Enter an ID like name@bank and a display name buyers will see.',
        keywords: ['upi id', 'add upi', 'seller payment'],
      ),
    ],
  ),
  HelpCategory(
    id: 'issues',
    title: '🆘 Common Issues',
    icon: Icons.support_agent_outlined,
    faqs: [
      HelpFaq(
        id: 'issues-empty-home',
        question: 'I don\'t see any food on Home',
        answer:
            'Home shows cooks in your society plus nearby cooks who opted into Nearby or Extended selling. If the feed is empty, pull to refresh, try Explore Nearby, or start selling yourself.',
        keywords: ['blank home', 'no food', 'empty'],
      ),
      HelpFaq(
        id: 'issues-nearby-empty',
        question: 'Explore Nearby is empty',
        answer:
            'Nearby sellers must opt into Nearby or Extended selling. Distance alone is not enough. Pull to refresh after a cook nearby changes their reach.',
        keywords: ['nearby empty', '12 km', 'delivery', 'no nearby'],
      ),
      HelpFaq(
        id: 'issues-two-carts',
        question: 'I can\'t add items from two kitchens',
        answer:
            'That is expected. Finish or clear your current cart before ordering from another seller.',
        keywords: ['two sellers', 'cart blocked', 'replace cart'],
      ),
      HelpFaq(
        id: 'issues-listing-gone',
        question: 'A listing disappeared',
        answer:
            'Sellers can pause or remove a dish, and listings expire after their available-until time. Ask the seller or check back later.',
        keywords: ['expired', 'paused', 'missing listing', 'sold out'],
      ),
      HelpFaq(
        id: 'issues-support',
        question: 'How do I contact support?',
        answer:
            'Email support.societyeats@gmail.com. We typically reply within 24 hours.',
        keywords: ['email', 'help', 'contact', 'support'],
      ),
    ],
  ),
];

int get helpFaqCount =>
    helpCategories.fold<int>(0, (sum, category) => sum + category.faqs.length);

List<HelpSearchHit> searchHelpFaqs(String rawQuery) {
  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) return const [];

  final hits = <HelpSearchHit>[];
  for (final category in helpCategories) {
    for (final faq in category.faqs) {
      final haystack = [
        faq.question,
        faq.answer,
        category.title,
        ...faq.keywords,
      ].join(' ').toLowerCase();
      if (haystack.contains(query)) {
        hits.add(HelpSearchHit(category: category, faq: faq));
      }
    }
  }
  return hits;
}

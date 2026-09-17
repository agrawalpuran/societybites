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
        question: 'What is SocietyBites?',
        answer:
            'SocietyBites is a homegrown food marketplace for your apartment community. Neighbours cook, neighbours buy, and you pick up from each other.',
        keywords: ['what is', 'app', 'community', 'homemade', 'marketplace'],
      ),
      HelpFaq(
        id: 'buying-how',
        question: 'How do I buy something?',
        answer:
            'Open Home, tap a dish or a seller, add items to your cart, then checkout. You can pay with UPI or cash when you collect the order.',
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
            'Your cart can hold items from one seller at a time. If you add food from someone else, you will be asked to start a new cart.',
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
            'Go to Profile and tap Start Selling. Then add your UPI ID so neighbours can pay you, and create a listing from My Listings or the Seller Dashboard.',
        keywords: ['become seller', 'enable selling', 'onboard'],
      ),
      HelpFaq(
        id: 'selling-upi',
        question: 'Do I need a UPI ID to sell?',
        answer:
            'Yes. Buyers pay you directly. Add your UPI ID in Profile before you publish a listing.',
        keywords: ['upi', 'payment', 'payout'],
      ),
      HelpFaq(
        id: 'selling-listing',
        question: 'How do I add or edit a listing?',
        answer:
            'Open My Listings from Profile or the Seller Dashboard. Tap Add to publish, or open an item to edit, pause, resume, or remove it.',
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
            'Open the Seller Dashboard. You can accept an order, mark it preparing or ready, reject it if needed, and confirm cash when a buyer pays in cash. Nearby delivery orders use the charge you set in Profile.',
        keywords: ['accept', 'ready', 'dashboard', 'reject', 'delivery'],
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
            'Some sellers can bring the order to you themselves. This is arranged by the seller, not by a SocietyBites driver.',
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
            'No. SocietyBites does not show live tracking or a delivery ETA. Follow the order status and message the seller if you need an update.',
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
            'Open Orders in the bottom bar, or tap My Orders on Profile. Active orders stay on top. Completed ones move to past orders. Pickup and delivery details stay on the order if it came from a nearby seller.',
        keywords: ['my orders', 'history', 'track', 'delivery'],
      ),
      HelpFaq(
        id: 'orders-status',
        question: 'What do order statuses mean?',
        answer:
            'Pending means the seller has not accepted yet. Then the order moves to preparing and ready. After you collect it, it is completed.',
        keywords: ['status', 'pending', 'accepted', 'ready', 'completed'],
      ),
      HelpFaq(
        id: 'orders-picked-up',
        question: 'How do I mark an order as picked up?',
        answer:
            'When the order is ready, use Mark Picked Up on your order. That tells the seller you have collected it.',
        keywords: ['picked up', 'collected', 'complete'],
      ),
      HelpFaq(
        id: 'orders-cancel',
        question: 'Can I cancel an order?',
        answer:
            'There is no in-app cancel button for buyers. Ask the seller if they can reject it, or write to support@societybites.in if you need help.',
        keywords: ['cancel', 'reject', 'stop order'],
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
    id: 'preorders',
    title: '❤️ Pre-orders',
    icon: Icons.favorite_outline,
    faqs: [
      HelpFaq(
        id: 'preorders-what',
        question: 'What is a pre-order?',
        answer:
            'A pre-order is a planned batch. You book before the seller cooks, so they know how much to make.',
        keywords: ['campaign', 'preorder', 'batch'],
      ),
      HelpFaq(
        id: 'preorders-join',
        question: 'How do I join a pre-order?',
        answer:
            'Open a pre-order from Home, choose what you want, and checkout before the cutoff time.',
        keywords: ['join', 'book', 'home', 'campaign'],
      ),
      HelpFaq(
        id: 'preorders-cutoff',
        question: 'When does a pre-order close?',
        answer:
            'Each campaign has an order cutoff. After that time, new orders stop so the seller can cook.',
        keywords: ['cutoff', 'close', 'deadline'],
      ),
      HelpFaq(
        id: 'preorders-fulfilment',
        question: 'How is a pre-order fulfilled?',
        answer:
            'The seller shares a fulfilment time and any pickup notes on the campaign. Collect or receive it as those notes say.',
        keywords: ['fulfilment', 'pickup notes', 'when ready'],
      ),
      HelpFaq(
        id: 'preorders-change',
        question: 'Can a seller change a pre-order after people have ordered?',
        answer:
            'Once orders are placed on a campaign product, that product cannot be changed. This keeps what you booked the same.',
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
            'SocietyBites does not take the payment. You pay the seller directly with UPI or cash. There is no in-app payment gateway.',
        keywords: ['upi', 'cash', 'gateway', 'razorpay', 'pay'],
      ),
      HelpFaq(
        id: 'profile-society',
        question: 'Can I change my society?',
        answer:
            'Your society cannot be changed after you join. Email support@societybites.in if you have moved and need help.',
        keywords: ['change society', 'move', 'wrong society'],
      ),
      HelpFaq(
        id: 'profile-fee',
        question: 'What is the platform fee?',
        answer:
            'Checkout may add a small platform fee set by SocietyBites. You will see it on the bill before you place the order.',
        keywords: ['platform fee', 'community fee', 'charges'],
      ),
      HelpFaq(
        id: 'profile-upi',
        question: 'How do I add my UPI ID?',
        answer:
            'Open Profile and tap UPI for Payments. Enter an ID like name@bank and a display name buyers will see.',
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
            'Home only shows cooks in your society. If nobody is listing yet, use Explore Nearby or start selling yourself.',
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
            'Email support@societybites.in. We typically reply within 24 hours.',
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

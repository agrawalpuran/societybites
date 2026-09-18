const listingFoodCategories = [
  'Breakfast',
  'Lunch',
  'Dinner',
  'Snacks',
  'Desserts',
];

const allListingCategoriesLabel = 'All Categories';

String? normalizeListingCategory(String? value) {
  if (value == null) return null;
  final raw = value.trim();
  if (raw.isEmpty) return null;
  final upper = raw.toUpperCase().replaceAll('-', '_');
  if (upper == 'ALL' || raw.toLowerCase() == 'all categories') return null;
  for (final label in listingFoodCategories) {
    if (label.toLowerCase() == raw.toLowerCase() ||
        label.toUpperCase() == upper) {
      return label;
    }
  }
  return raw;
}

List<String> parseListingCategoriesFromJson(Map<String, dynamic> json) {
  final raw = json['categories'];
  if (raw is List && raw.isNotEmpty) {
    return raw
        .map((item) => normalizeListingCategory(item?.toString()))
        .whereType<String>()
        .toList();
  }
  final single = normalizeListingCategory(json['category']?.toString());
  if (single == null) return const [];
  return [single];
}

bool isAllListingCategoriesSelected(Iterable<String> selected) {
  final set = selected.toSet();
  return listingFoodCategories.every(set.contains);
}

Set<String> toggleListingCategory(
  Set<String> current, {
  required String option,
  required bool selected,
}) {
  final next = Set<String>.from(current);
  if (option == allListingCategoriesLabel) {
    if (selected) {
      next.addAll(listingFoodCategories);
    } else {
      next.removeAll(listingFoodCategories);
    }
    return next;
  }
  if (selected) {
    next.add(option);
  } else {
    next.remove(option);
  }
  return next;
}

String formatAvailableIn(Iterable<String> categories) {
  final selected = listingFoodCategories
      .where((item) => categories.contains(item))
      .toList();
  if (selected.isEmpty) {
    final extras = categories.map((item) => item.trim()).where((item) => item.isNotEmpty);
    return extras.join(', ');
  }
  if (selected.length == listingFoodCategories.length) {
    return allListingCategoriesLabel;
  }
  return selected.join(', ');
}

bool listingMatchesHomeCategory(
  Iterable<String> categories, {
  String? selectedCategory,
  String? legacyCategory,
}) {
  if (selectedCategory == null || selectedCategory == 'All') return true;
  final values = [
    ...categories,
    if (legacyCategory != null && legacyCategory.trim().isNotEmpty) legacyCategory,
  ];
  return values.any(
    (item) => item.toLowerCase() == selectedCategory.toLowerCase(),
  );
}

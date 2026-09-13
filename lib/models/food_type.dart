const foodTypeVeg = 'VEG';
const foodTypeNonVeg = 'NON_VEG';

String? parseFoodType(dynamic value) {
  if (value == null) return null;
  final mapped = value.toString().trim().toUpperCase().replaceAll('-', '_');
  if (mapped == foodTypeVeg || mapped == foodTypeNonVeg) return mapped;
  return null;
}

/// Returns an error message if the seller cannot submit, otherwise null.
String? foodTypeSelectionError({
  required String? foodType,
  List<String> tags = const [],
}) {
  if (foodType != foodTypeVeg && foodType != foodTypeNonVeg) {
    return 'Please select a food type.';
  }
  final normalized = tags.map((tag) => tag.trim().toLowerCase()).toList();
  if (normalized.contains('egg') && foodType != foodTypeNonVeg) {
    return 'Egg listings must be Non-Vegetarian.';
  }
  if ((normalized.contains('vegan') || normalized.contains('jain')) &&
      foodType != foodTypeVeg) {
    return 'Vegan and Jain listings must be Vegetarian.';
  }
  return null;
}

List<Map<String, dynamic>> filterSocieties({
  required List<Map<String, dynamic>> societies,
  required String query,
  int minQueryLength = 2,
}) {
  final normalized = query.trim().toLowerCase();
  if (normalized.length < minQueryLength) return const [];

  return societies.where((society) {
    final haystack = [
      society['name'],
      society['address'],
      society['city'],
      society['state'],
      society['pincode'],
    ].map((value) => value?.toString().trim().toLowerCase() ?? '').join(' ');
    return haystack.contains(normalized);
  }).toList();
}

String societyLocationLabel(Map<String, dynamic> society) {
  final address = society['address']?.toString().trim() ?? '';
  final city = society['city']?.toString().trim() ?? '';
  final state = society['state']?.toString().trim() ?? '';
  final pincode = society['pincode']?.toString().trim() ?? '';

  final parts = <String>[
    if (address.isNotEmpty) address,
    if (city.isNotEmpty) city,
    if (state.isNotEmpty && state.toLowerCase() != city.toLowerCase()) state,
    if (pincode.isNotEmpty) pincode,
  ];
  return parts.join(', ');
}

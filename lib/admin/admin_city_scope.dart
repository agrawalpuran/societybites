import 'package:flutter/material.dart';

import '../models/serving_city.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';

class AdminCityScopeController extends ChangeNotifier {
  String? selectedCityKey;
  List<ServingCity> activeCities = const [];
  bool loading = false;

  String? get selectedDisplayName {
    if (selectedCityKey == null) return null;
    for (final city in activeCities) {
      if (city.cityKey == selectedCityKey) return city.displayName;
    }
    return selectedCityKey;
  }

  Future<void> bootstrap() async {
    final saved = await SessionService.getAdminCityScope();
    if (saved != null && saved.isNotEmpty) {
      selectedCityKey = saved;
    }
    await reloadActiveCities();
  }

  Future<void> reloadActiveCities() async {
    loading = true;
    notifyListeners();
    try {
      final data = await ApiService.getAdminDashboardCities();
      final rawActive = data['activeCities'];
      var cities = const <ServingCity>[];
      if (rawActive is List) {
        cities = rawActive
            .whereType<Map>()
            .map(
              (row) => ServingCity(
                cityKey: row['cityKey']?.toString() ?? '',
                displayName: row['displayName']?.toString() ?? '',
                state: row['state']?.toString() ?? '',
                active: true,
              ),
            )
            .where((c) => c.cityKey.isNotEmpty)
            .toList();
      }
      activeCities = cities;
      if (selectedCityKey != null &&
          !cities.any((c) => c.cityKey == selectedCityKey)) {
        selectedCityKey = null;
        await SessionService.saveAdminCityScope(null);
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> selectCity(String? cityKey) async {
    if (selectedCityKey == cityKey) return;
    selectedCityKey = cityKey;
    await SessionService.saveAdminCityScope(cityKey);
    notifyListeners();
  }
}

class AdminCityScope extends InheritedNotifier<AdminCityScopeController> {
  const AdminCityScope({
    super.key,
    required AdminCityScopeController controller,
    required super.child,
  }) : super(notifier: controller);

  static AdminCityScopeController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AdminCityScope>()
        ?.notifier;
  }
}

/// Reload lists when the shell city chip changes.
mixin AdminCityScopeListener<T extends StatefulWidget> on State<T> {
  AdminCityScopeController? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = AdminCityScope.maybeOf(context);
    if (identical(next, _scope)) return;
    _scope?.removeListener(_onCityScopeChanged);
    _scope = next;
    _scope?.addListener(_onCityScopeChanged);
  }

  @override
  void dispose() {
    _scope?.removeListener(_onCityScopeChanged);
    super.dispose();
  }

  void _onCityScopeChanged() {
    if (!mounted) return;
    onAdminCityScopeChanged();
  }

  String? get adminCityKey => _scope?.selectedCityKey;

  @protected
  void onAdminCityScopeChanged();
}

bool adminShellTabUsesCityScope(int index) {
  return index == 0 ||
      index == 1 ||
      index == 5 ||
      index == 6 ||
      index == 7 ||
      index == 8 ||
      index == 9 ||
      index == 10;
}
import 'package:flutter/material.dart';

import '../../models/serving_city.dart';
import '../../services/api_service.dart';
import '../../services/session_service.dart';
import '../../widgets/admin_loading_panel.dart';

class AdminServingCitiesScreen extends StatefulWidget {
  const AdminServingCitiesScreen({super.key});

  @override
  State<AdminServingCitiesScreen> createState() => _AdminServingCitiesScreenState();
}

class _AdminServingCitiesScreenState extends State<AdminServingCitiesScreen> {
  List<ServingCity> _cities = const [];
  bool _isLoading = true;
  bool _isSuperAdmin = false;
  String? _error;
  String? _savingKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.getAdminServingCities(),
        SessionService.getRole(),
      ]);
      if (!mounted) return;
      setState(() {
        _cities = results[0] as List<ServingCity>;
        _isSuperAdmin = results[1] == 'super_admin';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _toggle(ServingCity city, bool active) async {
    if (!_isSuperAdmin || _savingKey != null) return;
    final next = _cities
        .map((row) => row.cityKey == city.cityKey ? row.copyWith(active: active) : row)
        .toList();
    final keys = next.where((row) => row.active).map((row) => row.cityKey).toList();
    if (keys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one city must stay on')),
      );
      return;
    }

    setState(() => _savingKey = city.cityKey);
    try {
      final saved = await ApiService.updateAdminServingCities(keys);
      if (!mounted) return;
      setState(() {
        _cities = saved;
        _savingKey = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingKey = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update cities: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeNames = _cities
        .where((city) => city.active)
        .map((city) => city.displayName)
        .toList();
    final serving = activeNames.isEmpty
        ? 'Bengaluru'
        : activeNames.length == 1
            ? activeNames.first
            : activeNames.length == 2
                ? '${activeNames[0]} and ${activeNames[1]}'
                : '${activeNames.sublist(0, activeNames.length - 1).join(', ')}, and ${activeNames.last}';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E5A47),
        foregroundColor: Colors.white,
        title: const Text(
          'Serving cities',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _isLoading
          ? const AdminLoadingPanel(message: 'Loading serving cities…')
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: const Color(0xFF0E5A47),
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        'Now serving $serving',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0E5A47),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isSuperAdmin
                            ? 'Turn a known city on when you are ready to accept societies there. At least one city stays on. A city that is not in this list has to be added in the app before it can be switched on.'
                            : 'View only. A super admin can change which cities are open.',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF6A7774)),
                      ),
                      const SizedBox(height: 16),
                      ..._cities.map((city) {
                        final saving = _savingKey == city.cityKey;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFEAEFED)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          city.displayName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                            color: Color(0xFF101617),
                                          ),
                                        ),
                                        Text(
                                          city.state,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF6A7774),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (saving)
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  else
                                    Switch(
                                      value: city.active,
                                      activeThumbColor: const Color(0xFF0E5A47),
                                      onChanged: _isSuperAdmin
                                          ? (value) => _toggle(city, value)
                                          : null,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }
}

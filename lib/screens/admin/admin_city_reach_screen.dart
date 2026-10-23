import 'package:flutter/material.dart';

import '../../models/selling_reach.dart';
import '../../services/api_service.dart';
import '../../widgets/admin_loading_panel.dart';

class AdminCityReachScreen extends StatefulWidget {
  const AdminCityReachScreen({super.key});

  @override
  State<AdminCityReachScreen> createState() => _AdminCityReachScreenState();
}

class _AdminCityReachScreenState extends State<AdminCityReachScreen> {
  List<CityReachConfig> _configs = const [];
  bool _isLoading = true;
  String? _error;

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
      final configs = await ApiService.getAdminCityReachConfigs();
      if (!mounted) return;
      setState(() {
        _configs = configs;
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

  Future<void> _edit({CityReachConfig? existing}) async {
    final cityController = TextEditingController(text: existing?.cityKey ?? '');
    final displayController = TextEditingController(text: existing?.displayName ?? '');
    final maxSellerController = TextEditingController(
      text: existing == null
          ? '10'
          : existing.maxSellerRadiusKm.toString(),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add city reach' : 'Edit city reach'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: cityController,
                enabled: existing == null,
                decoration: const InputDecoration(
                  labelText: 'City',
                  hintText: 'Bengaluru',
                ),
              ),
              TextField(
                controller: displayController,
                decoration: const InputDecoration(labelText: 'Display name'),
              ),
              TextField(
                controller: maxSellerController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Max reach (km)',
                  helperText:
                      'Buyer Home “Up to” menu and the seller Selling Reach bar both use this maximum.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    final cityKey = cityController.text.trim();
    final displayName = displayController.text.trim();
    final maxSeller = double.tryParse(maxSellerController.text.trim());
    cityController.dispose();
    displayController.dispose();
    maxSellerController.dispose();

    if (saved != true || !mounted) return;
    if (cityKey.isEmpty || maxSeller == null || maxSeller < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('City and max reach (km) are required')),
      );
      return;
    }

    try {
      await ApiService.upsertAdminCityReachConfig(
        cityKey: cityKey,
        maxSellerRadiusKm: maxSeller,
        displayName: displayName.isEmpty ? null : displayName,
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('City reach configuration saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E5A47),
        foregroundColor: Colors.white,
        title: const Text(
          'City Reach Configuration',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF0E5A47),
        onPressed: () => _edit(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading
          ? const AdminLoadingPanel(message: 'Loading city reach…')
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
                      const Text(
                        'Set one maximum km per city. It caps buyer Home distance and each seller’s Selling Reach bar.',
                        style: TextStyle(fontSize: 13, color: Color(0xFF6A7774)),
                      ),
                      const SizedBox(height: 16),
                      if (_configs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 24),
                          child: Text(
                            'No cities configured yet.',
                            style: TextStyle(color: Color(0xFF6A7774)),
                          ),
                        ),
                      ..._configs.map(
                        (config) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              onTap: () => _edit(existing: config),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFEAEFED)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      config.displayName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                        color: Color(0xFF101617),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      config.cityKey,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF6A7774),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Max reach: ${config.maxSellerRadiusKm} km',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

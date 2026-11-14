import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../widgets/admin_loading_panel.dart';
import 'admin_kitchen_move_detail_screen.dart';

class AdminKitchenMovesScreen extends StatefulWidget {
  const AdminKitchenMovesScreen({super.key});

  @override
  State<AdminKitchenMovesScreen> createState() => _AdminKitchenMovesScreenState();
}

class _AdminKitchenMovesScreenState extends State<AdminKitchenMovesScreen> {
  static const _filters = <_MoveFilter>[
    _MoveFilter('PENDING', 'Waiting'),
    _MoveFilter('APPROVED', 'Approved'),
    _MoveFilter('REJECTED', 'Rejected'),
  ];

  String _status = 'PENDING';
  List<Map<String, dynamic>> _moves = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final moves = await ApiService.getAdminKitchenMoves(status: _status);
      if (!mounted) return;
      setState(() {
        _moves = moves;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load kitchen moves: $error')),
      );
    }
  }

  Future<void> _open(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminKitchenMoveDetailScreen(moveId: id),
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            'The kitchen stays at the current society until you approve the move.',
            style: TextStyle(fontSize: 13, color: Color(0xFF6A7774), height: 1.35),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Wrap(
            spacing: 8,
            children: [
              for (final filter in _filters)
                ChoiceChip(
                  label: Text(filter.label),
                  selected: _status == filter.status,
                  onSelected: _loading
                      ? null
                      : (_) {
                          if (_status == filter.status) return;
                          setState(() => _status = filter.status);
                          _load();
                        },
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) {
      return const AdminLoadingPanel(message: 'Loading kitchen moves…');
    }
    if (_moves.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 80),
            Center(
              child: Text(
                'No kitchen moves in this list',
                style: TextStyle(color: Color(0xFF6A7774)),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: _moves.length,
        itemBuilder: (context, index) {
          final row = _moves[index];
          final from = row['fromSocietyName']?.toString() ?? 'Current society';
          final to = row['toSocietyName']?.toString() ?? 'New society';
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => _open(row),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row['sellerName']?.toString() ?? 'Seller',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$from → $to',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF6A7774)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MoveFilter {
  const _MoveFilter(this.status, this.label);
  final String status;
  final String label;
}

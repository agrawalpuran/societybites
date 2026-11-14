import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/session_service.dart';

class BuyerAddressList extends StatefulWidget {
  const BuyerAddressList({
    super.key,
    required this.loadAddresses,
    required this.selectAddress,
    required this.deleteAddress,
    required this.onAdd,
    this.onPlaceChanged,
    this.initialSocietyName,
    this.initialFlatNumber,
  });

  final Future<Map<String, dynamic>> Function() loadAddresses;
  final Future<Map<String, dynamic>> Function(String id) selectAddress;
  final Future<Map<String, dynamic>> Function(String id) deleteAddress;
  final VoidCallback onAdd;
  final Future<void> Function(Map<String, dynamic> place)? onPlaceChanged;
  final String? initialSocietyName;
  final String? initialFlatNumber;

  @override
  BuyerAddressListState createState() => BuyerAddressListState();
}

class BuyerAddressListState extends State<BuyerAddressList> {
  late List<Map<String, dynamic>> _addresses;
  late bool _loading;
  String? _savingId;
  String? _error;
  Future<void>? _reloadInFlight;

  @override
  void initState() {
    super.initState();
    final remembered = SessionService.rememberedBuyerAddresses;
    if (remembered != null && remembered.isNotEmpty) {
      _addresses = remembered
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      _loading = false;
    } else {
      final seeded = _placeAlreadyOnScreen();
      _addresses = seeded;
      _loading = seeded.isEmpty;
    }
    reload();
  }

  List<Map<String, dynamic>> _placeAlreadyOnScreen() {
    final society = widget.initialSocietyName?.trim() ?? '';
    if (society.isEmpty) return [];
    final flat = widget.initialFlatNumber?.trim() ?? '';
    return [
      {
        'id': 'current-place',
        'label': 'Home',
        'selected': true,
        'flatNumber': flat.isEmpty ? null : flat,
        'society': {'name': society},
      },
    ];
  }

  List<Map<String, dynamic>> _rowsFrom(Map<String, dynamic> payload) {
    final raw = payload['addresses'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<void> reload() {
    final current = _reloadInFlight;
    if (current != null) return current;
    final flight = _reload();
    _reloadInFlight = flight;
    return flight.whenComplete(() {
      if (identical(_reloadInFlight, flight)) _reloadInFlight = null;
    });
  }

  Future<void> _reload() async {
    try {
      final payload = await widget.loadAddresses();
      if (!mounted) return;
      final rows = _rowsFrom(payload);
      SessionService.rememberedBuyerAddresses = rows
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      setState(() {
        _addresses = rows;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ApiService.userFacingError(error);
      });
    }
  }

  Map<String, dynamic>? get _selected {
    for (final row in _addresses) {
      if (row['selected'] == true) return row;
    }
    return _addresses.isEmpty ? null : _addresses.first;
  }

  String _societyName(Map<String, dynamic> row) {
    final society = row['society'];
    if (society is Map && society['name'] != null) {
      return society['name'].toString();
    }
    return 'this place';
  }

  String _detail(Map<String, dynamic> row) {
    final society = _societyName(row);
    final block = row['block']?.toString().trim() ?? '';
    final flat = row['flatNumber']?.toString().trim() ?? '';
    final door = [
      if (block.isNotEmpty) block,
      if (flat.isNotEmpty) 'Flat $flat',
    ].join(' · ');
    if (door.isEmpty) return society;
    return '$society · $door';
  }

  Future<void> _select(Map<String, dynamic> row) async {
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty || id == 'current-place' || _savingId != null || row['selected'] == true) {
      return;
    }
    setState(() {
      _savingId = id;
      _error = null;
    });
    try {
      final payload = await widget.selectAddress(id);
      if (!mounted) return;
      setState(() {
        _addresses = _rowsFrom(payload);
        _savingId = null;
      });
      final place = payload['place'];
      if (place is Map && widget.onPlaceChanged != null) {
        await widget.onPlaceChanged!(Map<String, dynamic>.from(place));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _savingId = null;
        _error = ApiService.userFacingError(error);
      });
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty || _savingId != null) return;
    final label = row['label']?.toString() ?? 'this place';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this place?'),
        content: Text('$label will be removed from your saved places.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _savingId = id;
      _error = null;
    });
    try {
      final payload = await widget.deleteAddress(id);
      if (!mounted) return;
      setState(() {
        _addresses = _rowsFrom(payload);
        _savingId = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _savingId = null;
        _error = ApiService.userFacingError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final hint = selected == null
        ? 'Add a place to see food near you.'
        : 'Showing food near ${_societyName(selected)}.';

    return Column(
      key: const Key('buyer-addresses'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Addresses',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF101617),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          hint,
          key: const Key('buyer-address-hint'),
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF6A7774),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF0E5A47),
                ),
              ),
            ),
          )
        else
          for (final row in _addresses)
            _AddressRow(
              row: row,
              detail: _detail(row),
              busy: _savingId == row['id']?.toString(),
              onSelect: () => _select(row),
              onDelete: row['selected'] == true ? null : () => _delete(row),
            ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            key: const Key('buyer-address-error'),
            style: const TextStyle(
              color: Color(0xFFD94F4F),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 4),
        TextButton.icon(
          key: const Key('buyer-address-add'),
          onPressed: _savingId == null ? widget.onAdd : null,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add address'),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF0E5A47),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({
    required this.row,
    required this.detail,
    required this.busy,
    required this.onSelect,
    required this.onDelete,
  });

  final Map<String, dynamic> row;
  final String detail;
  final bool busy;
  final VoidCallback onSelect;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final selected = row['selected'] == true;
    final label = row['label']?.toString() ?? 'Place';
    final id = row['id']?.toString() ?? label;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0xFFE8F5EE) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: Key('buyer-address-$id'),
          borderRadius: BorderRadius.circular(16),
          onTap: busy ? null : onSelect,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? const Color(0xFF0E5A47)
                    : const Color(0xFFEAEFED),
              ),
            ),
            child: Row(
              children: [
                Semantics(
                  selected: selected,
                  label: label,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF0E5A47)
                            : const Color(0xFF8A9491),
                        width: 2,
                      ),
                    ),
                    child: selected
                        ? Center(
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF0E5A47),
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF101617),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6A7774),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF0E5A47),
                    ),
                  )
                else if (onDelete != null)
                  IconButton(
                    key: Key('buyer-address-remove-$id'),
                    tooltip: 'Remove $label',
                    onPressed: onDelete,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: const Color(0xFF8A9491),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

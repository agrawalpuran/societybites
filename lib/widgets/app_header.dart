import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/session_service.dart';

class AppHeader extends StatefulWidget {
  const AppHeader({
    super.key,
    this.leading,
    this.padding = const EdgeInsets.fromLTRB(20, 14, 20, 0),
  });

  final Widget? leading;
  final EdgeInsets padding;

  @override
  State<AppHeader> createState() => _AppHeaderState();
}

class _AppHeaderState extends State<AppHeader> {
  String? _name;
  String? _flatNumber;
  String? _societyName;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    var name = await SessionService.getUserName();
    var flatNumber = await SessionService.getFlatNumber();
    var societyName = await SessionService.getSocietyName();

    final userId = await SessionService.getUserId();
    if (userId != null && (name == null || flatNumber == null)) {
      try {
        final profile = await ApiService.getMe();
        await SessionService.cacheProfileFromApi(profile);
        name = await SessionService.getUserName();
        flatNumber = await SessionService.getFlatNumber();
        societyName = await SessionService.getSocietyName();
      } catch (_) {}
    }

    if (!mounted) return;

    setState(() {
      _name = name;
      _flatNumber = flatNumber;
      _societyName = societyName;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.leading != null) widget.leading!,
          if (widget.leading == null) ...const [
            Text(
              'SocietyBites',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: Color(0xFF0A4638),
              ),
            ),
            SizedBox(width: 4),
            Icon(
              Icons.restaurant_menu_rounded,
              color: Color(0xFF0E5A47),
              size: 18,
            ),
          ],
          const Spacer(),
          _UserInfoColumn(
            name: _name,
            flatNumber: _flatNumber,
            societyName: _societyName,
          ),
        ],
      ),
    );
  }
}

class _UserInfoColumn extends StatelessWidget {
  const _UserInfoColumn({
    required this.name,
    required this.flatNumber,
    required this.societyName,
  });

  final String? name;
  final String? flatNumber;
  final String? societyName;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      if (name != null && name!.isNotEmpty) name!,
      if (flatNumber != null && flatNumber!.isNotEmpty) 'Flat $flatNumber',
      if (societyName != null && societyName!.isNotEmpty) societyName!,
    ];

    if (lines.isEmpty) {
      return const Icon(
        Icons.person_rounded,
        color: Color(0xFF0E5A47),
        size: 22,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: lines
          .map(
            (line) => Text(
              line,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11,
                height: 1.35,
                color: Color(0xFF4A5A57),
                fontWeight: FontWeight.w600,
              ),
            ),
          )
          .toList(),
    );
  }
}

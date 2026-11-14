import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../web/web_page_frame.dart';

class AdminKitchenMoveDetailScreen extends StatefulWidget {
  const AdminKitchenMoveDetailScreen({super.key, required this.moveId});

  final String moveId;

  @override
  State<AdminKitchenMoveDetailScreen> createState() =>
      _AdminKitchenMoveDetailScreenState();
}

class _AdminKitchenMoveDetailScreenState extends State<AdminKitchenMoveDetailScreen> {
  Map<String, dynamic>? _move;
  bool _loading = true;
  bool _acting = false;
  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final move = await ApiService.getAdminKitchenMove(widget.moveId);
      if (!mounted) return;
      setState(() {
        _move = move;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ApiService.userFacingError(error);
      });
    }
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() action) async {
    setState(() => _acting = true);
    try {
      final move = await action();
      if (!mounted) return;
      setState(() {
        _move = move;
        _acting = false;
        _changed = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _acting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.userFacingError(error))),
      );
    }
  }

  Future<void> _rejectMove() async {
    final reason = await _askReason('Reject this move?');
    if (reason == null || !mounted) return;
    await _run(() => ApiService.rejectAdminKitchenMove(widget.moveId, reason: reason));
  }

  Future<void> _rejectFssai() async {
    final reason = await _askReason('Reject this FSSAI?');
    if (reason == null || reason.trim().isEmpty || !mounted) return;
    await _run(
      () => ApiService.rejectAdminKitchenMoveFssai(widget.moveId, reason: reason.trim()),
    );
  }

  Future<String?> _askReason(String title) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Note for the seller'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, _changed);
      },
      child: panelOnWeb(
        context,
        Scaffold(
          backgroundColor: const Color(0xFFF8FAF9),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0E5A47),
            foregroundColor: Colors.white,
            title: const Text(
              'Kitchen move',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context, _changed),
            ),
          ),
          body: _body(),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_move == null) {
      return Center(child: Text(_error ?? 'Kitchen move not found'));
    }
    final move = _move!;
    final pending = move['status']?.toString() == 'PENDING';
    final proof = move['addressProofStatus']?.toString() ?? 'PENDING';
    final fssai = move['fssaiStatus']?.toString() ?? 'NOT_SUBMITTED';
    final attached = move['fssaiAttached'] == true;
    final required = move['fssaiSellingRequirement'] == true;
    final url = move['addressProofUrl']?.toString();
    final flat = [
      move['toBlock']?.toString(),
      move['toFlatNumber']?.toString(),
    ].where((part) => part != null && part.isNotEmpty).join(' ');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          move['sellerName']?.toString() ?? 'Seller',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text('Phone: ${move['phone'] ?? '—'}'),
        const SizedBox(height: 12),
        Text('From: ${move['fromSocietyName'] ?? '—'}'),
        Text(
          'To: ${move['toSocietyName'] ?? '—'}${flat.isEmpty ? '' : ' · $flat'}',
        ),
        const SizedBox(height: 8),
        Text(
          required
              ? 'FSSAI is required. Approve the licence for the new society, then approve the move. The address changes only then.'
              : 'FSSAI is not required yet. You can approve the move without a new licence. The address still changes only when you approve.',
          style: const TextStyle(color: Color(0xFF6A7774), height: 1.35),
        ),
        const SizedBox(height: 16),
        const Text('Address photo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 4),
        Text(
          'Status: $proof. A weak photo does not block FSSAI review.',
          style: const TextStyle(color: Color(0xFF6A7774), fontSize: 13),
        ),
        const SizedBox(height: 8),
        if (url == null || url.isEmpty)
          const Text('No photo uploaded')
        else
          _photo(url),
        if (pending) ...[
          const SizedBox(height: 12),
          _button(
            key: const Key('kitchen-move-proof-ok'),
            label: 'Photo looks fine',
            filled: true,
            enabled: proof != 'OK',
            onPressed: () => _run(
              () => ApiService.reviewAdminKitchenMoveProof(widget.moveId, status: 'OK'),
            ),
          ),
          const SizedBox(height: 8),
          _button(
            key: const Key('kitchen-move-proof-follow-up'),
            label: 'Photo needs follow-up',
            filled: false,
            enabled: proof != 'FOLLOW_UP',
            onPressed: () => _run(
              () => ApiService.reviewAdminKitchenMoveProof(
                widget.moveId,
                status: 'FOLLOW_UP',
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        const Text('FSSAI for the new society', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 4),
        Text(
          attached
              ? '${move['fssaiRegisteredName'] ?? 'Licence'} · ${move['fssaiRegistrationNumber'] ?? ''} · $fssai'
              : 'No new licence was attached.',
          style: const TextStyle(color: Color(0xFF6A7774), height: 1.35),
        ),
        if (move['fssaiRejectionReason'] != null) ...[
          const SizedBox(height: 4),
          Text(move['fssaiRejectionReason'].toString()),
        ],
        if (attached) ...[
          const SizedBox(height: 8),
          if ((move['fssaiDocumentUrl']?.toString() ?? '').isEmpty)
            const Text('Could not load the licence photo')
          else
            _photo(move['fssaiDocumentUrl'].toString()),
        ],
        if (pending && attached && (fssai == 'NOT_SUBMITTED' || fssai == 'REJECTED')) ...[
          const SizedBox(height: 8),
          _button(
            key: const Key('kitchen-move-fssai-review'),
            label: 'Needs FSSAI review',
            filled: true,
            enabled: true,
            onPressed: () => _run(
              () => ApiService.sendAdminKitchenMoveFssaiToReview(widget.moveId),
            ),
          ),
        ],
        if (pending && fssai == 'UNDER_REVIEW') ...[
          const SizedBox(height: 8),
          _button(
            key: const Key('kitchen-move-fssai-approve'),
            label: 'Approve FSSAI',
            filled: true,
            enabled: true,
            onPressed: () => _run(() => ApiService.approveAdminKitchenMoveFssai(widget.moveId)),
          ),
          const SizedBox(height: 8),
          _button(
            label: 'Reject FSSAI',
            filled: false,
            enabled: true,
            onPressed: _rejectFssai,
          ),
        ],
        if (pending) ...[
          const SizedBox(height: 24),
          _button(
            key: const Key('kitchen-move-approve'),
            label: 'Approve move',
            filled: true,
            enabled: move['canApproveMove'] == true,
            onPressed: () => _run(() => ApiService.approveAdminKitchenMove(widget.moveId)),
          ),
          if (move['approveBlockReason'] != null) ...[
            const SizedBox(height: 8),
            Text(
              move['approveBlockReason'].toString(),
              style: const TextStyle(color: Color(0xFF9A3412), fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 8),
          _button(
            label: 'Reject move',
            filled: false,
            enabled: true,
            onPressed: _rejectMove,
          ),
        ],
        if (!pending) ...[
          const SizedBox(height: 16),
          Text('This move is ${move['status']}.'),
        ],
      ],
    );
  }

  Widget _photo(String url) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _openPhoto(url),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            url,
            height: 220,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) =>
                const Text('Could not load the photo'),
          ),
        ),
      ),
    );
  }

  void _openPhoto(String url) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) => const Text(
                    'Could not load the photo',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _button({
    Key? key,
    required String label,
    required bool filled,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    final press = _acting || !enabled ? null : onPressed;
    if (filled) {
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(
          key: key,
          onPressed: press,
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0E5A47)),
          child: Text(label),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(key: key, onPressed: press, child: Text(label)),
    );
  }
}

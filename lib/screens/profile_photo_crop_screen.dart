import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Circular crop: pan and zoom, then capture the visible circle.
class ProfilePhotoCropScreen extends StatefulWidget {
  const ProfilePhotoCropScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<ProfilePhotoCropScreen> createState() => _ProfilePhotoCropScreenState();
}

class _ProfilePhotoCropScreenState extends State<ProfilePhotoCropScreen> {
  final TransformationController _transform = TransformationController();
  final GlobalKey _cropKey = GlobalKey();
  bool _saving = false;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _usePhoto() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final boundary =
          _cropKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('Could not crop this photo.');
      }
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) {
        throw StateError('Could not crop this photo.');
      }
      if (!mounted) return;
      Navigator.pop(context, bytes.buffer.asUint8List());
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not crop this photo. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const cropSize = 280.0;
    return Scaffold(
      backgroundColor: const Color(0xFF101617),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101617),
        foregroundColor: Colors.white,
        title: const Text('Adjust photo'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: SizedBox(
                width: cropSize,
                height: cropSize,
                child: ClipOval(
                  child: RepaintBoundary(
                    key: _cropKey,
                    child: InteractiveViewer(
                      transformationController: _transform,
                      minScale: 1,
                      maxScale: 4,
                      constrained: false,
                      child: Image.memory(
                        widget.imageBytes,
                        width: cropSize,
                        height: cropSize,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Pinch to zoom and drag so your face sits in the circle.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFC5CDC9), fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _saving ? null : _usePhoto,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0E5A47),
                  ),
                  child: Text(_saving ? 'Preparing…' : 'Use Photo'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

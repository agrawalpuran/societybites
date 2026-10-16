import 'package:flutter/material.dart';

import '../../models/festival_banner_content.dart';
import '../../preview/festival_banner_preview.dart';
import '../../widgets/festival_announcement_banner.dart';
import '../../widgets/festival_banner_placement_picker.dart';
import '../../widgets/festival_home_hero_section.dart';

/// UI mock for festival banner admin — pushes content to Home preview (debug).
class AdminFestivalBannersMockScreen extends StatefulWidget {
  const AdminFestivalBannersMockScreen({super.key});

  @override
  State<AdminFestivalBannersMockScreen> createState() =>
      _AdminFestivalBannersMockScreenState();
}

class _AdminFestivalBannersMockScreenState
    extends State<AdminFestivalBannersMockScreen> {
  final _nameController = TextEditingController();
  final _titleController = TextEditingController();
  final _subtitleController = TextEditingController();
  bool _active = true;
  bool _usePreviewImageFile = false;
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now().add(const Duration(days: 9));

  @override
  void initState() {
    super.initState();
    final c = FestivalBannerPreview.instance.content;
    _titleController.text = c.title ?? '';
    _subtitleController.text = c.subtitle ?? '';
    _usePreviewImageFile = c.imageAssetPath != null;
    _active =
        FestivalBannerPreview.instance.previewState ==
        FestivalBannerPreviewState.active;
    FestivalBannerPreview.instance.addListener(_onPreviewChanged);
  }

  void _onPreviewChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    FestivalBannerPreview.instance.removeListener(_onPreviewChanged);

    _nameController.dispose();
    _titleController.dispose();
    _subtitleController.dispose();
    super.dispose();
  }

  FestivalBannerContent _buildContent() {
    return FestivalBannerContent(
      title: _titleController.text.trim().isEmpty
          ? null
          : _titleController.text.trim(),
      subtitle: _subtitleController.text.trim().isEmpty
          ? null
          : _subtitleController.text.trim(),
      imageAssetPath: _usePreviewImageFile
          ? FestivalBannerContent.previewAssetPath
          : null,
    );
  }

  void _applyToHomePreview() {
    final preview = FestivalBannerPreview.instance;
    preview.setContent(_buildContent());
    preview.setPreviewState(
      _active
          ? FestivalBannerPreviewState.active
          : FestivalBannerPreviewState.hidden,
    );
    // Placement is already on the shared preview instance (picker updates live).
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Applied to Home preview (this device, debug only)'),
      ),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
        if (_end.isBefore(_start)) _end = _start;
      } else {
        _end = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final previewContent = _buildContent();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        title: const Text('Festival banners'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF101617),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Set title, subtitle, and image here. The app only shows a neutral '
            'placeholder until you apply content. Save applies to Home preview '
            'on this device (production will use the server).',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF6A7774),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Internal name',
              hintText: 'e.g. Navratri 2026 — home hero',
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Use banner image file'),
            subtitle: Text(
              'Place PNG or JPG as assets/images/preview/festival_banner_preview.png '
              '(or .jpg). Hot restart after adding the file.',
              style: const TextStyle(fontSize: 12),
            ),
            value: _usePreviewImageFile,
            onChanged: (v) => setState(() => _usePreviewImageFile = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Display title (optional)',
              hintText: 'Leave empty if text is only in the image',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _subtitleController,
            decoration: const InputDecoration(
              labelText: 'Display subtitle (optional)',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDate(isStart: true),
                  child: Text('Start: ${_formatDate(_start)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDate(isStart: false),
                  child: Text('End: ${_formatDate(_end)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Active on Home preview'),
            subtitle: const Text('Only one active banner in MVP'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          const SizedBox(height: 16),
          const Text(
            'Home placement',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101617),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap A or B — applies to Home on this device (narrow/mobile layout). '
            'Use Save to keep content in sync.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF6A7774),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          const FestivalBannerPlacementPicker(),
          if (!FestivalBannerPreview.instance.showDevControls)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                onPressed: () {
                  FestivalBannerPreview.instance.showDevControls = true;
                  FestivalBannerPreview.instance.notifyListeners();
                },
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Show yellow preview bar on Home'),
              ),
            ),
          const SizedBox(height: 20),
          Text(
            FestivalBannerPreview.instance.placement ==
                    FestivalBannerPlacement.belowSearch
                ? 'Preview — Option A (hero)'
                : 'Preview — Option B (card)',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101617),
            ),
          ),
          const SizedBox(height: 8),
          if (_active)
            FestivalBannerPreview.instance.placement ==
                    FestivalBannerPlacement.belowSearch
                ? FestivalHomeHeroSection(
                    content: previewContent,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        if (previewContent.hasDisplayText)
                          FestivalHeroHeadline(content: previewContent),
                        const SizedBox(height: 48),
                      ],
                    ),
                  )
                : FestivalAnnouncementBanner(content: previewContent)
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Banner hidden (inactive)',
                  style: TextStyle(color: Color(0xFF8A9491)),
                ),
              ),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _applyToHomePreview,
                  child: const Text('Save & apply to Home'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              setState(() => _active = false);
              _applyToHomePreview();
            },
            child: const Text('Deactivate on Home'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';
}

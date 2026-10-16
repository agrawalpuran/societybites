import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/festival_banner_content.dart';
import '../../preview/festival_banner_preview.dart';
import '../../services/api_service.dart';
import '../../widgets/festival_announcement_banner.dart';
import '../../widgets/festival_banner_placement_picker.dart';
import '../../widgets/festival_home_hero_section.dart';

/// Admin editor for the production Home festival banner.
class AdminFestivalBannersScreen extends StatefulWidget {
  const AdminFestivalBannersScreen({super.key});

  @override
  State<AdminFestivalBannersScreen> createState() =>
      _AdminFestivalBannersScreenState();
}

class _AdminFestivalBannersScreenState extends State<AdminFestivalBannersScreen> {
  final _nameController = TextEditingController();
  final _titleController = TextEditingController();
  final _subtitleController = TextEditingController();
  final _imageUrlController = TextEditingController();

  String? _bannerId;
  bool _active = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now().add(const Duration(days: 9));

  @override
  void initState() {
    super.initState();
    FestivalBannerPreview.instance.addListener(_onPreviewChanged);
    _load();
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
    _imageUrlController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final banners = await ApiService.getAdminFestivalBanners();
      if (!mounted) return;
      Map<String, dynamic>? selected;
      for (final row in banners) {
        if (row['status']?.toString() == 'ACTIVE') {
          selected = row;
          break;
        }
      }
      selected ??= banners.isNotEmpty ? banners.first : null;
      _applyBannerToForm(selected);
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ApiService.userFacingError(e);
      });
    }
  }

  void _applyBannerToForm(Map<String, dynamic>? banner) {
    _bannerId = banner?['id']?.toString();
    _nameController.text = banner?['name']?.toString() ?? '';
    _titleController.text = banner?['title']?.toString() ?? '';
    _subtitleController.text = banner?['subtitle']?.toString() ?? '';
    _imageUrlController.text = banner?['imageUrl']?.toString() ?? '';
    _active = banner?['status']?.toString() == 'ACTIVE';
    final startsAt = DateTime.tryParse(banner?['startsAt']?.toString() ?? '');
    final endsAt = DateTime.tryParse(banner?['endsAt']?.toString() ?? '');
    _start = startsAt ?? DateTime.now();
    _end = endsAt ?? DateTime.now().add(const Duration(days: 9));
    if (banner != null) {
      FestivalBannerPreview.instance.setPlacement(
        FestivalBannerPreview.placementFromApi(banner['placement']?.toString()),
        markLocal: false,
      );
    }
  }

  FestivalBannerContent _previewContent() {
    final url = _imageUrlController.text.trim();
    return FestivalBannerContent(
      title: _titleController.text.trim().isEmpty
          ? null
          : _titleController.text.trim(),
      subtitle: _subtitleController.text.trim().isEmpty
          ? null
          : _subtitleController.text.trim(),
      imageUrl: url.isEmpty ? null : url,
    );
  }

  Map<String, dynamic> _bodyFromForm() {
    final name = _nameController.text.trim().isEmpty
        ? 'Home festival banner'
        : _nameController.text.trim();
    final title = _titleController.text.trim();
    final subtitle = _subtitleController.text.trim();
    final imageUrl = _imageUrlController.text.trim();
    return {
      'name': name,
      'title': title.isEmpty ? null : title,
      'subtitle': subtitle.isEmpty ? null : subtitle,
      'imageUrl': imageUrl.isEmpty ? null : imageUrl,
      'placement': FestivalBannerPreview.placementToApi(
        FestivalBannerPreview.instance.placement,
      ),
      'startsAt': DateTime(_start.year, _start.month, _start.day)
          .toUtc()
          .toIso8601String(),
      'endsAt': DateTime(_end.year, _end.month, _end.day, 23, 59, 59)
          .toUtc()
          .toIso8601String(),
    };
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
        if (_end.isBefore(_start)) _start = _end;
      }
    });
  }

  Future<void> _uploadImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2000,
        imageQuality: 88,
      );
      if (picked == null) return;
      setState(() => _saving = true);
      final bytes = await picked.readAsBytes();
      final mime = picked.mimeType ?? 'image/jpeg';
      final url = await ApiService.uploadListingImage(
        bytes: bytes,
        mimeType: mime,
        purpose: 'festival-banner',
      );
      if (!mounted) return;
      setState(() {
        _imageUrlController.text = url;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.userFacingError(e))),
      );
    }
  }

  Future<void> _save({required bool activate}) async {
    setState(() => _saving = true);
    try {
      final body = _bodyFromForm();
      Map<String, dynamic> banner;
      if (_bannerId == null || _bannerId!.isEmpty) {
        banner = await ApiService.createAdminFestivalBanner(body);
        _bannerId = banner['id']?.toString();
      } else {
        banner = await ApiService.updateAdminFestivalBanner(_bannerId!, body);
      }
      if (activate) {
        banner = await ApiService.activateAdminFestivalBanner(banner['id'].toString());
      } else if (_bannerId != null) {
        banner = await ApiService.deactivateAdminFestivalBanner(_bannerId!);
      }
      if (!mounted) return;
      _applyBannerToForm(banner);
      FestivalBannerPreview.instance.localOverride = false;
      FestivalBannerPreview.instance.applyServerBanner(
        activate ? banner : null,
      );
      setState(() {
        _active = activate;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            activate
                ? 'Banner saved and shown on Home'
                : 'Banner saved and hidden on Home',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.userFacingError(e))),
      );
    }
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';

  @override
  Widget build(BuildContext context) {
    final previewContent = _previewContent();
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        title: const Text('Festival banners'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF101617),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0E5A47)))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        TextButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    20,
                    20,
                    20 + MediaQuery.paddingOf(context).bottom,
                  ),
                  children: [
                    const Text(
                      'This banner shows on Home for all users while it is active '
                      'and within the start/end dates.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6A7774),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active on Home'),
                      subtitle: Text(
                        _active ? 'Visible to buyers now' : 'Hidden on Home',
                      ),
                      value: _active,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _active = v),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () => _save(activate: false),
                        icon: const Icon(Icons.visibility_off_outlined, size: 18),
                        label: const Text('Deactivate on Home'),
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
                    const SizedBox(height: 12),
                    TextField(
                      controller: _imageUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Image URL (https)',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _uploadImage,
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('Upload banner image'),
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
                    const SizedBox(height: 16),
                    const Text(
                      'Home placement',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF101617),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const FestivalBannerPlacementPicker(),
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
                    if (_active || previewContent.hasImage || previewContent.hasDisplayText)
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
                            'Add title, subtitle, or an image to preview',
                            style: TextStyle(color: Color(0xFF8A9491)),
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: _saving
                            ? null
                            : () => _save(activate: _active),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0E5A47),
                        ),
                        child: Text(
                          _saving
                              ? 'Saving…'
                              : (_active
                                  ? 'Save & show on Home'
                                  : 'Save (keep hidden)'),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

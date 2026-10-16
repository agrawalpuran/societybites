import 'package:flutter/material.dart';

import '../preview/festival_banner_preview.dart';
import 'festival_banner_placement_picker.dart';

/// Debug-only row to compare banner placement and visibility states.
class FestivalBannerPreviewControls extends StatelessWidget {
  const FestivalBannerPreviewControls({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FestivalBannerPreview.instance,
      builder: (context, _) {
        final preview = FestivalBannerPreview.instance;
        return Material(
          color: const Color(0xFFFFF8E8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.celebration_outlined, size: 18),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Festival banner preview (local only)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF3A4644),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Hide controls',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: preview.toggleDevControls,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Visibility',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6A7774),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _StateChip(
                      label: 'On',
                      selected:
                          preview.previewState ==
                          FestivalBannerPreviewState.active,
                      onTap: () => preview.setPreviewState(
                        FestivalBannerPreviewState.active,
                      ),
                    ),
                    _StateChip(
                      label: 'Off',
                      selected:
                          preview.previewState ==
                          FestivalBannerPreviewState.hidden,
                      onTap: () => preview.setPreviewState(
                        FestivalBannerPreviewState.hidden,
                      ),
                    ),
                    _StateChip(
                      label: 'Loading',
                      selected:
                          preview.previewState ==
                          FestivalBannerPreviewState.loading,
                      onTap: () => preview.setPreviewState(
                        FestivalBannerPreviewState.loading,
                      ),
                    ),
                    _StateChip(
                      label: 'Error',
                      selected:
                          preview.previewState ==
                          FestivalBannerPreviewState.error,
                      onTap: () => preview.setPreviewState(
                        FestivalBannerPreviewState.error,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Home placement',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6A7774),
                  ),
                ),
                const SizedBox(height: 6),
                const FestivalBannerPlacementPicker(),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF0E5A47) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? const Color(0xFF0E5A47)
                  : const Color(0xFFD0D8D4),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : const Color(0xFF3A4644),
            ),
          ),
        ),
      ),
    );
  }
}

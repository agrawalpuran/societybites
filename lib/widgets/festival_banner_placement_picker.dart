import 'package:flutter/material.dart';

import '../preview/festival_banner_preview.dart';

/// Chooses Option A (hero) vs Option B (card) for the Home festival banner.
class FestivalBannerPlacementPicker extends StatelessWidget {
  const FestivalBannerPlacementPicker({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FestivalBannerPreview.instance,
      builder: (context, _) {
        final placement = FestivalBannerPreview.instance.placement;
        return SegmentedButton<FestivalBannerPlacement>(
          segments: const [
            ButtonSegment<FestivalBannerPlacement>(
              value: FestivalBannerPlacement.belowSearch,
              label: Text('A · Hero'),
              icon: Icon(Icons.wallpaper_outlined, size: 18),
            ),
            ButtonSegment<FestivalBannerPlacement>(
              value: FestivalBannerPlacement.belowCategories,
              label: Text('B · Card'),
              icon: Icon(Icons.view_agenda_outlined, size: 18),
            ),
          ],
          selected: {placement},
          showSelectedIcon: false,
          onSelectionChanged: (selected) {
            if (selected.isEmpty) return;
            FestivalBannerPreview.instance.setPlacement(selected.first);
          },
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import 'web_breakpoints.dart';

/// Centers a form or detail page in a card on wide web.
/// Android, iOS, and narrow Chrome keep [page] full screen.
Widget panelOnWeb(
  BuildContext context,
  Widget page, {
  double maxWidth = 760,
}) {
  if (!useWebMarketplaceLayout(context)) return page;
  return ColoredBox(
    color: webPageBackground,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: webLine),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x140E5A47),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: page,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Centers a page on wide web. On Android, iOS, and narrow Chrome this
/// returns [page] unchanged.
Widget centerOnWeb(
  BuildContext context,
  Widget page, {
  double maxWidth = webFrameMaxWidth,
}) {
  if (!useWebMarketplaceLayout(context)) return page;
  return ColoredBox(
    color: webPageBackground,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: page,
      ),
    ),
  );
}

/// Side-by-side cards inside an existing scroll view. One column under 980px.
class WebCardRows extends StatelessWidget {
  const WebCardRows({
    super.key,
    required this.children,
    this.gap = 16,
    this.minWidthForTwoColumns = 980,
  });

  final List<Widget> children;
  final double gap;
  final double minWidthForTwoColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth >= minWidthForTwoColumns ? 2 : 1;
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          );
        }
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += 2) {
          final left = children[i];
          final right = i + 1 < children.length
              ? children[i + 1]
              : const SizedBox.shrink();
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: left),
                SizedBox(width: gap),
                Expanded(child: right),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}

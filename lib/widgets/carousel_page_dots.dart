import 'package:flutter/material.dart';

/// Which dots to draw. More than three pages stays a three-dot slider:
/// the lit dot sits left, middle, or right as the row scrolls.
({int count, int active}) carouselDotWindow(int pageCount, int activePage) {
  final pages = pageCount < 1 ? 1 : pageCount;
  final active = activePage.clamp(0, pages - 1);
  if (pages <= 3) return (count: pages, active: active);
  if (active <= 0) return (count: 3, active: 0);
  if (active >= pages - 1) return (count: 3, active: 2);
  return (count: 3, active: 1);
}

({int active, int count}) carouselPageFromScroll({
  required double offset,
  required double maxScroll,
  required double viewport,
}) {
  if (maxScroll <= 1 || viewport <= 0) {
    return (active: 0, count: 1);
  }
  final pageCount = (maxScroll / viewport).ceil() + 1;
  final active = ((offset.clamp(0.0, maxScroll) / maxScroll) * (pageCount - 1))
      .round()
      .clamp(0, pageCount - 1);
  return (active: active, count: pageCount);
}

class CarouselPageDots extends StatelessWidget {
  const CarouselPageDots({
    super.key,
    required this.activePage,
    required this.pageCount,
  });

  final int activePage;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    final window = carouselDotWindow(pageCount, activePage);
    if (window.count <= 1) return const SizedBox.shrink();
    return Semantics(
      label: 'Page ${activePage + 1} of $pageCount',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(window.count, (i) {
          final selected = i == window.active;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: selected ? 16 : 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF0E5A47)
                  : const Color(0xFFD4DBD8),
              borderRadius: BorderRadius.circular(6),
            ),
          );
        }),
      ),
    );
  }
}

/// Horizontal row with a dot indicator when more items sit off-screen.
class PagedHorizontalList extends StatefulWidget {
  const PagedHorizontalList({
    super.key,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.separatorBuilder,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder? separatorBuilder;
  final EdgeInsets padding;

  @override
  State<PagedHorizontalList> createState() => _PagedHorizontalListState();
}

class _PagedHorizontalListState extends State<PagedHorizontalList> {
  final ScrollController _controller = ScrollController();
  final ValueNotifier<({int active, int count})> _page = ValueNotifier(
    (active: 0, count: 1),
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(covariant PagedHorizontalList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_sync);
    _controller.dispose();
    _page.dispose();
    super.dispose();
  }

  void _sync() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final next = carouselPageFromScroll(
      offset: _controller.offset,
      maxScroll: position.maxScrollExtent,
      viewport: position.viewportDimension,
    );
    if (_page.value != next) _page.value = next;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: widget.height,
          child: ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            padding: widget.padding,
            itemCount: widget.itemCount,
            separatorBuilder:
                widget.separatorBuilder ?? (_, _) => const SizedBox(width: 14),
            itemBuilder: widget.itemBuilder,
          ),
        ),
        ValueListenableBuilder<({int active, int count})>(
          valueListenable: _page,
          builder: (context, page, _) {
            if (page.count <= 1) return const SizedBox(height: 4);
            return Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 2),
              child: CarouselPageDots(
                activePage: page.active,
                pageCount: page.count,
              ),
            );
          },
        ),
      ],
    );
  }
}

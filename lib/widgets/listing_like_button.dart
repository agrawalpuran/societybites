import 'package:flutter/material.dart';

import '../models/data.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';

/// Heart and count. Buyers never see who liked the dish.
class ListingLikeButton extends StatefulWidget {
  const ListingLikeButton({
    super.key,
    required this.food,
    this.onPhoto = false,
    this.iconColor,
    this.countColor,
  });

  final FoodItem food;
  final bool onPhoto;
  final Color? iconColor;
  final Color? countColor;

  @override
  State<ListingLikeButton> createState() => _ListingLikeButtonState();
}

class _ListingLikeButtonState extends State<ListingLikeButton> {
  late int _count;
  late bool _liked;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _count = widget.food.likeCount;
    _liked = widget.food.likedByMe;
  }

  @override
  void didUpdateWidget(ListingLikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.food.id != widget.food.id ||
        oldWidget.food.likeCount != widget.food.likeCount ||
        oldWidget.food.likedByMe != widget.food.likedByMe) {
      _count = widget.food.likeCount;
      _liked = widget.food.likedByMe;
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final userId = await SessionService.getUserId();
    if (!mounted) return;
    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to like this dish')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ApiService.toggleListingLike(widget.food.id);
      if (!mounted) return;
      setState(() {
        _liked = result.liked;
        _count = result.likeCount;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update like: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded;
    final count = _count > 0 ? '$_count' : null;
    final heartColor = widget.iconColor ?? const Color(0xFF0E5A47);
    final numberColor = widget.countColor ?? const Color(0xFF6A7774);
    if (widget.onPhoto) {
      return Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: heartColor),
                if (count != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    count,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF101617),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return InkWell(
      onTap: _toggle,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: heartColor),
            if (count != null) ...[
              const SizedBox(width: 3),
              Text(
                count,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: numberColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

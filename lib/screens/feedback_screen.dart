import 'package:flutter/material.dart';
import '../widgets/app_header.dart';
import '../models/data.dart';
import '../services/api_service.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({
    super.key,
    required this.food,
    required this.orderId,
  });

  final FoodItem food;
  final String orderId;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  int _starRating = 4;
  final Set<String> _selectedTags = {'Fresh'};
  final TextEditingController _noteController = TextEditingController();
  bool _wouldOrderAgain = true;
  bool _isSubmitting = false;

  static const _allTags = ['Tasty', 'Fresh', 'Value for money', 'On time'];

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      await ApiService.submitReview(
        orderId: widget.orderId,
        listingId: widget.food.id,
        rating: _starRating,
        comment: _noteController.text.trim(),
        tags: _selectedTags.toList(),
        wouldOrderAgain: _wouldOrderAgain,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Thank you for your feedback!'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: const Color(0xFF0E5A47),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not submit feedback: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    _buildFoodContext(),
                    const SizedBox(height: 28),
                    _buildStarRating(),
                    const SizedBox(height: 28),
                    _buildTagSection(),
                    const SizedBox(height: 24),
                    _buildNoteInput(),
                    const SizedBox(height: 24),
                    _buildReorderQuestion(),
                    const SizedBox(height: 28),
                    _buildSubmitButton(),
                    const SizedBox(height: 12),
                    const Text(
                      'Your feedback helps the seller grow and earns\nyou 15 Community Points',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8A9491),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return AppHeader(
      padding: const EdgeInsets.fromLTRB(4, 10, 20, 0),
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        color: const Color(0xFF3A4644),
      ),
    );
  }

  Widget _buildFoodContext() {
    return Column(
      children: [
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            color: widget.food.bgColor,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Icon(widget.food.icon,
                    size: 48, color: const Color(0xFF6A7774).withAlpha(150)),
              ),
              Positioned(
                bottom: -6,
                right: -6,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE85D5D),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.favorite_rounded,
                      size: 14, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'How was your meal?',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Color(0xFF101617),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your neighbor ${widget.food.sellerName} is waiting to hear about\n'
          'your experience with the ${widget.food.name}.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF6A7774),
            height: 1.45,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildStarRating() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Column(
        children: [
          const Text(
            'OVERALL QUALITY',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0E5A47),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              return GestureDetector(
                onTap: () => setState(() => _starRating = i + 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.star_rounded,
                    size: 44,
                    color: i < _starRating
                        ? Colors.amber.shade600
                        : const Color(0xFFD4DBD8),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildTagSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.auto_awesome_rounded,
                  size: 18, color: Color(0xFF0E5A47)),
              SizedBox(width: 8),
              Text(
                'What stood out?',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF101617),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _allTags.map((tag) {
              final selected = _selectedTags.contains(tag);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (selected) {
                      _selectedTags.remove(tag);
                    } else {
                      _selectedTags.add(tag);
                    }
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF0E5A47)
                        : const Color(0xFFF5F7F6),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF0E5A47)
                          : const Color(0xFFE0E5E3),
                    ),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? Colors.white
                          : const Color(0xFF3A4644),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteInput() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.edit_note_rounded, size: 20, color: Color(0xFF3A4644)),
              SizedBox(width: 8),
              Text(
                'Share a note with your neighbor',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF101617),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            maxLines: 4,
            style: const TextStyle(
              fontSize: 15,
              color: Color(0xFF3A4644),
            ),
            decoration: InputDecoration(
              hintText:
                  'Tell ${widget.food.sellerName} what you loved about the cooking...',
              hintStyle: const TextStyle(
                color: Color(0xFFADB5B2),
                fontSize: 14,
              ),
              filled: true,
              fillColor: const Color(0xFFF8FAF9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE6EBE9)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE6EBE9)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF0E5A47)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReorderQuestion() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Would you\norder again?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF101617),
                    height: 1.2,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Help others in the\ncommunity decide.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8A9491),
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          _TogglePill(
            label: 'Yes',
            isActive: _wouldOrderAgain,
            onTap: () => setState(() => _wouldOrderAgain = true),
          ),
          const SizedBox(width: 8),
          _TogglePill(
            label: 'No',
            isActive: !_wouldOrderAgain,
            onTap: () => setState(() => _wouldOrderAgain = false),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0E5A47),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 0,
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                'Submit Feedback',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
      ),
    );
  }
}

class _TogglePill extends StatelessWidget {
  const _TogglePill({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF0E5A47) : const Color(0xFFF5F7F6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color:
                isActive ? const Color(0xFF0E5A47) : const Color(0xFFE0E5E3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: isActive ? Colors.white : const Color(0xFF3A4644),
          ),
        ),
      ),
    );
  }
}

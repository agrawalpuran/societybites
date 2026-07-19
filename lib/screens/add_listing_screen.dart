import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../widgets/app_header.dart';
import '../models/data.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';

class AddListingScreen extends StatefulWidget {
  const AddListingScreen({super.key, this.existingListing});

  final FoodItem? existingListing;

  @override
  State<AddListingScreen> createState() => _AddListingScreenState();
}

class _AddListingScreenState extends State<AddListingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  final _weightPerUnitController = TextEditingController();
  final _descController = TextEditingController();
  String _pickup = 'My Home (Verified)';
  String _weightUnit = 'portions';
  String? _category;
  List<String> _selectedTags = [];
  DateTime? _dateTime;
  bool _isSubmitting = false;
  Uint8List? _imageBytes;
  String _imageMime = 'image/jpeg';
  String? _existingImageUrl;
  final ImagePicker _picker = ImagePicker();

  bool get _isEditing => widget.existingListing != null;

  @override
  void initState() {
    super.initState();
    final listing = widget.existingListing;
    if (listing != null) {
      _nameController.text = listing.name;
      _priceController.text = listing.price.toStringAsFixed(0);
      _descController.text = listing.description;
      _existingImageUrl = listing.imageUrl;
      _qtyController.text = listing.quantity.toString();
      if (listing.weightValue != null) {
        _weightPerUnitController.text = listing.weightValue!;
      }
      if (listing.weightUnit != null && listing.weightUnit!.isNotEmpty) {
        _weightUnit = listing.weightUnit!;
      }
      _selectedTags = List<String>.from(listing.tags);
      _category = listing.category;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _qtyController.dispose();
    _weightPerUnitController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 7)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null || !mounted) return;

    setState(() {
      _dateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  String get _formattedDateTime {
    if (_dateTime == null) return '';
    final d = _dateTime!;
    final h = d.hour > 12 ? d.hour - 12 : d.hour;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}, '
        '${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $ampm';
  }

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;

    final bytes = await file.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _imageMime = file.mimeType ?? 'image/jpeg';
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      final societyId =
          await SessionService.getSocietyId() ?? SessionService.defaultSocietyId;

      String? imageUrl = _existingImageUrl;
      if (_imageBytes != null) {
        imageUrl = await ApiService.uploadListingImage(
          bytes: _imageBytes!,
          mimeType: _imageMime,
        );
      }

      if (_isEditing) {
        await ApiService.updateListing(
          listingId: widget.existingListing!.id,
          name: _nameController.text.trim(),
          price: double.parse(_priceController.text.trim()),
          quantity: int.parse(_qtyController.text.trim()),
          description: _descController.text.trim(),
          availableAt: _dateTime,
          pickupLocation: _pickup,
          imageUrl: imageUrl,
          weightUnit: _weightUnit,
          weightValue: _weightPerUnitController.text.trim(),
          tags: _selectedTags,
          category: _category,
        );
      } else {
        await ApiService.createListing(
          societyId: societyId,
          name: _nameController.text.trim(),
          price: double.parse(_priceController.text.trim()),
          quantity: int.parse(_qtyController.text.trim()),
          description: _descController.text.trim(),
          availableAt: _dateTime,
          pickupLocation: _pickup,
          imageUrl: imageUrl,
          weightUnit: _weightUnit,
          weightValue: _weightPerUnitController.text.trim(),
          tags: _selectedTags,
          category: _category,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing
              ? 'Listing updated successfully!'
              : 'Listing created successfully!'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: const Color(0xFF0E5A47),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing
                ? 'Could not update listing: $e'
                : 'Could not create listing: $e',
          ),
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
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE5D6),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'SELLER PORTAL',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.3,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF4E2A20),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'List a New Bite',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF101617),
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Share your culinary creations with the\nneighborhood.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6A7774),
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildImageUpload(),
                      const SizedBox(height: 24),
                      _buildField(
                        label: 'ITEM NAME',
                        child: TextFormField(
                          controller: _nameController,
                          validator: (v) =>
                              v == null || v.trim().isEmpty ? 'Required' : null,
                          decoration: _inputDeco(
                              "e.g. Grandma's Sourdough Loaf"),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildField(
                        label: 'PRICE PER PORTION',
                        child: TextFormField(
                          controller: _priceController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[\d.]')),
                          ],
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Required';
                            if (double.tryParse(v) == null) return 'Invalid price';
                            return null;
                          },
                          decoration: _inputDeco('₹ 0.00'),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildField(
                        label: 'QUANTITY AVAILABLE',
                        child: TextFormField(
                          controller: _qtyController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          validator: (v) =>
                              v == null || v.trim().isEmpty ? 'Required' : null,
                          decoration: _inputDeco('1'),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildField(
                        label: 'WEIGHT PER PORTION',
                        child: TextFormField(
                          controller: _weightPerUnitController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[\d.]')),
                          ],
                          decoration: _inputDeco('e.g. 250'),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildField(
                        label: 'UNIT / WEIGHT TYPE',
                        child: Container(
                          height: 52,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border:
                                Border.all(color: const Color(0xFFE0E5E3)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _weightUnit,
                              isExpanded: true,
                              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                                  color: Color(0xFF8A9491)),
                              style: const TextStyle(
                                fontSize: 15,
                                color: Color(0xFF3A4644),
                                fontWeight: FontWeight.w500,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'portions',
                                  child: Text('Portions / Servings'),
                                ),
                                DropdownMenuItem(
                                  value: 'grams',
                                  child: Text('Grams (g)'),
                                ),
                                DropdownMenuItem(
                                  value: 'kg',
                                  child: Text('Kilograms (kg)'),
                                ),
                                DropdownMenuItem(
                                  value: 'ml',
                                  child: Text('Millilitres (ml)'),
                                ),
                                DropdownMenuItem(
                                  value: 'litres',
                                  child: Text('Litres (L)'),
                                ),
                                DropdownMenuItem(
                                  value: 'pieces',
                                  child: Text('Pieces'),
                                ),
                                DropdownMenuItem(
                                  value: 'packs',
                                  child: Text('Packs'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => _weightUnit = v);
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildField(
                        label: 'DATE/TIME AVAILABLE',
                        child: GestureDetector(
                          onTap: _pickDateTime,
                          child: Container(
                            height: 52,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: const Color(0xFFE0E5E3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today_rounded,
                                    size: 18, color: Color(0xFF8A9491)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _dateTime == null
                                        ? 'mm/dd/yyyy, --:-- --'
                                        : _formattedDateTime,
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: _dateTime == null
                                          ? const Color(0xFFADB5B2)
                                          : const Color(0xFF3A4644),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.calendar_month_rounded,
                                    size: 20, color: Color(0xFF8A9491)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildField(
                        label: 'PICKUP LOCATION',
                        child: Container(
                          height: 52,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border:
                                Border.all(color: const Color(0xFFE0E5E3)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _pickup,
                              isExpanded: true,
                              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                                  color: Color(0xFF8A9491)),
                              style: const TextStyle(
                                fontSize: 15,
                                color: Color(0xFF3A4644),
                                fontWeight: FontWeight.w500,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'My Home (Verified)',
                                  child: Row(
                                    children: [
                                      Icon(Icons.location_on_rounded,
                                          size: 18,
                                          color: Color(0xFF0E5A47)),
                                      SizedBox(width: 8),
                                      Text('My Home (Verified)'),
                                    ],
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'Lobby Area',
                                  child: Text('Lobby Area'),
                                ),
                                DropdownMenuItem(
                                  value: 'Society Gate',
                                  child: Text('Society Gate'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => _pickup = v);
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildField(
                        label: 'DESCRIPTION & INGREDIENTS',
                        child: TextFormField(
                          controller: _descController,
                          maxLines: 5,
                          decoration: _inputDeco(
                            'Tell the story of your dish. Mention\ningredients, allergens, or special prep\nmethods...',
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildField(
                        label: 'CATEGORY',
                        child: Container(
                          height: 52,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border:
                                Border.all(color: const Color(0xFFE0E5E3)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _category,
                              isExpanded: true,
                              hint: const Text(
                                'Select a category',
                                style: TextStyle(
                                  color: Color(0xFFADB5B2),
                                  fontSize: 15,
                                ),
                              ),
                              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                                  color: Color(0xFF8A9491)),
                              style: const TextStyle(
                                fontSize: 15,
                                color: Color(0xFF3A4644),
                                fontWeight: FontWeight.w500,
                              ),
                              items: const [
                                DropdownMenuItem(value: 'Breakfast', child: Text('Breakfast')),
                                DropdownMenuItem(value: 'Lunch', child: Text('Lunch')),
                                DropdownMenuItem(value: 'Dinner', child: Text('Dinner')),
                                DropdownMenuItem(value: 'Snacks', child: Text('Snacks')),
                                DropdownMenuItem(value: 'Desserts', child: Text('Desserts')),
                                DropdownMenuItem(value: 'Beverages', child: Text('Beverages')),
                                DropdownMenuItem(value: 'Healthy', child: Text('Healthy')),
                                DropdownMenuItem(value: 'Jain', child: Text('Jain')),
                                DropdownMenuItem(value: 'Kids', child: Text('Kids')),
                                DropdownMenuItem(value: 'Homemade Specials', child: Text('Homemade Specials')),
                              ],
                              onChanged: (v) {
                                setState(() => _category = v);
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildField(
                        label: 'FOOD TAGS',
                        child: _buildTagChips(),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 58,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0E5A47),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18)),
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
                                  'List Item',
                                  style: TextStyle(
                                      fontSize: 18, fontWeight: FontWeight.w700),
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildSafetyInfo(),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _availableTags = [
    'Vegetarian',
    'Non-Vegetarian',
    'Egg',
    'Vegan',
    'Mild',
    'Medium Spicy',
    'Spicy',
    'Extra Spicy',
    'Homemade',
    'No Preservatives',
    'Organic',
    'Sugar Free',
    'Gluten Free',
    'Fresh',
    'Slow Cooked',
  ];

  Widget _buildTagChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _availableTags.map((tag) {
        final isSelected = _selectedTags.contains(tag);
        return FilterChip(
          label: Text(tag),
          selected: isSelected,
          onSelected: (selected) {
            setState(() {
              if (selected) {
                _selectedTags.add(tag);
              } else {
                _selectedTags.remove(tag);
              }
            });
          },
          selectedColor: const Color(0xFFD6F0E4),
          checkmarkColor: const Color(0xFF0E5A47),
          backgroundColor: const Color(0xFFF5F7F6),
          side: BorderSide(
            color: isSelected
                ? const Color(0xFF0E5A47)
                : const Color(0xFFE0E5E3),
          ),
          labelStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected
                ? const Color(0xFF0E5A47)
                : const Color(0xFF3A4644),
          ),
        );
      }).toList(),
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

  Widget _buildImageUpload() {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        width: double.infinity,
        height: 170,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F2F1),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE0E5E3)),
        ),
        child: _imageBytes != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.memory(
                  _imageBytes!,
                  width: double.infinity,
                  height: 170,
                  fit: BoxFit.cover,
                ),
              )
            : _existingImageUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.network(
                      ApiService.absoluteUrl(_existingImageUrl!),
                      width: double.infinity,
                      height: 170,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _uploadPlaceholder(),
                    ),
                  )
                : _uploadPlaceholder(),
      ),
    );
  }

  Widget _uploadPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.add_a_photo_rounded,
              color: Color(0xFF0E5A47), size: 26),
        ),
        const SizedBox(height: 12),
        Text(
          _isEditing ? 'Change Cover Photo' : 'Upload Cover Photo',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF3A4644),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Tap to choose from gallery',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF8A9491),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6A7774),
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  InputDecoration _inputDeco(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFADB5B2), fontSize: 15),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE0E5E3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE0E5E3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF0E5A47)),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD94F4F)),
      ),
    );
  }

  Widget _buildSafetyInfo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5EE),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFFE0CC)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.verified_user_rounded,
                color: Color(0xFFE07B3C), size: 20),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'COMMUNITY SAFETY STANDARDS',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB85C3A),
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'By listing this item, you confirm compliance with local health '
                  'regulations and SocietyBites food safety guidelines. Ensure all '
                  'ingredients are listed to prevent allergen risks.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF7A5A42),
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

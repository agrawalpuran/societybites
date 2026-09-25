import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../widgets/app_header.dart';
import '../models/data.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../models/food_type.dart';
import '../models/listing_availability.dart';
import '../models/listing_categories.dart';
import '../widgets/available_in_selector.dart';
import '../widgets/simple_time_picker.dart';
import '../widgets/food_type_selector.dart';
import '../widgets/photo_source_sheet.dart';
import '../widgets/required_field_label.dart';

class AddListingScreen extends StatefulWidget {
  const AddListingScreen({
    super.key,
    this.existingListing,
    this.catalogType = listingCatalogRegular,
    this.initialAvailabilityMode = listingAvailabilityReadyNow,
  });

  final FoodItem? existingListing;
  final String catalogType;
  final String initialAvailabilityMode;

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
  final Set<String> _selectedCategories = {};
  List<String> _legacyCategories = [];
  String? _foodType;
  List<String> _selectedTags = [];
  DateTime? _dateTime;
  bool _isSubmitting = false;
  Uint8List? _imageBytes;
  String _imageMime = 'image/jpeg';
  String? _existingImageUrl;
  final ImagePicker _picker = ImagePicker();
  late String _availabilityMode;
  int _prepPresetMinutes = 60;
  final _customPrepDaysController = TextEditingController();

  bool get _isEditing => widget.existingListing != null;
  bool get _isPreorderCatalog =>
      widget.catalogType == listingCatalogPreorder ||
      (widget.existingListing?.isPreOrderCatalog ?? false);
  bool get _isMadeToOrder =>
      !_isPreorderCatalog &&
      _availabilityMode == listingAvailabilityMadeToOrder;
  bool get _showFulfilmentChoice => _isEditing && !_isPreorderCatalog;
  bool get _showFulfilmentSection =>
      !_isPreorderCatalog && (_showFulfilmentChoice || _isMadeToOrder);
  bool get _showStockAndExpiryFields =>
      !_isMadeToOrder && !_isPreorderCatalog;

  String get _orderTypeTitle {
    if (_isPreorderCatalog) return 'Pre-order';
    if (_isMadeToOrder) return 'Made to order';
    return 'Available now order';
  }

  int? get _selectedPrepMinutes {
    if (!_isMadeToOrder) return null;
    final daysRaw = _customPrepDaysController.text.trim();
    if (daysRaw.isNotEmpty) {
      final days = int.tryParse(daysRaw);
      if (days == null) return null;
      return preparationMinutesFromDays(days);
    }
    return _prepPresetMinutes;
  }

  Widget _buildFulfilmentSection() {
    return _buildField(
      label: _showFulfilmentChoice
          ? 'HOW WILL YOU FULFIL THIS?'
          : 'PREPARATION TIME',
      isRequired: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_showFulfilmentChoice) ...[
            _FulfilmentOption(
              selected: !_isMadeToOrder,
              title: 'Available Now',
              subtitle: 'Normally available for regular orders',
              onTap: () => setState(() {
                _availabilityMode = listingAvailabilityReadyNow;
              }),
            ),
            const SizedBox(height: 8),
            _FulfilmentOption(
              selected: _isMadeToOrder,
              title: 'Made to Order',
              subtitle: 'Prepare this after a buyer places an order',
              onTap: () => setState(() {
                _availabilityMode = listingAvailabilityMadeToOrder;
              }),
            ),
          ],
          if (_isMadeToOrder) ...[
            if (_showFulfilmentChoice) ...[
              const SizedBox(height: 14),
              RequiredFieldLabel(
                'PREPARATION TIME',
                required: true,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: Color(0xFF8A9491),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _prepChip(30, '30 minutes'),
                _prepChip(60, '1 hour'),
                _prepChip(120, '2 hours'),
                _prepChip(240, '4 hours'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 64,
                  child: TextFormField(
                    key: const Key('prep-days-field'),
                    controller: _customPrepDaysController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    decoration: _inputDeco('1').copyWith(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                      errorStyle: const TextStyle(fontSize: 11, height: 1.2),
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (value) {
                      if (!_isMadeToOrder) return null;
                      final raw = value?.trim() ?? '';
                      if (raw.isEmpty) return null;
                      final days = int.tryParse(raw);
                      if (days == null ||
                          days < 1 ||
                          days > maxPreparationDays) {
                        return '1–$maxPreparationDays';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'days',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3A4644),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'This is an estimate. You still confirm the actual ready time after accepting.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: Color(0xFF6A7774),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _prepChip(int minutes, String label) {
    final selected = _customPrepDaysController.text.trim().isEmpty &&
        _prepPresetMinutes == minutes;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _prepPresetMinutes = minutes;
          _customPrepDaysController.clear();
        });
      },
      selectedColor: const Color(0xFFD6F0E4),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w700,
        color: selected ? const Color(0xFF0E5A47) : const Color(0xFF3A4644),
      ),
      side: BorderSide(
        color: selected ? const Color(0xFF0E5A47) : const Color(0xFFE0E5E3),
      ),
    );
  }

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
      final known = listing.listingCategories
          .map(normalizeListingCategory)
          .whereType<String>()
          .toSet();
      _selectedCategories.addAll(
        known.where(listingFoodCategories.contains),
      );
      _legacyCategories = known
          .where((item) => !listingFoodCategories.contains(item))
          .toList();
      _foodType = parseFoodType(listing.foodType);
      _dateTime = listing.availableAt;
      _availabilityMode = listing.isMadeToOrder
          ? listingAvailabilityMadeToOrder
          : listingAvailabilityReadyNow;
      if (listing.preparationTimeMinutes != null) {
        _prepPresetMinutes = listing.preparationTimeMinutes!;
        final days = preparationDaysFromMinutes(_prepPresetMinutes);
        if (days != null) {
          _customPrepDaysController.text = days.toString();
        }
      }
    } else {
      _availabilityMode = parseListingAvailabilityMode(
        widget.initialAvailabilityMode,
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _qtyController.dispose();
    _weightPerUnitController.dispose();
    _descController.dispose();
    _customPrepDaysController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final initial = _dateTime ?? DateTime.now().add(const Duration(hours: 1));
    final firstDate = listingAvailableUntilFirstDate();
    final lastDate = listingAvailableUntilLastDate();
    var initialDate = initial.isBefore(firstDate) ? firstDate : initial;
    if (initialDate.isAfter(lastDate)) initialDate = lastDate;
    final picked = await pickDateAndSimpleTime(
      context,
      initial: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      dateHelpText: 'Available until (up to $listingAvailableUntilMaxDays days)',
    );
    if (picked == null || !mounted) return;

    setState(() {
      _dateTime = picked;
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
    final source = await showPhotoSourceSheet(
      context,
      title: 'Add Food Photo',
    );
    if (source == null || !mounted) return;
    await _pickImageFrom(source);
  }

  Future<void> _pickImageFrom(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;

      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _imageMime = file.mimeType ?? 'image/jpeg';
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      final denied = error.code.toLowerCase().contains('denied') ||
          (error.message?.toLowerCase().contains('denied') ?? false) ||
          (error.message?.toLowerCase().contains('permission') ?? false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            denied
                ? (source == ImageSource.camera
                    ? 'Camera access is needed to take a photo. You can enable it in Settings.'
                    : 'Photo access is needed to choose from your gallery. You can enable it in Settings.')
                : 'Could not open ${source == ImageSource.camera ? 'the camera' : 'the gallery'}. Please try again.',
          ),
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _isSubmitting) return;

    if (_selectedCategories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one category.')),
      );
      return;
    }

    final foodTypeError = foodTypeSelectionError(
      foodType: _foodType,
      tags: _selectedTags,
    );
    if (foodTypeError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(foodTypeError)),
      );
      return;
    }

    int? prepMinutes;
    if (_isMadeToOrder) {
      prepMinutes = _selectedPrepMinutes;
      if (prepMinutes == null ||
          prepMinutes < 15 ||
          prepMinutes > maxPreparationTimeMinutes) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Choose a preparation time between 15 minutes and $maxPreparationDays days.',
            ),
          ),
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);

    try {
      final societyId = await SessionService.getSocietyId();
      if (societyId == null || societyId.isEmpty) {
        throw Exception('Join your society before creating a listing.');
      }

      String? imageUrl = _existingImageUrl;
      if (_imageBytes != null) {
        imageUrl = await ApiService.uploadListingImage(
          bytes: _imageBytes!,
          mimeType: _imageMime,
        );
      }

      final quantity = (_isMadeToOrder || _isPreorderCatalog)
          ? (_isEditing && widget.existingListing!.quantity > 0
              ? widget.existingListing!.quantity
              : 99)
          : int.parse(_qtyController.text.trim());

      if (_isEditing) {
        await ApiService.updateListing(
          listingId: widget.existingListing!.id,
          name: _nameController.text.trim(),
          price: double.parse(_priceController.text.trim()),
          quantity: quantity,
          description: _descController.text.trim(),
          availableAt: _showStockAndExpiryFields ? _dateTime : null,
          clearAvailableAt: !_showStockAndExpiryFields,
          pickupLocation: _pickup,
          imageUrl: imageUrl,
          weightUnit: _weightUnit,
          weightValue: _weightPerUnitController.text.trim(),
          tags: _selectedTags,
          categories: [..._selectedCategories, ..._legacyCategories],
          foodType: _foodType!,
          availabilityMode: _isPreorderCatalog
              ? listingAvailabilityReadyNow
              : _availabilityMode,
          preparationTimeMinutes: prepMinutes,
          maxDailyOrders: null,
          clearMaxDailyOrders: true,
        );
      } else {
        await ApiService.createListing(
          societyId: societyId,
          name: _nameController.text.trim(),
          price: double.parse(_priceController.text.trim()),
          quantity: quantity,
          description: _descController.text.trim(),
          availableAt: _showStockAndExpiryFields ? _dateTime : null,
          pickupLocation: _pickup,
          imageUrl: imageUrl,
          weightUnit: _weightUnit,
          weightValue: _weightPerUnitController.text.trim(),
          tags: _selectedTags,
          categories: [..._selectedCategories, ..._legacyCategories],
          foodType: _foodType!,
          catalogType: widget.catalogType,
          availabilityMode: _isPreorderCatalog
              ? listingAvailabilityReadyNow
              : _availabilityMode,
          preparationTimeMinutes: prepMinutes,
          maxDailyOrders: null,
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
                      Text(
                        _orderTypeTitle,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF101617),
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isEditing
                            ? 'Update this item. It stays in the same catalog.'
                            : _isPreorderCatalog
                                ? 'This adds an item to your pre-order catalog. After you save it, you can put it on a campaign.'
                                : _isMadeToOrder
                                    ? 'You prepare this after a buyer places an order. You can still accept or reject each order.'
                                    : 'Share your culinary creations with the\nneighborhood.',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6A7774),
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const RequiredFieldsLegend(),
                      const SizedBox(height: 24),
                      _buildImageUpload(),
                      const SizedBox(height: 24),
                      _buildField(
                        label: 'ITEM NAME',
                        isRequired: true,
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
                        isRequired: true,
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
                      if (_showStockAndExpiryFields) ...[
                        const SizedBox(height: 18),
                        _buildField(
                          label: 'QUANTITY AVAILABLE',
                          isRequired: true,
                          child: TextFormField(
                            controller: _qtyController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Required';
                              }
                              final n = int.tryParse(v.trim());
                              if (n == null || n < 1) return 'Enter at least 1';
                              return null;
                            },
                            decoration: _inputDeco(
                              _isEditing
                                  ? 'Remaining portions (current stock)'
                                  : '1',
                            ),
                          ),
                        ),
                      ],
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
                      if (_showStockAndExpiryFields) ...[
                        const SizedBox(height: 18),
                        _buildField(
                          label: 'DATE/TIME AVAILABLE UNTIL',
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
                      ],
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
                      if (_showFulfilmentSection) ...[
                        const SizedBox(height: 18),
                        _buildFulfilmentSection(),
                      ],
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
                        label: 'AVAILABLE IN',
                        isRequired: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AvailableInSelector(
                              selected: _selectedCategories,
                              onChanged: (value) {
                                setState(() {
                                  _selectedCategories
                                    ..clear()
                                    ..addAll(value);
                                });
                              },
                            ),
                            if (_selectedCategories.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Available in: ${formatAvailableIn(_selectedCategories)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF6A7774),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildField(
                        label: 'FOOD TYPE',
                        isRequired: true,
                        child: FoodTypeSelector(
                          value: _foodType,
                          onChanged: (value) {
                            setState(() => _foodType = value);
                          },
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
                      errorBuilder: (context, error, stackTrace) =>
                          _uploadPlaceholder(),
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
          'Tap to take a photo or choose from gallery',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF8A9491),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildField({
    required String label,
    required Widget child,
    bool isRequired = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RequiredFieldLabel(label, required: isRequired),
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

class _FulfilmentOption extends StatelessWidget {
  const _FulfilmentOption({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFE8F5EE) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? const Color(0xFF0E5A47) : const Color(0xFFE0E5E3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 22,
                color: selected
                    ? const Color(0xFF0E5A47)
                    : const Color(0xFF8A9491),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101617),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6A7774),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

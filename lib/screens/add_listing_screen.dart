import 'package:flutter/material.dart';

import '../web/web_page_frame.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../widgets/app_header.dart';
import '../models/data.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../models/food_type.dart';
import '../models/listing_availability.dart';
import '../models/listing_categories.dart';
import '../models/pickup_location.dart';
import '../models/recurring_availability.dart';
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
  String _pickup = defaultPickupLocation;
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
  bool _repeatSchedule = false;
  final Set<int> _recurringDays = {};
  TimeOfDay _recurringStart = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _recurringEnd = const TimeOfDay(hour: 11, minute: 0);
  bool _dailyLimitEnabled = false;
  final _dailyLimitController = TextEditingController();
  bool _todayFullDay = true;

  bool get _isEditing => widget.existingListing != null;
  bool get _isPreorderCatalog =>
      widget.catalogType == listingCatalogPreorder ||
      (widget.existingListing?.isPreOrderCatalog ?? false);
  bool get _isMadeToOrder =>
      !_isPreorderCatalog &&
      _availabilityMode == listingAvailabilityMadeToOrder;
  /// Type is chosen on Add listing (Available Now vs Made to Order vs Pre-order),
  /// not switched again on edit.
  bool get _showFulfilmentSection => !_isPreorderCatalog && _isMadeToOrder;
  bool get _showStockAndExpiryFields =>
      !_isMadeToOrder && !_isPreorderCatalog && !_repeatSchedule;
  bool get _showRecurringSection => !_isMadeToOrder && !_isPreorderCatalog;
  bool get _showUntilField => _showStockAndExpiryFields && _todayFullDay;

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

  Widget _buildRecurringSection() {
    return _buildField(
      label: 'WHEN IS THIS AVAILABLE?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FulfilmentOption(
            key: const Key('listing-availability-today'),
            selected: !_repeatSchedule,
            title: 'Just today',
            subtitle:
                'Neighbors can order it today. List it again tomorrow if you cook again.',
            onTap: () => setState(() => _repeatSchedule = false),
            child: !_repeatSchedule ? _buildJustTodayHours() : null,
          ),
          const SizedBox(height: 8),
          _FulfilmentOption(
            key: const Key('listing-availability-repeat'),
            selected: _repeatSchedule,
            title: 'Same days every week',
            subtitle:
                'For regular items like idli or thepla. We will show it on the days you choose.',
            onTap: () => setState(() => _repeatSchedule = true),
            child: _repeatSchedule ? _buildWeeklySchedule() : null,
          ),
        ],
      ),
    );
  }

  Widget _buildJustTodayHours() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FulfilmentOption(
          key: const Key('listing-today-full-day'),
          selected: _todayFullDay,
          nested: true,
          title: 'Full day',
          subtitle: 'Neighbors can order anytime today.',
          onTap: () => setState(() => _todayFullDay = true),
        ),
        const SizedBox(height: 8),
        _FulfilmentOption(
          key: const Key('listing-today-hours'),
          selected: !_todayFullDay,
          nested: true,
          title: 'Specific hours',
          subtitle: 'Only take orders between the times you choose.',
          onTap: () => setState(() => _todayFullDay = false),
        ),
        if (!_todayFullDay) ...[
          const SizedBox(height: 8),
          _buildHoursPickers(
            startKey: 'listing-today-start',
            endKey: 'listing-today-end',
          ),
        ],
      ],
    );
  }

  Widget _buildWeeklySchedule() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'WHICH DAYS?',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: Color(0xFF8A9491),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(7, (index) {
            final day = index + 1;
            final selected = _recurringDays.contains(day);
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: index == 6 ? 0 : 4),
                child: Material(
                  color: selected
                      ? const Color(0xFF0E5A47)
                      : const Color(0xFFF0F2F1),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    key: Key('listing-recurring-day-$day'),
                    onTap: () {
                      setState(() {
                        if (selected) {
                          _recurringDays.remove(day);
                        } else {
                          _recurringDays.add(day);
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      height: 40,
                      child: Center(
                        child: Text(
                          recurringWeekdayLabels[index],
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: selected
                                ? Colors.white
                                : const Color(0xFF3A4644),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 16),
        const Text(
          'WHAT TIME?',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: Color(0xFF8A9491),
          ),
        ),
        const SizedBox(height: 8),
        _buildHoursPickers(),
        const SizedBox(height: 16),
        const Text(
          'HOW MANY PER DAY?',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: Color(0xFF8A9491),
          ),
        ),
        const SizedBox(height: 8),
        _FulfilmentOption(
          key: const Key('listing-daily-unlimited'),
          selected: !_dailyLimitEnabled,
          nested: true,
          title: 'No limit',
          subtitle: 'Keep taking orders during these hours.',
          onTap: () => setState(() => _dailyLimitEnabled = false),
        ),
        const SizedBox(height: 8),
        _FulfilmentOption(
          key: const Key('listing-daily-limit'),
          selected: _dailyLimitEnabled,
          nested: true,
          title: 'I have a limit',
          subtitle: 'Stop orders after this many portions.',
          onTap: () => setState(() => _dailyLimitEnabled = true),
        ),
        if (_dailyLimitEnabled) ...[
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('listing-daily-limit-field'),
            controller: _dailyLimitController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _inputDeco('e.g. 20'),
          ),
        ],
      ],
    );
  }

  Widget _buildHoursPickers({
    String startKey = 'listing-recurring-start',
    String endKey = 'listing-recurring-end',
  }) {
    return Row(
      children: [
        Expanded(
          child: _timeButton(
            key: Key(startKey),
            label: _recurringStart.format(context),
            onTap: () async {
              final picked = await showSimpleTimePicker(
                context,
                initialTime: _recurringStart,
              );
              if (picked != null && mounted) {
                setState(() => _recurringStart = picked);
              }
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'to',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF6A7774),
            ),
          ),
        ),
        Expanded(
          child: _timeButton(
            key: Key(endKey),
            label: _recurringEnd.format(context),
            onTap: () async {
              final picked = await showSimpleTimePicker(
                context,
                initialTime: _recurringEnd,
              );
              if (picked != null && mounted) {
                setState(() => _recurringEnd = picked);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _timeButton({
    required Key key,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      key: key,
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE0E5E3)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101617),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFulfilmentSection() {
    return _buildField(
      label: 'PREPARATION TIME',
      isRequired: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isMadeToOrder) ...[
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
      if (listing.pickupLocation != null &&
          listing.pickupLocation!.trim().isNotEmpty) {
        _pickup = listing.pickupLocation!;
      }
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
      if (listing.recurringEnabled && !listing.isMadeToOrder) {
        _repeatSchedule = true;
        _recurringDays.addAll(listing.recurringWeekdays);
        if (listing.recurringStartMinute != null) {
          _recurringStart = TimeOfDay(
            hour: listing.recurringStartMinute! ~/ 60,
            minute: listing.recurringStartMinute! % 60,
          );
        }
        if (listing.recurringEndMinute != null) {
          _recurringEnd = TimeOfDay(
            hour: listing.recurringEndMinute! ~/ 60,
            minute: listing.recurringEndMinute! % 60,
          );
        }
        if (listing.recurringDailyLimit != null) {
          _dailyLimitEnabled = true;
          _dailyLimitController.text = '${listing.recurringDailyLimit}';
        }
      } else if (!listing.isMadeToOrder &&
          listing.recurringStartMinute != null &&
          listing.recurringEndMinute != null) {
        _todayFullDay = false;
        _recurringStart = TimeOfDay(
          hour: listing.recurringStartMinute! ~/ 60,
          minute: listing.recurringStartMinute! % 60,
        );
        _recurringEnd = TimeOfDay(
          hour: listing.recurringEndMinute! ~/ 60,
          minute: listing.recurringEndMinute! % 60,
        );
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
    _dailyLimitController.dispose();
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

    final useRecurring = _showRecurringSection && _repeatSchedule;
    final sameDayHours =
        _showRecurringSection && !_repeatSchedule && !_todayFullDay;
    if (useRecurring || sameDayHours) {
      if (useRecurring && _recurringDays.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select at least one available day.')),
        );
        return;
      }
      final startMinute = timeOfDayToMinute(
        _recurringStart.hour,
        _recurringStart.minute,
      );
      final endMinute = timeOfDayToMinute(
        _recurringEnd.hour,
        _recurringEnd.minute,
      );
      if (endMinute <= startMinute) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('End time must be after the start time.')),
        );
        return;
      }
      if (useRecurring && _dailyLimitEnabled) {
        final limit = int.tryParse(_dailyLimitController.text.trim());
        if (limit == null || limit < 1) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enter a daily quantity of 1 or more.')),
          );
          return;
        }
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

      final quantity = (_isMadeToOrder || _isPreorderCatalog || useRecurring)
          ? (_isEditing && widget.existingListing!.quantity > 0
              ? widget.existingListing!.quantity
              : 99)
          : int.parse(_qtyController.text.trim());
      final recurringStartMinute = timeOfDayToMinute(
        _recurringStart.hour,
        _recurringStart.minute,
      );
      final recurringEndMinute = timeOfDayToMinute(
        _recurringEnd.hour,
        _recurringEnd.minute,
      );
      final recurringLimit = useRecurring && _dailyLimitEnabled
          ? int.parse(_dailyLimitController.text.trim())
          : null;

      final sameDayEnd = sameDayHours
          ? DateTime(
              DateTime.now().year,
              DateTime.now().month,
              DateTime.now().day,
              _recurringEnd.hour,
              _recurringEnd.minute,
            )
          : null;
      final availableAt = sameDayHours
          ? sameDayEnd
          : (_showUntilField ? _dateTime : null);

      if (_isEditing) {
        await ApiService.updateListing(
          listingId: widget.existingListing!.id,
          name: _nameController.text.trim(),
          price: double.parse(_priceController.text.trim()),
          quantity: quantity,
          description: _descController.text.trim(),
          availableAt: availableAt,
          clearAvailableAt: availableAt == null && !_showUntilField,
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
          recurringEnabled: _showRecurringSection && useRecurring,
          sameDayHours: sameDayHours,
          recurringWeekdays: useRecurring ? _recurringDays.toList() : const [],
          recurringStartMinute:
              (useRecurring || sameDayHours) ? recurringStartMinute : null,
          recurringEndMinute:
              (useRecurring || sameDayHours) ? recurringEndMinute : null,
          recurringDailyLimit: recurringLimit,
        );
      } else {
        await ApiService.createListing(
          societyId: societyId,
          name: _nameController.text.trim(),
          price: double.parse(_priceController.text.trim()),
          quantity: quantity,
          description: _descController.text.trim(),
          availableAt: availableAt,
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
          recurringEnabled: _showRecurringSection && useRecurring,
          sameDayHours: sameDayHours,
          recurringWeekdays: useRecurring ? _recurringDays.toList() : const [],
          recurringStartMinute:
              (useRecurring || sameDayHours) ? recurringStartMinute : null,
          recurringEndMinute:
              (useRecurring || sameDayHours) ? recurringEndMinute : null,
          recurringDailyLimit: recurringLimit,
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
    return centerOnWeb(
      context,
      Scaffold(
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
                      if (_showRecurringSection) ...[
                        const SizedBox(height: 18),
                        _buildRecurringSection(),
                      ],
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
                      if (_showUntilField) ...[
                        const SizedBox(height: 18),
                        _buildField(
                          label: 'AVAILABLE UNTIL (OPTIONAL)',
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
                                  color: const Color(0xFFE0E5E3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.calendar_today_rounded,
                                    size: 18,
                                    color: Color(0xFF8A9491),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _dateTime == null
                                          ? 'Tap to choose when to stop taking orders'
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
                                  const Icon(
                                    Icons.calendar_month_rounded,
                                    size: 20,
                                    color: Color(0xFF8A9491),
                                  ),
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
                              items: [
                                for (final location in [
                                  ...listingPickupLocations,
                                  if (!listingPickupLocations.contains(_pickup))
                                    _pickup,
                                ])
                                  DropdownMenuItem(
                                    value: location,
                                    child: location == defaultPickupLocation
                                        ? const Row(
                                            children: [
                                              Icon(
                                                Icons.location_on_rounded,
                                                size: 18,
                                                color: Color(0xFF0E5A47),
                                              ),
                                              SizedBox(width: 8),
                                              Text(defaultPickupLocation),
                                            ],
                                          )
                                        : Text(location),
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
                        label: 'CATEGORY',
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
                                'Category: ${formatAvailableIn(_selectedCategories)}',
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
    ),
      maxWidth: 840,
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
                  'regulations and SocietyEats food safety guidelines. Ensure all '
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
    super.key,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.child,
    this.nested = false,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? child;
  final bool nested;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected && !nested
          ? const Color(0xFFE8F5EE)
          : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFF0E5A47) : const Color(0xFFE0E5E3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onTap,
              borderRadius: child == null
                  ? BorderRadius.circular(14)
                  : const BorderRadius.vertical(top: Radius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
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
            if (child != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: child,
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../web/web_breakpoints.dart';
import '../web/web_page_frame.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../widgets/app_header.dart';
import '../models/data.dart';
import '../services/api_service.dart';
import '../services/listing_publish_navigation.dart';
import '../services/my_listings_cache.dart';
import '../services/session_service.dart';
import '../models/food_type.dart';
import '../models/coupon.dart';
import '../models/listing_availability.dart';
import '../models/listing_categories.dart';
import '../models/listing_discount.dart';
import '../models/pickup_location.dart';
import '../models/recurring_availability.dart';
import '../widgets/available_in_selector.dart';
import '../widgets/simple_time_picker.dart';
import '../widgets/food_type_selector.dart';
import '../widgets/photo_source_sheet.dart';
import '../widgets/required_field_label.dart';
import '../utils/inventory_units.dart';

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
  static final _pairedFieldLabelStyle = requiredFieldLabelStyle.copyWith(
    fontSize: 9,
    letterSpacing: 0.9,
    height: 1.35,
  );

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
  bool _untilStockLasts = false;
  final Set<int> _recurringDays = {};
  TimeOfDay _recurringStart = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _recurringEnd = const TimeOfDay(hour: 11, minute: 0);
  bool _dailyLimitEnabled = false;
  final _dailyLimitController = TextEditingController();
  bool _todayFullDay = true;
  bool _useMultipleSizes = false;
  /// SEPARATE = per-size stock; SHARED = one pool (e.g. paneer block).
  String _variantInventoryMode = 'SEPARATE';
  final List<_ListingVariantDraft> _variantDrafts = [];
  final _variantLabelController = TextEditingController();
  final _sharedPoolController = TextEditingController();
  InventoryUnit _sharedPoolUnit = InventoryUnit.kg;
  bool _discountEnabled = false;
  final _discountPercentController = TextEditingController();
  DateTime? _discountStartsAt;
  DateTime? _discountEndsAt;

  bool get _isEditing => widget.existingListing != null;
  bool get _showMultipleSizes =>
      !_isEditing && !_isPreorderCatalog && _showStockAndExpiryFields;
  bool get _isPreorderCatalog =>
      widget.catalogType == listingCatalogPreorder ||
      (widget.existingListing?.isPreOrderCatalog ?? false);
  bool get _isMadeToOrder =>
      !_isPreorderCatalog &&
      _availabilityMode == listingAvailabilityMadeToOrder;
  /// Type is chosen on Add listing (Available Now vs Made to Order vs Pre-order),
  /// not switched again on edit.
  bool get _showFulfilmentSection => !_isPreorderCatalog && _isMadeToOrder;
  bool get _isJustToday => !_repeatSchedule && !_untilStockLasts;
  bool get _showStockAndExpiryFields =>
      !_isMadeToOrder && !_isPreorderCatalog && !_repeatSchedule;

  bool get _showQuantityAvailableField =>
      !_isPreorderCatalog && (_isMadeToOrder || _showStockAndExpiryFields);

  bool get _showWeightAndUnitFields =>
      _isPreorderCatalog || _isMadeToOrder || _showStockAndExpiryFields;

  bool get _showRecurringSection => !_isMadeToOrder && !_isPreorderCatalog;
  /// Just today already ends today, so an extra stop date is not offered.
  bool get _showUntilField => false;

  bool get _discountAppliesToVariantGroup {
    if (_useMultipleSizes) return true;
    final groupId = widget.existingListing?.variantGroupId?.trim();
    return groupId != null && groupId.isNotEmpty;
  }

  int? get _discountPercentValue {
    final raw = _discountPercentController.text.trim();
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  double? get _discountPreviewRegularPrice {
    if (_useMultipleSizes && _variantDrafts.isNotEmpty) {
      return double.tryParse(_variantDrafts.first.priceController.text.trim());
    }
    return double.tryParse(_priceController.text.trim());
  }

  String get _orderTypeTitle {
    if (_isPreorderCatalog) return 'Pre-order Catalog';
    if (_isMadeToOrder) return 'Made to order';
    return 'Available now order';
  }

  (String? value, String? unit) _weightFieldsForApi() {
    final trimmed = _weightPerUnitController.text.trim();
    if (trimmed.isEmpty) {
      if (_isEditing) return ('', '');
      return (null, null);
    }
    return (trimmed, _weightUnit);
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
            selected: _isJustToday,
            title: 'Just today',
            subtitle:
                'Neighbors can order it today. List it again tomorrow if you cook again.',
            onTap: () => setState(() {
              _repeatSchedule = false;
              _untilStockLasts = false;
            }),
            child: _isJustToday ? _buildJustTodayHours() : null,
          ),
          const SizedBox(height: 8),
          _FulfilmentOption(
            key: const Key('listing-availability-repeat'),
            selected: _repeatSchedule,
            title: 'Same days every week',
            subtitle:
                'For regular items like idli or thepla. We will show it on the days you choose.',
            onTap: () => setState(() {
              _repeatSchedule = true;
              _untilStockLasts = false;
            }),
            child: _repeatSchedule ? _buildWeeklySchedule() : null,
          ),
          const SizedBox(height: 8),
          _FulfilmentOption(
            key: const Key('listing-availability-until-stock'),
            selected: _untilStockLasts,
            title: 'Till stock lasts',
            subtitle: 'Neighbors can order until this quantity runs out.',
            onTap: () => setState(() {
              _repeatSchedule = false;
              _untilStockLasts = true;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildJustTodayHours() {
    return Padding(
      padding: const EdgeInsets.only(left: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _TodayWindowChoice(
                  key: const Key('listing-today-full-day'),
                  selected: _todayFullDay,
                  title: 'Full day',
                  onTap: () => setState(() => _todayFullDay = true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TodayWindowChoice(
                  key: const Key('listing-today-hours'),
                  selected: !_todayFullDay,
                  title: 'Specific hours',
                  onTap: () => setState(() => _todayFullDay = false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _todayFullDay
                ? 'Neighbors can order anytime today.'
                : 'Only take orders between the times you choose.',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6A7774),
            ),
          ),
          if (!_todayFullDay) ...[
            const SizedBox(height: 8),
            _buildHoursPickers(
              startKey: 'listing-today-start',
              endKey: 'listing-today-end',
            ),
          ],
        ],
      ),
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
        Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _TodayWindowChoice(
                      key: const Key('listing-daily-unlimited'),
                      selected: !_dailyLimitEnabled,
                      title: 'No limit',
                      onTap: () => setState(() => _dailyLimitEnabled = false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _TodayWindowChoice(
                      key: const Key('listing-daily-limit'),
                      selected: _dailyLimitEnabled,
                      title: 'I have a limit',
                      onTap: () => setState(() => _dailyLimitEnabled = true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _dailyLimitEnabled
                    ? 'Stop orders after this many portions.'
                    : 'Keep taking orders during these hours.',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6A7774),
                ),
              ),
            ],
          ),
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

  Widget _buildWeightAndUnitRow() {
    const weightLabel = 'WEIGHT';
    const unitLabel = 'UNIT';
    return Row(
      key: const Key('listing-weight-unit-row'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: _buildField(
            label: weightLabel,
            labelStyle: _pairedFieldLabelStyle,
            child: TextFormField(
              key: const Key('listing-weight-field'),
              controller: _weightPerUnitController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              decoration: _inputDeco('e.g. 250'),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: _buildField(
            label: unitLabel,
            labelStyle: _pairedFieldLabelStyle,
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE0E5E3)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: const Key('listing-weight-unit'),
                  value: _weightUnit,
                  isExpanded: true,
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Color(0xFF8A9491),
                  ),
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF3A4644),
                    fontWeight: FontWeight.w500,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'portions',
                      child: Text(
                        'Portions / Servings',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'grams',
                      child: Text(
                        'Grams (g)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'kg',
                      child: Text(
                        'Kilograms (kg)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'ml',
                      child: Text(
                        'Millilitres (ml)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'litres',
                      child: Text(
                        'Litres (L)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'pieces',
                      child: Text(
                        'Pieces',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'packs',
                      child: Text(
                        'Packs',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _weightUnit = v);
                    }
                  },
                ),
              ),
            ),
          ),
        ),
      ],
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
      if (listing.variantLabel != null) {
        _variantLabelController.text = listing.variantLabel!;
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
        _untilStockLasts = false;
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
        _untilStockLasts = false;
        _recurringStart = TimeOfDay(
          hour: listing.recurringStartMinute! ~/ 60,
          minute: listing.recurringStartMinute! % 60,
        );
        _recurringEnd = TimeOfDay(
          hour: listing.recurringEndMinute! ~/ 60,
          minute: listing.recurringEndMinute! % 60,
        );
      } else if (!listing.isMadeToOrder &&
          !listing.recurringEnabled &&
          listing.availableAt == null) {
        _untilStockLasts = true;
      }
      _discountEnabled = listing.discountEnabled;
      final storedPercent = listing.discountPercent;
      if (storedPercent != null) {
        final asInt = storedPercent.round();
        _discountPercentController.text = asInt == storedPercent
            ? '$asInt'
            : storedPercent.toString();
      }
      if (listing.discountStartsAt != null) {
        _discountStartsAt =
            listingDiscountCalendarDate(listing.discountStartsAt!);
      }
      if (listing.discountEndsAt != null) {
        _discountEndsAt = listingDiscountCalendarDate(listing.discountEndsAt!);
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
    _variantLabelController.dispose();
    _sharedPoolController.dispose();
    _discountPercentController.dispose();
    for (final draft in _variantDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  bool get _variantSharedPool =>
      _useMultipleSizes && _variantInventoryMode == 'SHARED';

  void _enableMultipleSizes(bool enabled) {
    setState(() {
      _useMultipleSizes = enabled;
      if (enabled && _variantDrafts.isEmpty) {
        _variantDrafts.addAll([
          _ListingVariantDraft(
            qty: '250',
            stock: '10',
            unit: InventoryUnit.grams,
          )..syncLabelFromAmount(),
          _ListingVariantDraft(
            qty: '500',
            stock: '10',
            unit: InventoryUnit.grams,
          )..syncLabelFromAmount(),
        ]);
        if (_sharedPoolController.text.trim().isEmpty) {
          _sharedPoolController.text = '10';
          _sharedPoolUnit = InventoryUnit.kg;
        }
      }
    });
  }

  void _setVariantInventoryMode(String mode) {
    setState(() {
      _variantInventoryMode = mode;
      if (mode == 'SHARED') {
        for (final draft in _variantDrafts) {
          final n = double.tryParse(draft.qtyController.text.trim());
          if (n == null || n <= 0) {
            draft.qtyController.text = '250';
            draft.unit = InventoryUnit.grams;
          }
          draft.syncLabelFromAmount();
        }
        if (_sharedPoolController.text.trim().isEmpty) {
          _sharedPoolController.text = '10';
          _sharedPoolUnit = InventoryUnit.kg;
        }
      }
    });
  }

  void _addVariantDraft() {
    if (_variantDrafts.length >= 8) return;
    setState(() {
      final draft = _ListingVariantDraft(
        qty: '250',
        stock: '10',
        unit: InventoryUnit.grams,
      )..syncLabelFromAmount();
      _variantDrafts.add(draft);
    });
  }

  void _removeVariantDraft(int index) {
    if (_variantDrafts.length <= 2) return;
    setState(() {
      _variantDrafts.removeAt(index).dispose();
    });
  }

  List<Map<String, dynamic>>? _variantsPayloadOrNull() {
    if (!_useMultipleSizes || _variantDrafts.length < 2) return null;
    final shared = _variantSharedPool;
    return _variantDrafts.map((draft) {
      final label = draft.suggestedLabel();
      final price = double.parse(draft.priceController.text.trim());
      final amount = double.parse(draft.qtyController.text.trim());
      if (shared) {
        return {
          'label': label,
          'price': price,
          'portionAmount': amount,
          'portionUnit': draft.unit.apiValue,
          'weightValue': amount.toString(),
          'weightUnit': draft.unit.apiValue,
        };
      }
      return {
        'label': label,
        'price': price,
        'quantity': int.parse(draft.stockController.text.trim()),
        'weightValue': amount.toString(),
        'weightUnit': draft.unit.apiValue,
      };
    }).toList();
  }

  num? _sharedPoolAmountOrNull() {
    if (!_variantSharedPool) return null;
    return num.parse(_sharedPoolController.text.trim());
  }

  String? _sharedPoolUnitOrNull() {
    if (!_variantSharedPool) return null;
    return _sharedPoolUnit.apiValue;
  }

  Widget _buildInventoryUnitDropdown({
    required InventoryUnit value,
    required ValueChanged<InventoryUnit> onChanged,
    Key? key,
  }) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E5E3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: key,
          value: value.apiValue,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF8A9491),
          ),
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF3A4644),
            fontWeight: FontWeight.w500,
          ),
          items: [
            for (final unit in InventoryUnit.all)
              DropdownMenuItem(
                value: unit.apiValue,
                child: Text(unit.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v == null) return;
            onChanged(InventoryUnit.parse(v));
          },
        ),
      ),
    );
  }

  Widget _buildMultipleSizesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Multiple sizes',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101617),
            ),
          ),
          subtitle: Text(
            _variantSharedPool
                ? 'e.g. Paneer from one block — sizes share one pool of stock'
                : 'e.g. Juice bottles — each size has its own price and stock',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6A7774),
              height: 1.35,
            ),
          ),
          value: _useMultipleSizes,
          activeColor: const Color(0xFF0E5A47),
          onChanged: _enableMultipleSizes,
        ),
        if (_useMultipleSizes) ...[
          const SizedBox(height: 8),
          _buildVariantModePicker(),
          if (_variantSharedPool) ...[
            const SizedBox(height: 12),
            _buildField(
              label: 'TOTAL AVAILABLE (SHARED POOL)',
              isRequired: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _sharedPoolController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                      ],
                      validator: (v) {
                        if (!_variantSharedPool) return null;
                        final n = double.tryParse(v?.trim() ?? '');
                        if (n == null || n <= 0) return 'Required';
                        return null;
                      },
                      decoration: _inputDeco('e.g. 10'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: _buildInventoryUnitDropdown(
                      key: const Key('shared-pool-unit'),
                      value: _sharedPoolUnit,
                      onChanged: (unit) {
                        setState(() => _sharedPoolUnit = unit);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '10 kg + 250 g sizes is fine — we convert to the same base for stock.',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF6A7774),
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          for (var i = 0; i < _variantDrafts.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _buildVariantDraftRow(i),
          ],
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _variantDrafts.length >= 8 ? null : _addVariantDraft,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add size'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF0E5A47),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildVariantModePicker() {
    return Column(
      children: [
        _VariantModeTile(
          selected: !_variantSharedPool,
          title: 'Each size has its own stock',
          subtitle: 'Juice bottles, packs — stock counted separately',
          onTap: () => _setVariantInventoryMode('SEPARATE'),
        ),
        const SizedBox(height: 8),
        _VariantModeTile(
          selected: _variantSharedPool,
          title: 'Sizes share one pool',
          subtitle: 'One block of paneer sold as 250 g / 500 g / 1 kg',
          onTap: () => _setVariantInventoryMode('SHARED'),
        ),
      ],
    );
  }

  Widget _buildVariantDraftRow(int index) {
    final draft = _variantDrafts[index];
    final shared = _variantSharedPool;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E5E3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Size ${index + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6A7774),
                  ),
                ),
              ),
              if (_variantDrafts.length > 2)
                IconButton(
                  tooltip: 'Remove size',
                  onPressed: () => _removeVariantDraft(index),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: const Color(0xFF8A9491),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if (shared) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: draft.qtyController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                    ],
                    onChanged: (_) {
                      draft.syncLabelFromAmount();
                      setState(() {});
                    },
                    validator: (v) {
                      if (!_useMultipleSizes) return null;
                      final n = double.tryParse(v?.trim() ?? '');
                      if (n == null || n <= 0) return 'Required';
                      if (!inventoryUnitsCompatible(
                        _sharedPoolUnit,
                        draft.unit,
                      )) {
                        return 'Unit kind';
                      }
                      final poolAmount =
                          double.tryParse(_sharedPoolController.text.trim());
                      if (poolAmount != null) {
                        final poolBase =
                            _sharedPoolUnit.toBaseUnits(poolAmount);
                        final portionBase = draft.unit.toBaseUnits(n);
                        if (portionBase > poolBase) return '≤ pool';
                      }
                      return null;
                    },
                    decoration: _inputDeco('Amount'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: _buildInventoryUnitDropdown(
                    value: draft.unit,
                    onChanged: (unit) {
                      setState(() {
                        draft.unit = unit;
                        draft.syncLabelFromAmount();
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildField(
              label: 'PRICE',
              isRequired: true,
              labelStyle: _pairedFieldLabelStyle,
              child: TextFormField(
                controller: draft.priceController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  if (!_useMultipleSizes) return null;
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (double.tryParse(v.trim()) == null) return 'Invalid';
                  return null;
                },
                decoration: _inputDeco('₹ 0.00'),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Shown as “${draft.suggestedLabel()}”',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6A7774),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: _buildField(
                    label: 'SIZE',
                    isRequired: true,
                    labelStyle: _pairedFieldLabelStyle,
                    child: TextFormField(
                      controller: draft.qtyController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                      ],
                      onChanged: (_) {
                        draft.syncLabelFromAmount();
                        setState(() {});
                      },
                      validator: (v) {
                        if (!_useMultipleSizes) return null;
                        final n = double.tryParse(v?.trim() ?? '');
                        if (n == null || n <= 0) return 'Required';
                        return null;
                      },
                      decoration: _inputDeco('e.g. 250'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: _buildField(
                    label: 'UNIT',
                    isRequired: true,
                    labelStyle: _pairedFieldLabelStyle,
                    child: _buildInventoryUnitDropdown(
                      value: draft.unit,
                      onChanged: (unit) {
                        setState(() {
                          draft.unit = unit;
                          draft.syncLabelFromAmount();
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildField(
                    label: 'PRICE',
                    isRequired: true,
                    labelStyle: _pairedFieldLabelStyle,
                    child: TextFormField(
                      controller: draft.priceController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                      ],
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        if (!_useMultipleSizes) return null;
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (double.tryParse(v.trim()) == null) return 'Invalid';
                        return null;
                      },
                      decoration: _inputDeco('₹ 0.00'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildField(
                    label: 'STOCK',
                    isRequired: true,
                    labelStyle: _pairedFieldLabelStyle,
                    child: TextFormField(
                      controller: draft.stockController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      validator: (v) {
                        if (!_useMultipleSizes) return null;
                        final n = int.tryParse(v?.trim() ?? '');
                        if (n == null || n < 1) return 'Min 1';
                        return null;
                      },
                      decoration: _inputDeco('Qty'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Shown as “${draft.suggestedLabel()}”',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6A7774),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  DateTime _endOfToday() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, 23, 59);
    if (end.isAfter(now)) return end;
    return now.add(const Duration(minutes: 1));
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

    final discountError = listingDiscountValidationError(
      enabled: _discountEnabled,
      percent: _discountPercentValue,
      startsAt: _discountStartsAt,
      endsAt: _discountEndsAt,
    );
    if (discountError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(discountError)),
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
    final justToday = _showRecurringSection && _isJustToday;
    final sameDayHours = justToday && !_todayFullDay;
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

      final variants = _variantsPayloadOrNull();
      final sharedPoolAmount = _sharedPoolAmountOrNull();
      final sharedPoolUnit = _sharedPoolUnitOrNull();
      final quantity = variants != null
          ? (_variantSharedPool
              ? _sharedPoolUnit.toBaseUnits(sharedPoolAmount!)
              : (variants.first['quantity'] as int))
          : _showQuantityAvailableField
              ? int.parse(_qtyController.text.trim())
              : (_isPreorderCatalog || useRecurring)
                  ? (_isEditing && widget.existingListing!.quantity > 0
                      ? widget.existingListing!.quantity
                      : 99)
                  : int.parse(_qtyController.text.trim());
      final price = variants != null
          ? (variants.first['price'] as double)
          : double.parse(_priceController.text.trim());
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
          : (justToday ? _endOfToday() : null);

      final (weightValue, weightUnit) = _weightFieldsForApi();
      final variantLabel = _variantLabelController.text.trim();

      if (_isEditing) {
        await ApiService.updateListing(
          listingId: widget.existingListing!.id,
          name: _nameController.text.trim(),
          price: price,
          quantity: quantity,
          description: _descController.text.trim(),
          availableAt: availableAt,
          clearAvailableAt: availableAt == null && !_showUntilField,
          pickupLocation: _pickup,
          imageUrl: imageUrl,
          weightUnit: weightUnit,
          weightValue: weightValue,
          variantLabel: variantLabel.isEmpty ? '' : variantLabel,
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
          discountEnabled: _discountEnabled,
          discountPercent: _discountEnabled ? _discountPercentValue : null,
          discountStartsAt: _discountEnabled ? _discountStartsAt : null,
          discountEndsAt: _discountEnabled ? _discountEndsAt : null,
        );
      } else {
        await ApiService.createListing(
          societyId: societyId,
          name: _nameController.text.trim(),
          price: price,
          quantity: quantity,
          description: _descController.text.trim(),
          availableAt: availableAt,
          pickupLocation: _pickup,
          imageUrl: imageUrl,
          weightUnit: weightUnit,
          weightValue: weightValue,
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
          variants: variants,
          variantInventoryMode:
              variants != null ? _variantInventoryMode : null,
          sharedPoolQuantity: sharedPoolAmount,
          sharedPoolUnit: sharedPoolUnit,
          discountEnabled: _discountEnabled,
          discountPercent: _discountEnabled ? _discountPercentValue : null,
          discountStartsAt: _discountEnabled ? _discountStartsAt : null,
          discountEndsAt: _discountEnabled ? _discountEndsAt : null,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing
              ? 'Listing updated successfully!'
              : 'Saved as draft. Publish it from My Listings when you are ready.'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: const Color(0xFF0E5A47),
        ),
      );
      if (_isEditing || _isPreorderCatalog) {
        // Pre-order catalog creates should return to the parent flow so the
        // seller can add more items / attach them to a campaign.
        MyListingsCache.clear();
        Navigator.pop(context, true);
      } else {
        ListingPublishNavigation.completeNewListing(context);
      }
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
                      if (_showMultipleSizes) ...[
                        const SizedBox(height: 18),
                        _buildMultipleSizesSection(),
                      ],
                      if (!_useMultipleSizes) ...[
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
                            onChanged: (_) => setState(() {}),
                            validator: (v) {
                              if (_useMultipleSizes) return null;
                              if (v == null || v.trim().isEmpty) {
                                return 'Required';
                              }
                              if (double.tryParse(v) == null) {
                                return 'Invalid price';
                              }
                              return null;
                            },
                            decoration: _inputDeco('₹ 0.00'),
                          ),
                        ),
                      ],
                      if (_isEditing) ...[
                        const SizedBox(height: 18),
                        _buildField(
                          label: 'SIZE LABEL (OPTIONAL)',
                          child: TextFormField(
                            controller: _variantLabelController,
                            decoration: _inputDeco('e.g. 250 g'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      _buildDiscountSection(),
                      if (_showRecurringSection) ...[
                        const SizedBox(height: 18),
                        _buildRecurringSection(),
                      ],
                      if (_showQuantityAvailableField && !_useMultipleSizes) ...[
                        const SizedBox(height: 18),
                        _buildField(
                          label: 'PORTIONS AVAILABLE',
                          isRequired: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextFormField(
                                key: const Key('listing-portions-available'),
                                controller: _qtyController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                validator: (v) {
                                  if (_useMultipleSizes) return null;
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Required';
                                  }
                                  final n = int.tryParse(v.trim());
                                  if (n == null || n < 1) {
                                    return 'Enter at least 1';
                                  }
                                  return null;
                                },
                                decoration: _inputDeco(
                                  _isEditing
                                      ? 'How many portions you can take now'
                                      : 'e.g. 10',
                                ),
                              ),
                              if (_isMadeToOrder) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Counts down as neighbors order. Update anytime '
                                  'if you can take more or need to pause new orders.',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: Color(0xFF6A7774),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      if (_showWeightAndUnitFields && !_useMultipleSizes) ...[
                        const SizedBox(height: 18),
                        _buildWeightAndUnitRow(),
                      ],
                      if (_showStockAndExpiryFields) ...[
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
                      ],
                      const SizedBox(height: 18),
                      _buildField(
                        label: 'PICKUP LOCATION - For BUYER PICKUP',
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
      maxWidth: webSellerContentMaxWidth,
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

  Future<void> _pickDiscountDate({required bool start}) async {
    final current = start ? _discountStartsAt : _discountEndsAt;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstDate = !start && _discountStartsAt != null
        ? _discountStartsAt!
        : DateTime(today.year - 1);
    var initial = current ?? today;
    if (initial.isBefore(firstDate)) initial = firstDate;
    final lastDate = DateTime(today.year + 5);
    if (initial.isAfter(lastDate)) initial = lastDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked == null || !mounted) return;
    setState(() {
      final day = listingDiscountCalendarDate(picked);
      if (start) {
        _discountStartsAt = day;
        if (_discountEndsAt != null &&
            listingDiscountCalendarDate(_discountEndsAt!).isBefore(day)) {
          _discountEndsAt = null;
        }
      } else {
        _discountEndsAt = day;
      }
    });
  }

  Widget _buildDiscountSection() {
    final percent = _discountPercentValue;
    final regular = _discountPreviewRegularPrice;
    final previewValid = _discountEnabled &&
        listingDiscountPercentIsAllowed(percent) &&
        regular != null &&
        regular > 0;
    final effective = previewValid
        ? listingDiscountEffectivePrice(regular, percent!)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          key: const Key('listing-discount-toggle'),
          contentPadding: EdgeInsets.zero,
          title: const Text(
            listingDiscountToggleLabel,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101617),
            ),
          ),
          subtitle: const Text(
            'Optional percentage off the regular price. The regular price stays the same.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF6A7774),
              height: 1.35,
            ),
          ),
          value: _discountEnabled,
          activeColor: const Color(0xFF0E5A47),
          onChanged: (value) => setState(() => _discountEnabled = value),
        ),
        if (_discountEnabled) ...[
          if (_discountAppliesToVariantGroup) ...[
            const SizedBox(height: 4),
            Text(
              listingDiscountVariantGroupHint,
              key: const Key('listing-discount-variant-note'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0E5A47),
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _buildField(
            label: 'DISCOUNT PERCENT',
            isRequired: true,
            child: TextFormField(
              key: const Key('listing-discount-percent'),
              controller: _discountPercentController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              validator: (value) {
                if (!_discountEnabled) return null;
                final parsed = int.tryParse(value?.trim() ?? '');
                if (!listingDiscountPercentIsAllowed(parsed)) {
                  return listingDiscountPercentRangeError;
                }
                return null;
              },
              decoration: _inputDeco('e.g. 10'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            listingDiscountUnboundedHint,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6A7774),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildDiscountDateButton(
                  key: const Key('listing-discount-start'),
                  label: 'Start date',
                  value: _discountStartsAt,
                  onTap: () => _pickDiscountDate(start: true),
                  onClear: _discountStartsAt == null
                      ? null
                      : () => setState(() => _discountStartsAt = null),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDiscountDateButton(
                  key: const Key('listing-discount-end'),
                  label: 'End date',
                  value: _discountEndsAt,
                  onTap: () => _pickDiscountDate(start: false),
                  onClear: _discountEndsAt == null
                      ? null
                      : () => setState(() => _discountEndsAt = null),
                ),
              ),
            ],
          ),
          if (effective != null) ...[
            const SizedBox(height: 12),
            Text(
              'Regular price ${formatRupee(regular!)} · Neighbors pay ${formatRupee(effective)}',
              key: const Key('listing-discount-preview'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0E5A47),
                height: 1.35,
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildDiscountDateButton({
    required Key key,
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: _pairedFieldLabelStyle.copyWith(color: const Color(0xFF6A7774)),
        ),
        const SizedBox(height: 6),
        InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: InputDecorator(
            decoration: _inputDeco('Optional'),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value == null ? 'None' : formatCouponDate(value),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: value == null
                          ? const Color(0xFFADB5B2)
                          : const Color(0xFF101617),
                    ),
                  ),
                ),
                if (onClear != null)
                  GestureDetector(
                    onTap: onClear,
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: Color(0xFF6A7774),
                    ),
                  )
                else
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 16,
                    color: Color(0xFF6A7774),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildField({
    required String label,
    required Widget child,
    bool isRequired = false,
    TextStyle? labelStyle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RequiredFieldLabel(
          label,
          required: isRequired,
          style: labelStyle ?? requiredFieldLabelStyle,
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

class _TodayWindowChoice extends StatelessWidget {
  const _TodayWindowChoice({
    super.key,
    required this.selected,
    required this.title,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFE8F5EE) : const Color(0xFFF7F9F8),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xFF0E5A47)
                  : const Color(0xFFE0E5E3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 18,
                color: selected
                    ? const Color(0xFF0E5A47)
                    : const Color(0xFF8A9491),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? const Color(0xFF0E5A47)
                        : const Color(0xFF101617),
                  ),
                ),
              ),
            ],
          ),
        ),
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
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFE8F5EE) : Colors.white,
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

class _ListingVariantDraft {
  _ListingVariantDraft({
    String label = '',
    String price = '',
    String qty = '1',
    String stock = '1',
    InventoryUnit unit = InventoryUnit.grams,
  })  : labelController = TextEditingController(text: label),
        priceController = TextEditingController(text: price),
        qtyController = TextEditingController(text: qty),
        stockController = TextEditingController(text: stock),
        unit = unit;

  final TextEditingController labelController;
  final TextEditingController priceController;
  /// Size amount (250) when using unit dropdown; SHARED portion amount.
  final TextEditingController qtyController;
  /// SEPARATE mode only: how many of this size are in stock.
  final TextEditingController stockController;
  InventoryUnit unit;

  String suggestedLabel() {
    final amount = num.tryParse(qtyController.text.trim());
    if (amount == null || amount <= 0) return unit.shortLabel;
    return unit.formatLabel(amount);
  }

  void syncLabelFromAmount() {
    labelController.text = suggestedLabel();
  }

  void dispose() {
    labelController.dispose();
    priceController.dispose();
    qtyController.dispose();
    stockController.dispose();
  }
}

class _VariantModeTile extends StatelessWidget {
  const _VariantModeTile({
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
      color: selected ? const Color(0xFFE8F5EE) : const Color(0xFFF5F7F6),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected
                    ? const Color(0xFF0E5A47)
                    : const Color(0xFF8A9491),
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Color(0xFF101617),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
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

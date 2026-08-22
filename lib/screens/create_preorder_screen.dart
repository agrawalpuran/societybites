import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/data.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../widgets/app_header.dart';
import '../widgets/preorder_widgets.dart';
import 'preorder_detail_screen.dart';

class CreatePreOrderScreen extends StatefulWidget {
  const CreatePreOrderScreen({
    super.key,
    this.campaign,
    this.hasOrders = false,
  });

  final PreOrderCampaign? campaign;
  final bool hasOrders;

  @override
  State<CreatePreOrderScreen> createState() => _CreatePreOrderScreenState();
}

class _CreatePreOrderScreenState extends State<CreatePreOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _deliveryCharge = TextEditingController(text: '0');
  final _fulfilmentNotes = TextEditingController();
  DateTime? _opensAt;
  DateTime? _cutoffAt;
  DateTime? _fulfilmentAt;
  bool _pickup = true;
  bool _sellerDelivery = false;
  bool _submitting = false;
  Uint8List? _coverImageBytes;
  String? _existingCoverImageUrl;
  bool _coverImageRemoved = false;
  String _coverImageMime = 'image/jpeg';
  final ImagePicker _imagePicker = ImagePicker();

  bool get _isEditing => widget.campaign != null;
  bool get _settingsLocked => _isEditing && widget.hasOrders;

  @override
  void initState() {
    super.initState();
    final campaign = widget.campaign;
    if (campaign == null) return;
    _title.text = campaign.title;
    _description.text = campaign.description ?? '';
    _fulfilmentNotes.text = campaign.fulfilmentNotes ?? '';
    _deliveryCharge.text = campaign.defaultDeliveryCharge.toStringAsFixed(
      campaign.defaultDeliveryCharge % 1 == 0 ? 0 : 2,
    );
    _opensAt = campaign.orderOpenAt;
    _cutoffAt = campaign.orderCutoffAt;
    _fulfilmentAt = campaign.fulfilmentAt;
    _pickup = campaign.offeredFulfilmentMethods.contains('pickup');
    _sellerDelivery = campaign.offeredFulfilmentMethods.contains(
      'seller_delivery',
    );
    _existingCoverImageUrl = campaign.coverImageUrl;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _deliveryCharge.dispose();
    _fulfilmentNotes.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime? current) async {
    final now = DateTime.now();
    final initial = current ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 180)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickCoverImage() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _coverImageBytes = bytes;
      _coverImageMime = file.mimeType ?? 'image/jpeg';
      _coverImageRemoved = false;
    });
  }

  void _removeCoverImage() {
    setState(() {
      _coverImageBytes = null;
      _existingCoverImageUrl = null;
      _coverImageRemoved = true;
    });
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    if (_opensAt == null || _cutoffAt == null || _fulfilmentAt == null) {
      _show('Choose the opening, cutoff, and fulfilment date/time.');
      return;
    }
    if (!_opensAt!.isBefore(_cutoffAt!) ||
        !_cutoffAt!.isBefore(_fulfilmentAt!)) {
      _show(
        'Order opening must be before cutoff, and cutoff before fulfilment.',
      );
      return;
    }
    if (!_pickup && !_sellerDelivery) {
      _show('Select at least one fulfilment method.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final description = _description.text.trim();
      final note = _fulfilmentNotes.text.trim();
      String? coverImageUrl;
      if (_coverImageBytes != null) {
        coverImageUrl = await ApiService.uploadListingImage(
          bytes: _coverImageBytes!,
          mimeType: _coverImageMime,
        );
      }
      if (_isEditing) {
        await ApiService.updatePreOrderCampaign(
          id: widget.campaign!.id,
          title: _settingsLocked ? null : _title.text.trim(),
          description: description,
          fulfilmentNotes: note,
          coverImageUrl: coverImageUrl,
          clearCoverImage: _coverImageRemoved,
          orderOpenAt: _settingsLocked ? null : _opensAt,
          orderCutoffAt: _settingsLocked ? null : _cutoffAt,
          fulfilmentAt: _settingsLocked ? null : _fulfilmentAt,
          offeredFulfilmentMethods: _settingsLocked
              ? null
              : [if (_pickup) 'pickup', if (_sellerDelivery) 'seller_delivery'],
          defaultDeliveryCharge: _settingsLocked
              ? null
              : (_sellerDelivery
                    ? double.tryParse(_deliveryCharge.text.trim()) ?? 0
                    : 0),
        );
        if (mounted) Navigator.pop(context, true);
        return;
      }
      final raw = await ApiService.createPreOrderCampaign(
        title: _title.text.trim(),
        description: description,
        fulfilmentNotes: note,
        orderOpenAt: _opensAt!,
        orderCutoffAt: _cutoffAt!,
        fulfilmentAt: _fulfilmentAt!,
        offeredFulfilmentMethods: [
          if (_pickup) 'pickup',
          if (_sellerDelivery) 'seller_delivery',
        ],
        defaultDeliveryCharge: _sellerDelivery
            ? double.tryParse(_deliveryCharge.text.trim()) ?? 0
            : 0,
        coverImageUrl: coverImageUrl,
      );
      if (!mounted) return;
      final campaign = PreOrderCampaign.fromJson(raw);
      final changed = await Navigator.pushReplacement<bool, bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PreOrderDetailScreen(
            campaignId: campaign.id,
            promptToAddProduct: true,
          ),
        ),
        result: true,
      );
      if (mounted && changed == true) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _show(cleanApiError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: preorderBackground,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              padding: const EdgeInsets.fromLTRB(4, 10, 20, 0),
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isEditing
                                ? 'Edit pre-order campaign'
                                : 'Create pre-order',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: preorderText,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _isEditing
                                ? 'Update the campaign details buyers will see.'
                                : 'Set the ordering window first. You can add products next.',
                            style: const TextStyle(
                              color: preorderMuted,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (_settingsLocked) ...[
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF5EE),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFFFE0CC),
                                ),
                              ),
                              child: const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.lock_outline_rounded,
                                    color: Color(0xFF9A6847),
                                    size: 19,
                                  ),
                                  SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      'Some campaign settings are locked because buyers have already placed orders. '
                                      'You can still change the description, fulfilment notes, and cover image.',
                                      style: TextStyle(
                                        color: Color(0xFF7A5A42),
                                        height: 1.35,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          _buildCoverImageInput(),
                          const SizedBox(height: 24),
                          _label('CAMPAIGN TITLE'),
                          TextFormField(
                            controller: _title,
                            enabled: !_settingsLocked,
                            decoration: _input('e.g. Friday Evening Specials'),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Campaign title is required'
                                : null,
                          ),
                          const SizedBox(height: 18),
                          _label('DESCRIPTION (OPTIONAL)'),
                          TextFormField(
                            controller: _description,
                            maxLines: 3,
                            decoration: _input('What are you preparing?'),
                          ),
                          const SizedBox(height: 18),
                          _dateField('ORDER OPENS', _opensAt, () async {
                            final value = await _pickDateTime(_opensAt);
                            if (value != null) setState(() => _opensAt = value);
                          }, enabled: !_settingsLocked),
                          const SizedBox(height: 14),
                          _dateField('ORDER CUTOFF', _cutoffAt, () async {
                            final value = await _pickDateTime(_cutoffAt);
                            if (value != null) {
                              setState(() => _cutoffAt = value);
                            }
                          }, enabled: !_settingsLocked),
                          const SizedBox(height: 14),
                          _dateField(
                            'FULFILMENT DATE & TIME',
                            _fulfilmentAt,
                            () async {
                              final value = await _pickDateTime(_fulfilmentAt);
                              if (value != null) {
                                setState(() => _fulfilmentAt = value);
                              }
                            },
                            enabled: !_settingsLocked,
                          ),
                          const SizedBox(height: 22),
                          _label('FULFILMENT METHOD'),
                          CheckboxListTile(
                            value: _pickup,
                            onChanged: _settingsLocked
                                ? null
                                : (v) => setState(() => _pickup = v == true),
                            title: const Text(
                              'Pickup',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: preorderGreen,
                            contentPadding: EdgeInsets.zero,
                          ),
                          CheckboxListTile(
                            value: _sellerDelivery,
                            onChanged: _settingsLocked
                                ? null
                                : (v) => setState(
                                    () => _sellerDelivery = v == true,
                                  ),
                            title: const Text(
                              'Seller-arranged delivery',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: const Text(
                              'You coordinate delivery directly with the buyer.',
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: preorderGreen,
                            contentPadding: EdgeInsets.zero,
                          ),
                          if (_sellerDelivery) ...[
                            const SizedBox(height: 8),
                            _label('DEFAULT DELIVERY CHARGE PER SELLER ORDER'),
                            TextFormField(
                              controller: _deliveryCharge,
                              enabled: !_settingsLocked,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[\d.]'),
                                ),
                              ],
                              decoration: _input('₹ 0'),
                              validator: (value) {
                                if (!_sellerDelivery) return null;
                                final amount = double.tryParse(
                                  value?.trim() ?? '',
                                );
                                if (amount == null || amount < 0) {
                                  return 'Enter a valid delivery charge';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Charged once per seller order, not per product.',
                              style: TextStyle(
                                color: preorderMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          _label('ADDITIONAL FULFILMENT NOTES (OPTIONAL)'),
                          TextFormField(
                            controller: _fulfilmentNotes,
                            maxLines: 3,
                            decoration: _input(
                              'Pickup location, delivery coordination, or timing notes',
                            ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF5EE),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFFFE0CC),
                              ),
                            ),
                            child: const Text(
                              'SocietyBites does not currently provide delivery services. '
                              'Pickup or seller-arranged delivery is coordinated directly '
                              'with the seller.',
                              style: TextStyle(
                                color: Color(0xFF7A5A42),
                                fontSize: 13,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 26),
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              onPressed: _submitting ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: preorderGreen,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: _submitting
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      _isEditing
                                          ? 'Save campaign'
                                          : 'Create & add products',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverImageInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('CAMPAIGN COVER IMAGE (OPTIONAL)'),
        const Text(
          'Add a photo that represents this pre-order.',
          style: TextStyle(
            color: preorderMuted,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          height: 180,
          decoration: BoxDecoration(
            color: const Color(0xFFF0F2F1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE0E5E3)),
          ),
          child: _coverImageBytes == null && _existingCoverImageUrl == null
              ? InkWell(
                  onTap: _pickCoverImage,
                  borderRadius: BorderRadius.circular(20),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_a_photo_rounded,
                        color: preorderGreen,
                        size: 34,
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Upload image',
                        style: TextStyle(
                          color: preorderText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Choose from gallery',
                        style: TextStyle(color: preorderMuted, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_coverImageBytes != null)
                        Image.memory(_coverImageBytes!, fit: BoxFit.cover)
                      else
                        PreOrderCoverImage(
                          imageUrl: _existingCoverImageUrl,
                          width: double.infinity,
                          height: 180,
                          borderRadius: 20,
                        ),
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Row(
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _pickCoverImage,
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Replace'),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              onPressed: _removeCoverImage,
                              tooltip: 'Remove image',
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w800,
        color: preorderMuted,
      ),
    ),
  );

  Widget _dateField(
    String label,
    DateTime? value,
    VoidCallback onTap, {
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE0E5E3)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_month_rounded,
                    color: enabled ? preorderMuted : const Color(0xFFADB5B2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      value == null
                          ? 'Choose date and time'
                          : formatDateTime(value),
                      style: TextStyle(
                        color: !enabled
                            ? const Color(0xFF8A9491)
                            : value == null
                            ? const Color(0xFFADB5B2)
                            : preorderText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _input(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
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
      borderSide: const BorderSide(color: preorderGreen),
    ),
  );
}

class AddPreOrderProductScreen extends StatefulWidget {
  const AddPreOrderProductScreen({
    super.key,
    required this.campaignId,
    required this.existingProductNames,
    this.product,
  });

  final String campaignId;
  final Set<String> existingProductNames;
  final PreOrderProduct? product;

  @override
  State<AddPreOrderProductScreen> createState() =>
      _AddPreOrderProductScreenState();
}

class _AddPreOrderProductScreenState extends State<AddPreOrderProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _quantity = TextEditingController();
  List<FoodItem> _listings = [];
  FoodItem? _selected;
  String _mode = 'demand';
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    if (product != null) {
      _name.text = product.name;
      _price.text = product.price.toStringAsFixed(
        product.price % 1 == 0 ? 0 : 2,
      );
      _mode = product.inventoryMode;
      if (product.inventoryMode == 'limited') {
        _quantity.text = '${product.quantity}';
      }
    }
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_isEditing) {
      _loading = false;
      return;
    }
    try {
      final societyId =
          await SessionService.getSocietyId() ??
          SessionService.defaultSocietyId;
      final sellerId = await SessionService.getUserId();
      if (sellerId == null) throw Exception('Please log in again.');
      final raw = await ApiService.getListings(
        societyId: societyId,
        sellerId: sellerId,
        status: 'all',
      );
      final listings = raw
          .map(FoodItem.fromJson)
          .where(
            (item) =>
                item.status != 'inactive' &&
                !widget.existingProductNames.contains(item.name.toLowerCase()),
          )
          .toList();
      if (!mounted) return;
      setState(() {
        _listings = listings;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = cleanApiError(e);
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting ||
        !_formKey.currentState!.validate() ||
        (!_isEditing && _selected == null)) {
      return;
    }
    setState(() => _submitting = true);
    try {
      if (_isEditing) {
        await ApiService.updatePreOrderProduct(
          campaignId: widget.campaignId,
          productId: widget.product!.listingId,
          name: _name.text.trim(),
          price: double.parse(_price.text.trim()),
          inventoryMode: _mode,
          maxQuantity: _mode == 'limited'
              ? int.parse(_quantity.text.trim())
              : null,
        );
        if (mounted) Navigator.pop(context, true);
        return;
      }
      final item = _selected!;
      await ApiService.addPreOrderProduct(
        campaignId: widget.campaignId,
        name: item.name,
        price: double.parse(_price.text.trim()),
        inventoryMode: _mode,
        maxQuantity: _mode == 'limited'
            ? int.parse(_quantity.text.trim())
            : null,
        description: item.description,
        imageUrl: item.imageUrl,
        weightUnit: item.weightUnit,
        weightValue: item.weightValue,
        tags: item.tags,
        category: item.category,
        pickupLocation: item.pickupLocation,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(cleanApiError(e))));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _remove() async {
    if (!_isEditing || _submitting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove product?'),
        content: Text(
          '${widget.product!.name} will no longer be part of this campaign.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep product'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFD94F4F),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _submitting = true);
    try {
      await ApiService.deletePreOrderProduct(
        campaignId: widget.campaignId,
        productId: widget.product!.listingId,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(cleanApiError(e))));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: preorderBackground,
      appBar: AppBar(
        backgroundColor: preorderBackground,
        foregroundColor: preorderText,
        elevation: 0,
        title: Text(
          _isEditing ? 'Edit campaign product' : 'Add campaign product',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: preorderGreen))
          : _error != null
          ? Center(child: Text(_error!, textAlign: TextAlign.center))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_isEditing) ...[
                          const Text(
                            'PRODUCT NAME',
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w800,
                              color: preorderMuted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _name,
                            decoration: _input('Product name'),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Product name is required'
                                : null,
                          ),
                        ] else ...[
                          const Text(
                            'Choose one of your listings',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: preorderText,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'We copy its product details. Regular listing stock stays separate.',
                            style: TextStyle(color: preorderMuted, height: 1.4),
                          ),
                          const SizedBox(height: 16),
                          if (_listings.isEmpty)
                            const PreOrderEmptyState(
                              title: 'No products available',
                              message:
                                  'Create a regular listing first, or remove a duplicate product from this campaign.',
                            )
                          else
                            DropdownButtonFormField<FoodItem>(
                              initialValue: _selected,
                              decoration: _input('Select product'),
                              items: _listings
                                  .map(
                                    (item) => DropdownMenuItem(
                                      value: item,
                                      child: Text(item.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selected = value;
                                  _price.text =
                                      value?.price.toStringAsFixed(0) ?? '';
                                });
                              },
                              validator: (value) =>
                                  value == null ? 'Choose a product' : null,
                            ),
                        ],
                        const SizedBox(height: 18),
                        const Text(
                          'PRICE FOR THIS CAMPAIGN',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w800,
                            color: preorderMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _price,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                          ],
                          decoration: _input('₹ 0'),
                          validator: (value) {
                            final price = double.tryParse(value?.trim() ?? '');
                            return price == null || price <= 0
                                ? 'Enter a valid price'
                                : null;
                          },
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'INVENTORY',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w800,
                            color: preorderMuted,
                          ),
                        ),
                        _inventoryChoice(
                          value: 'demand',
                          title: 'Prepare based on orders',
                          subtitle: "I'll make whatever quantity is ordered.",
                        ),
                        const SizedBox(height: 10),
                        _inventoryChoice(
                          value: 'limited',
                          title: 'Limited quantity',
                          subtitle:
                              'Stop accepting this product after this quantity is reached.',
                        ),
                        if (_mode == 'limited') ...[
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _quantity,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: _input('Maximum quantity'),
                            validator: (value) {
                              if (_mode != 'limited') return null;
                              final quantity = int.tryParse(
                                value?.trim() ?? '',
                              );
                              return quantity == null || quantity < 1
                                  ? 'Enter at least 1'
                                  : null;
                            },
                          ),
                        ],
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed:
                                (!_isEditing && _listings.isEmpty) ||
                                    _submitting
                                ? null
                                : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: preorderGreen,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            child: _submitting
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : Text(
                                    _isEditing ? 'Save product' : 'Add product',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                          ),
                        ),
                        if (_isEditing) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                              onPressed: _submitting ? null : _remove,
                              icon: const Icon(Icons.delete_outline_rounded),
                              label: const Text('Remove product'),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFFD94F4F),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  InputDecoration _input(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
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
      borderSide: const BorderSide(color: preorderGreen),
    ),
  );

  Widget _inventoryChoice({
    required String value,
    required String title,
    required String subtitle,
  }) {
    final selected = _mode == value;
    return Material(
      color: selected ? const Color(0xFFF0F7F4) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => setState(() => _mode = value),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? preorderGreen : const Color(0xFFE0E5E3),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? preorderGreen : const Color(0xFF8A9491),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: preorderMuted,
                        fontSize: 13,
                        height: 1.35,
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

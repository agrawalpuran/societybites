import 'dart:js_interop';

@JS('window.__SOCIETYEATS_STOREFRONT_SLUG__')
external JSString? get _storefrontBootstrapSlug;

String? readBootstrappedKitchenSlug() {
  final raw = _storefrontBootstrapSlug?.toDart;
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  return text;
}

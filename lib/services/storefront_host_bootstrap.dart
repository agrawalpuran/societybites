import 'storefront_host_bootstrap_stub.dart'
    if (dart.library.ui_web) 'storefront_host_bootstrap_web.dart';

/// Slug parsed in [web/index.html] before Flutter boots (reliable hostname).
String? bootstrappedKitchenSlug() => readBootstrappedKitchenSlug();

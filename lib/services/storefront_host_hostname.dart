import 'storefront_host_hostname_stub.dart'
    if (dart.library.ui_web) 'storefront_host_hostname_web.dart';

String liveWebHostname() => readLiveWebHostname();

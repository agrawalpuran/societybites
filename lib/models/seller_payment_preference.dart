enum SellerPaymentPreference {
  upiOnly,
  upiAndCod,
}

const defaultSellerPaymentPreference = SellerPaymentPreference.upiAndCod;

SellerPaymentPreference parseSellerPaymentPreference(Object? value) {
  switch (value?.toString().trim().toUpperCase()) {
    case 'UPI_ONLY':
    case 'UPI-ONLY':
    case 'UPI':
      return SellerPaymentPreference.upiOnly;
    case 'UPI_AND_COD':
    case 'UPI+COD':
    case 'BOTH':
    default:
      return SellerPaymentPreference.upiAndCod;
  }
}

extension SellerPaymentPreferenceApi on SellerPaymentPreference {
  String get apiValue {
    switch (this) {
      case SellerPaymentPreference.upiOnly:
        return 'UPI_ONLY';
      case SellerPaymentPreference.upiAndCod:
        return 'UPI_AND_COD';
    }
  }

  bool get allowsCod => this == SellerPaymentPreference.upiAndCod;

  String get title {
    switch (this) {
      case SellerPaymentPreference.upiOnly:
        return 'UPI Only';
      case SellerPaymentPreference.upiAndCod:
        return 'UPI + Cash on Delivery';
    }
  }

  String get optionTitle => title;

  String get optionSubtitle {
    switch (this) {
      case SellerPaymentPreference.upiOnly:
        return 'Buyers must pay through UPI.';
      case SellerPaymentPreference.upiAndCod:
        return 'Buyers can choose either UPI or COD.';
    }
  }

  String get profileSubtitle {
    switch (this) {
      case SellerPaymentPreference.upiOnly:
        return 'Buyers must pay through UPI.';
      case SellerPaymentPreference.upiAndCod:
        return 'Buyers can choose UPI or cash on delivery.';
    }
  }
}

SellerPaymentPreference paymentPreferenceFromAuthMe(Map<String, dynamic> me) {
  return parseSellerPaymentPreference(me['paymentPreference']);
}

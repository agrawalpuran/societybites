enum SellerPaymentPreference {
  codInSocietyUpiOutside,
  upiAndCod,
  upiOnly,
}

const defaultSellerPaymentPreference =
    SellerPaymentPreference.codInSocietyUpiOutside;

SellerPaymentPreference parseSellerPaymentPreference(Object? value) {
  switch (value?.toString().trim().toUpperCase()) {
    case 'UPI_ONLY':
    case 'UPI-ONLY':
    case 'UPI':
      return SellerPaymentPreference.upiOnly;
    case 'UPI_AND_COD':
    case 'UPI+COD':
    case 'BOTH':
      return SellerPaymentPreference.upiAndCod;
    case 'COD_IN_SOCIETY_UPI_OUTSIDE':
    case 'COD_IN_SOCIETY':
    case 'COD_SOCIETY':
    case 'IN_SOCIETY_COD':
    default:
      return SellerPaymentPreference.codInSocietyUpiOutside;
  }
}

extension SellerPaymentPreferenceApi on SellerPaymentPreference {
  String get apiValue {
    switch (this) {
      case SellerPaymentPreference.upiOnly:
        return 'UPI_ONLY';
      case SellerPaymentPreference.upiAndCod:
        return 'UPI_AND_COD';
      case SellerPaymentPreference.codInSocietyUpiOutside:
        return 'COD_IN_SOCIETY_UPI_OUTSIDE';
    }
  }

  bool get allowsCod => this != SellerPaymentPreference.upiOnly;

  bool allowsCodFor({required bool sameSociety}) {
    switch (this) {
      case SellerPaymentPreference.upiOnly:
        return false;
      case SellerPaymentPreference.upiAndCod:
        return true;
      case SellerPaymentPreference.codInSocietyUpiOutside:
        return sameSociety;
    }
  }

  bool allowsUpiFor({required bool sameSociety}) {
    switch (this) {
      case SellerPaymentPreference.upiOnly:
      case SellerPaymentPreference.upiAndCod:
        return true;
      case SellerPaymentPreference.codInSocietyUpiOutside:
        return !sameSociety;
    }
  }

  String get title {
    switch (this) {
      case SellerPaymentPreference.upiOnly:
        return 'UPI Only';
      case SellerPaymentPreference.upiAndCod:
        return 'UPI + Cash on Delivery';
      case SellerPaymentPreference.codInSocietyUpiOutside:
        return 'Cash on Delivery in society, UPI outside';
    }
  }

  String get optionTitle => title;

  String get optionSubtitle {
    switch (this) {
      case SellerPaymentPreference.upiOnly:
        return 'Buyers must pay through UPI.';
      case SellerPaymentPreference.upiAndCod:
        return 'Buyers can choose either UPI or COD.';
      case SellerPaymentPreference.codInSocietyUpiOutside:
        return 'Neighbours in your society can pay cash. Buyers from other societies pay by UPI.';
    }
  }

  String get profileSubtitle {
    switch (this) {
      case SellerPaymentPreference.upiOnly:
        return 'Buyers must pay through UPI.';
      case SellerPaymentPreference.upiAndCod:
        return 'Buyers can choose UPI or cash on delivery.';
      case SellerPaymentPreference.codInSocietyUpiOutside:
        return 'COD for your society. UPI for nearby / outside buyers.';
    }
  }
}

SellerPaymentPreference paymentPreferenceFromAuthMe(Map<String, dynamic> me) {
  return parseSellerPaymentPreference(me['paymentPreference']);
}

enum UpiAccountType {
  personal,
  merchant,
}

const defaultUpiAccountType = UpiAccountType.personal;

UpiAccountType parseUpiAccountType(Object? value) {
  switch (value?.toString().trim().toUpperCase()) {
    case 'MERCHANT':
    case 'BUSINESS':
      return UpiAccountType.merchant;
    case 'PERSONAL':
    default:
      return UpiAccountType.personal;
  }
}

extension UpiAccountTypeApi on UpiAccountType {
  String get apiValue {
    switch (this) {
      case UpiAccountType.personal:
        return 'PERSONAL';
      case UpiAccountType.merchant:
        return 'MERCHANT';
    }
  }

  bool get enablesCollectIntent => this == UpiAccountType.merchant;

  String get optionTitle {
    switch (this) {
      case UpiAccountType.personal:
        return 'Personal UPI';
      case UpiAccountType.merchant:
        return 'Merchant UPI';
    }
  }

  String get optionSubtitle {
    switch (this) {
      case UpiAccountType.personal:
        return 'Your normal bank UPI ID (for example name@oksbi).';
      case UpiAccountType.merchant:
        return 'Business / merchant UPI from your bank.';
    }
  }

  String get helpText {
    switch (this) {
      case UpiAccountType.personal:
        return 'The UPI ID linked to your personal bank account, usually like name@oksbi or phone@paytm.';
      case UpiAccountType.merchant:
        return 'A business or merchant UPI ID issued by your bank for receiving business payments.';
    }
  }
}

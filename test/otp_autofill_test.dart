import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/screens/otp_screen.dart';

void main() {
  test('autofill string fills all six boxes as digits', () {
    expect(splitOtpDigits('483921'), ['4', '8', '3', '9', '2', '1']);
  });

  test('OTP with leading zeros stays a string', () {
    expect(splitOtpDigits('048321'), ['0', '4', '8', '3', '2', '1']);
    expect(splitOtpDigits('000001'), ['0', '0', '0', '0', '0', '1']);
  });

  test('non-digits are ignored and empty boxes stay empty', () {
    expect(splitOtpDigits('48-39'), ['4', '8', '3', '9', '', '']);
    expect(splitOtpDigits('4'), ['4', '', '', '', '', '']);
  });
}

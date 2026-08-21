enum AuthProvider { firebase, twoFactor }

/// Build-time authentication switch.
///
/// 2Factor is the default login mechanism. Firebase phone auth remains
/// available for a controlled fallback build with:
/// `--dart-define=AUTH_PROVIDER=firebase`
class AuthConfig {
  AuthConfig._();

  static const _rawProvider = String.fromEnvironment(
    'AUTH_PROVIDER',
    defaultValue: '2factor',
  );

  static AuthProvider get provider => _rawProvider.toLowerCase() == 'firebase'
      ? AuthProvider.firebase
      : AuthProvider.twoFactor;

  static bool get usesFirebase => provider == AuthProvider.firebase;
  static bool get usesTwoFactor => provider == AuthProvider.twoFactor;
}

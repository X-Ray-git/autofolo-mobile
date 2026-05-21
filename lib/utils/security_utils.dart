abstract final class SecurityUtils {
  static final RegExp _controlChars = RegExp(r'[\x00-\x1F\x7F]');
  static final RegExp _cookieUnsafeChars = RegExp(r'[;\r\n]');
  static const Set<String> _allowedSchemes = {'http', 'https'};

  static String normalizeCredential(String value) => value.trim();

  static bool isSafeHeaderValue(String value) {
    return value.isNotEmpty && !_controlChars.hasMatch(value);
  }

  static bool isSafeCookieValue(String value) {
    return isSafeHeaderValue(value) && !_cookieUnsafeChars.hasMatch(value);
  }

  static Uri? parseHttpUrl(String rawUrl) {
    final normalized = rawUrl.trim();
    if (normalized.isEmpty) return null;

    final uri = Uri.tryParse(normalized);
    if (uri == null) return null;

    final scheme = uri.scheme.toLowerCase();
    if (!_allowedSchemes.contains(scheme)) return null;
    if (!uri.hasAuthority || uri.host.isEmpty) return null;

    return uri;
  }
}

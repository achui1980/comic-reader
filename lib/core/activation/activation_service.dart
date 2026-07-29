import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:comic_reader/data/local/secure_store.dart';
import 'remote_activation_validator.dart';

/// Result of an activation-code verification attempt.
class ActivationResult {
  /// Whether the code was accepted and the adult scope is now unlocked.
  final bool success;

  /// Human-readable reason when [success] is false (for UI display).
  final String? error;

  const ActivationResult._(this.success, this.error);

  const ActivationResult.ok() : this._(true, null);
  const ActivationResult.fail(String error) : this._(false, error);
}

/// Verifies adult-content activation codes locally (offline) using an
/// HMAC-SHA256 signature against an app-embedded secret key.
///
/// Activation-code format (dot-separated, base64url, no padding):
///
///   `<payloadB64>.<signatureB64>`
///
/// where `payload` is a JSON object such as:
///
///   `{"scope":"adult","id":"abc123","exp":1893456000}`
///
/// - `scope` (required) must equal `adult` for the adult unlock to apply.
/// - `id`    (optional) an opaque code identifier (useful for remote revocation).
/// - `exp`   (optional) Unix epoch seconds after which the code is invalid.
///
/// The signature is `HMAC-SHA256(payloadB64, secretKey)`. Because the secret is
/// embedded in the app this is NOT unbreakable DRM — it is a lightweight gate
/// that prevents casual sharing/guessing and gives a clean seam to later move
/// verification server-side (see [RemoteActivationValidator]).
///
/// On success the ORIGINAL activation code is persisted verbatim in
/// [SecureStore] under [tokenKey]; on next launch the app re-verifies that
/// stored token to decide whether to unlock (see main.dart / hasValidUnlock).
class ActivationService {
  final SecureStore _secureStore;
  final RemoteActivationValidator? _remoteValidator;

  /// SecureStore key under which the accepted activation code is persisted.
  static const String tokenKey = 'adult_unlock_token';

  /// The scope an activation code must grant to unlock adult sources.
  static const String adultScope = 'adult';

  /// App-embedded HMAC secret. Rotating this invalidates all issued codes.
  ///
  /// NOTE: this is intentionally obfuscation-grade only. For real revocation
  /// use the remote validator seam.
  static const String _secret =
      'comic-reader::activation::v1::hmac-secret::change-me-for-release';

  ActivationService({
    required SecureStore secureStore,
    RemoteActivationValidator? remoteValidator,
  })  : _secureStore = secureStore,
        _remoteValidator = remoteValidator;

  /// Verifies [code] and, on success, persists it as the unlock token.
  ///
  /// Returns an [ActivationResult] describing success or the failure reason.
  Future<ActivationResult> verify(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      return const ActivationResult.fail('请输入激活码');
    }

    final local = verifyLocally(trimmed);
    if (!local.success) {
      return local;
    }

    // Optional remote check (revocation / server-authoritative). When no
    // remote validator is wired, this is a no-op that returns true.
    final remote = _remoteValidator;
    if (remote != null) {
      try {
        final allowed = await remote.isCodeValid(trimmed);
        if (!allowed) {
          return const ActivationResult.fail('激活码已被吊销或无效');
        }
      } catch (_) {
        // Network failure on remote check must not block an otherwise valid
        // offline code — fail open to the local result.
      }
    }

    await _secureStore.write(tokenKey, trimmed);
    return const ActivationResult.ok();
  }

  /// Pure offline signature/scope/expiry check for [code]. Does not touch
  /// storage or the network. Exposed for startup re-validation and testing.
  ActivationResult verifyLocally(String code) {
    final trimmed = code.trim();
    final parts = trimmed.split('.');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
      return const ActivationResult.fail('激活码格式不正确');
    }

    final payloadB64 = parts[0];
    final providedSig = parts[1];

    final expectedSig = _sign(payloadB64);
    if (!_constantTimeEquals(expectedSig, providedSig)) {
      return const ActivationResult.fail('激活码无效');
    }

    final Map<String, dynamic> payload;
    try {
      final jsonStr = utf8.decode(_b64Decode(payloadB64));
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, dynamic>) {
        return const ActivationResult.fail('激活码无效');
      }
      payload = decoded;
    } catch (_) {
      return const ActivationResult.fail('激活码无效');
    }

    if (payload['scope'] != adultScope) {
      return const ActivationResult.fail('激活码无效');
    }

    final exp = payload['exp'];
    if (exp is int) {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (nowSec >= exp) {
        return const ActivationResult.fail('激活码已过期');
      }
    }

    return const ActivationResult.ok();
  }

  /// Whether a previously accepted activation token is stored AND still valid.
  /// Called at startup to decide the initial adult-unlock state.
  Future<bool> hasValidUnlock() async {
    final token = await _secureStore.read(tokenKey);
    if (token == null || token.isEmpty) return false;
    final result = verifyLocally(token);
    if (!result.success) {
      // Stored token no longer valid (expired / secret rotated) — clean up.
      await _secureStore.delete(tokenKey);
      return false;
    }
    return true;
  }

  /// Clears any stored unlock token (re-locks adult sources).
  Future<void> clear() => _secureStore.delete(tokenKey);

  /// Computes the base64url (unpadded) HMAC-SHA256 signature of [payloadB64].
  String _sign(String payloadB64) {
    final hmac = Hmac(sha256, utf8.encode(_secret));
    final digest = hmac.convert(utf8.encode(payloadB64));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  /// Decodes a base64url string that may be missing padding.
  List<int> _b64Decode(String input) {
    final padded = input.padRight((input.length + 3) & ~3, '=');
    return base64Url.decode(padded);
  }

  /// Length-constant string comparison to avoid timing side channels.
  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

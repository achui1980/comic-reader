/// Seam for server-authoritative activation-code validation (revocation,
/// per-device binding, usage limits, etc.).
///
/// The default flow is fully offline (local HMAC verification in
/// `ActivationService`). When a remote validator is supplied, it runs AFTER a
/// successful local check as an additional gate. To keep offline codes usable
/// during transient network failures, `ActivationService.verify` treats a
/// thrown error from [isCodeValid] as "allow" (fail-open); an explicit `false`
/// return means the server rejected/revoked the code.
///
/// This is intentionally left unwired (no concrete implementation registered)
/// so the app ships offline-only for now, with a clean extension point.
abstract class RemoteActivationValidator {
  /// Returns whether [code] is currently accepted by the remote authority.
  ///
  /// Throw to signal a transient/network error (treated as fail-open by the
  /// caller). Return `false` to signal an authoritative rejection/revocation.
  Future<bool> isCodeValid(String code);
}

/// No-op remote validator that always accepts. Useful as an explicit default
/// or in tests; wiring this is equivalent to not wiring any validator at all.
class NoopRemoteActivationValidator implements RemoteActivationValidator {
  const NoopRemoteActivationValidator();

  @override
  Future<bool> isCodeValid(String code) async => true;
}

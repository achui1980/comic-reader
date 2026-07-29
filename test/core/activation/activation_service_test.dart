import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:comic_reader/core/activation/activation_service.dart';
import 'package:comic_reader/core/activation/remote_activation_validator.dart';
import 'package:comic_reader/data/local/secure_store.dart';

class MockSecureStore extends Mock implements SecureStore {}

class _AllowValidator implements RemoteActivationValidator {
  @override
  Future<bool> isCodeValid(String code) async => true;
}

class _RejectValidator implements RemoteActivationValidator {
  @override
  Future<bool> isCodeValid(String code) async => false;
}

class _ThrowValidator implements RemoteActivationValidator {
  @override
  Future<bool> isCodeValid(String code) async => throw Exception('network');
}

// Mirror of the app-embedded secret in ActivationService for test codegen.
const _secret =
    'comic-reader::activation::v1::hmac-secret::change-me-for-release';

String _b64url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// Builds a valid (or intentionally invalid) activation code from a payload map.
String makeCode(Map<String, dynamic> payload, {bool tamperSig = false}) {
  final payloadB64 = _b64url(utf8.encode(jsonEncode(payload)));
  final hmac = Hmac(sha256, utf8.encode(_secret));
  final sig = _b64url(hmac.convert(utf8.encode(payloadB64)).bytes);
  final finalSig = tamperSig ? '${sig}x' : sig;
  return '$payloadB64.$finalSig';
}

void main() {
  late MockSecureStore store;

  setUp(() {
    store = MockSecureStore();
    when(() => store.write(any(), any())).thenAnswer((_) async {});
    when(() => store.delete(any())).thenAnswer((_) async {});
    when(() => store.read(any())).thenAnswer((_) async => null);
  });

  ActivationService build({RemoteActivationValidator? remote}) =>
      ActivationService(secureStore: store, remoteValidator: remote);

  group('verifyLocally', () {
    test('accepts a well-signed adult code', () {
      final code = makeCode({'scope': 'adult', 'id': 'abc'});
      final r = build().verifyLocally(code);
      expect(r.success, isTrue);
      expect(r.error, isNull);
    });

    test('rejects empty / malformed format', () {
      final svc = build();
      expect(svc.verifyLocally('').success, isFalse);
      expect(svc.verifyLocally('nodot').success, isFalse);
      expect(svc.verifyLocally('a.b.c').success, isFalse);
      expect(svc.verifyLocally('.sig').success, isFalse);
      expect(svc.verifyLocally('payload.').success, isFalse);
    });

    test('rejects a tampered signature', () {
      final code = makeCode({'scope': 'adult'}, tamperSig: true);
      expect(build().verifyLocally(code).success, isFalse);
    });

    test('rejects wrong scope', () {
      final code = makeCode({'scope': 'premium'});
      final r = build().verifyLocally(code);
      expect(r.success, isFalse);
    });

    test('rejects expired code', () {
      final past = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 10;
      final code = makeCode({'scope': 'adult', 'exp': past});
      final r = build().verifyLocally(code);
      expect(r.success, isFalse);
      expect(r.error, contains('过期'));
    });

    test('accepts not-yet-expired code', () {
      final future = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
      final code = makeCode({'scope': 'adult', 'exp': future});
      expect(build().verifyLocally(code).success, isTrue);
    });
  });

  group('verify (persistence + remote)', () {
    test('persists code under tokenKey on success', () async {
      final code = makeCode({'scope': 'adult'});
      final r = await build().verify(code);
      expect(r.success, isTrue);
      verify(() => store.write(ActivationService.tokenKey, code)).called(1);
    });

    test('does not persist on local failure', () async {
      final code = makeCode({'scope': 'adult'}, tamperSig: true);
      final r = await build().verify(code);
      expect(r.success, isFalse);
      verifyNever(() => store.write(any(), any()));
    });

    test('remote reject blocks an otherwise valid code', () async {
      final code = makeCode({'scope': 'adult'});
      final r = await build(remote: _RejectValidator()).verify(code);
      expect(r.success, isFalse);
      verifyNever(() => store.write(any(), any()));
    });

    test('remote throw fails open (offline tolerance)', () async {
      final code = makeCode({'scope': 'adult'});
      final r = await build(remote: _ThrowValidator()).verify(code);
      expect(r.success, isTrue);
      verify(() => store.write(ActivationService.tokenKey, code)).called(1);
    });

    test('remote allow permits persistence', () async {
      final code = makeCode({'scope': 'adult'});
      final r = await build(remote: _AllowValidator()).verify(code);
      expect(r.success, isTrue);
    });
  });

  group('hasValidUnlock', () {
    test('false when no token stored', () async {
      when(() => store.read(ActivationService.tokenKey))
          .thenAnswer((_) async => null);
      expect(await build().hasValidUnlock(), isFalse);
    });

    test('true when stored token still valid', () async {
      final code = makeCode({'scope': 'adult'});
      when(() => store.read(ActivationService.tokenKey))
          .thenAnswer((_) async => code);
      expect(await build().hasValidUnlock(), isTrue);
    });

    test('false + cleanup when stored token invalid', () async {
      final code = makeCode({'scope': 'adult'}, tamperSig: true);
      when(() => store.read(ActivationService.tokenKey))
          .thenAnswer((_) async => code);
      expect(await build().hasValidUnlock(), isFalse);
      verify(() => store.delete(ActivationService.tokenKey)).called(1);
    });

    test('false + cleanup when stored token expired', () async {
      final past = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 10;
      final code = makeCode({'scope': 'adult', 'exp': past});
      when(() => store.read(ActivationService.tokenKey))
          .thenAnswer((_) async => code);
      expect(await build().hasValidUnlock(), isFalse);
      verify(() => store.delete(ActivationService.tokenKey)).called(1);
    });
  });
}

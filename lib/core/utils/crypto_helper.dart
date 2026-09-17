import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart' hide Key;

class CryptoHelper {
  static final CryptoHelper _instance = CryptoHelper._internal();
  factory CryptoHelper() => _instance;
  CryptoHelper._internal();

  final _storage = const FlutterSecureStorage();
  static const _keyStorageKey = 'soseng_e2ee_key';

  late Key _key;
  late Encrypter _encrypter;
  bool _isInitialized = false;

  final String _encPrefix = '[ENC:';
  final String _encSuffix = ']';

  Future<void> initialize() async {
    if (_isInitialized) return;

    // 1. 보안 저장소에서 키를 읽어옵니다.
    String? base64Key = await _storage.read(key: _keyStorageKey);

    if (base64Key == null) {
      // 2. 키가 없다면 새로 생성 (256-bit = 32 bytes)
      final secureKey = Key.fromSecureRandom(32);
      base64Key = secureKey.base64;
      await _storage.write(key: _keyStorageKey, value: base64Key);
    } else {
    }

    _key = Key.fromBase64(base64Key);
    // AES 알고리즘 세팅 (CBC 모드가 일반적으로 가장 많이 사용되며 안전함)
    _encrypter = Encrypter(AES(_key, mode: AESMode.cbc));
    _isInitialized = true;
  }

  // / 텍스트를 AES-256으로 암호화하고 [ENC:Base64...] 형태로 반환
  String encryptSensitive(String plaintext) {
    if (!_isInitialized) {
      return plaintext;
    }
    if (plaintext.isEmpty) return plaintext;

    // 매 암호화마다 새로운 랜덤 IV를 생성하여 동일 평문이라도 다른 암호문이 나오게 함
    final iv = IV.fromSecureRandom(16);
    final encrypted = _encrypter.encrypt(plaintext, iv: iv);

    // IV와 암호문을 합쳐서 Base64로 인코딩 (iv 16바이트 + 암호문)
    final combined = Uint8List.fromList([...iv.bytes, ...encrypted.bytes]);
    final base64Combined = base64Encode(combined);

    return '$_encPrefix$base64Combined$_encSuffix';
  }

  // / 텍스트에 포함된 [ENC:Base64...] 형태를 찾아 복호화하여 평문으로 치환
  String decryptText(String text) {
    if (!_isInitialized) return text;
    if (!text.contains(_encPrefix)) return text;

    // 정규식으로 [ENC:...] 패턴 추출
    final regex = RegExp(r'\[ENC:([^\]]+)\]');

    return text.replaceAllMapped(regex, (match) {
      try {
        final base64Combined = match.group(1)!.replaceAll(RegExp(r'\s+'), '');
        final combined = base64Decode(base64Combined);

        // 앞 16바이트는 IV, 나머지는 암호문
        final ivBytes = combined.sublist(0, 16);
        final encryptedBytes = combined.sublist(16);

        final iv = IV(Uint8List.fromList(ivBytes));
        final encrypted = Encrypted(Uint8List.fromList(encryptedBytes));

        final decrypted = _encrypter.decrypt(encrypted, iv: iv);
        return decrypted;
      } catch (e) {
        // 복호화에 실패하면 마스킹된 형태로 리턴 (보안 상의 이유로 원본 노출 방지)
        return '***(Decryption Error)***';
      }
    });
  }
}

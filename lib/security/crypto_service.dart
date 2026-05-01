import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/asn1.dart';

class CryptoService {
  static const _storage = FlutterSecureStorage();

  static String _normalizeAccountId(String accountId) =>
      accountId.trim().toLowerCase();

  static String _storageKey(String accountId, String keyPart) =>
      'rsa_${_normalizeAccountId(accountId)}_$keyPart';

  static String _legacyStorageKey(String keyPart) => 'rsa_$keyPart';

  // generate RSA key pair
  static AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> generateRSAKeyPair() {
    final keyGen = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
          _getSecureRandom(),
        ),
      );

    final pair = keyGen.generateKeyPair();
    return AsymmetricKeyPair(
      pair.publicKey as RSAPublicKey,
      pair.privateKey as RSAPrivateKey,
    );
  }

  static SecureRandom _getSecureRandom() {
    final secureRandom = FortunaRandom();
    final random = Random.secure();
    final seeds = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }

  // save private key to secure space
  static Future<void> savePrivateKey(
    RSAPrivateKey privateKey, {
    required String accountId,
  }) async {
    await _storage.write(
      key: _storageKey(accountId, 'n'),
      value: privateKey.modulus.toString(),
    );
    await _storage.write(
      key: _storageKey(accountId, 'd'),
      value: privateKey.privateExponent.toString(),
    );
    await _storage.write(
      key: _storageKey(accountId, 'p'),
      value: privateKey.p.toString(),
    );
    await _storage.write(
      key: _storageKey(accountId, 'q'),
      value: privateKey.q.toString(),
    );
  }

  // send public key to server (PEM format)
  static String formatPublicKey(RSAPublicKey publicKey) {
    final domainSeq = ASN1Sequence()
      ..add(ASN1Integer(publicKey.modulus))
      ..add(ASN1Integer(publicKey.publicExponent));

    final algorithmSeq = ASN1Sequence()
      ..add(ASN1ObjectIdentifier.fromName('rsaEncryption'))
      ..add(ASN1Null());

    final subjectPublicKeyInfo = ASN1Sequence()
      ..add(algorithmSeq)
      ..add(
        ASN1BitString(stringValues: Uint8List.fromList(domainSeq.encode())),
      );

    final base64Encoded = base64.encode(subjectPublicKeyInfo.encode());

    final chunks = <String>[];
    for (var i = 0; i < base64Encoded.length; i += 64) {
      chunks.add(
        base64Encoded.substring(
          i,
          i + 64 > base64Encoded.length ? base64Encoded.length : i + 64,
        ),
      );
    }

    return "-----BEGIN PUBLIC KEY-----\n${chunks.join('\n')}\n-----END PUBLIC KEY-----";
  }

  // access private key from secure space
  static Future<RSAPrivateKey?> getPrivateKey({
    required String accountId,
  }) async {
    try {
      var n = await _storage.read(key: _storageKey(accountId, 'n'));
      var d = await _storage.read(key: _storageKey(accountId, 'd'));
      var p = await _storage.read(key: _storageKey(accountId, 'p'));
      var q = await _storage.read(key: _storageKey(accountId, 'q'));

      if (n == null || d == null || p == null || q == null) {
        n = await _storage.read(key: _legacyStorageKey('n'));
        d = await _storage.read(key: _legacyStorageKey('d'));
        p = await _storage.read(key: _legacyStorageKey('p'));
        q = await _storage.read(key: _legacyStorageKey('q'));
      }

      if (n == null || d == null || p == null || q == null) return null;

      final privateKey = RSAPrivateKey(
        BigInt.parse(n),
        BigInt.parse(d),
        BigInt.parse(p),
        BigInt.parse(q),
      );
      await savePrivateKey(privateKey, accountId: accountId);
      return privateKey;
    } catch (e) {
      return null;
    }
  }

  static Future<void> ensurePrivateKeyExists({
    required String accountId,
  }) async {
    final privateKey = await getPrivateKey(accountId: accountId);
    if (privateKey == null) {
      throw Exception(
        'Private key not found on this device. Please register this account on this device again.',
      );
    }
  }

  static Future<String> uploadPublicKey(
    String token, {
    required String accountId,
  }) async {
    final privateKey = await getPrivateKey(accountId: accountId);

    if (privateKey == null) {
      throw Exception(
        'Private key not found on this device. Please register this account on this device again.',
      );
    }

    final modulus = privateKey.modulus;
    if (modulus == null) {
      throw Exception('Stored private key is invalid');
    }
    final publicKey = RSAPublicKey(modulus, BigInt.parse('65537'));
    final publicKeyPem = formatPublicKey(publicKey);

    return publicKeyPem;
  }

  static Uint8List decryptAESKeyWithRSA(
    RSAPrivateKey privateKey,
    Uint8List encryptedKey,
  ) {
    final rsaParams = PrivateKeyParameter<RSAPrivateKey>(privateKey);
    final decryptors = [
      PKCS1Encoding(RSAEngine()),
      OAEPEncoding.withSHA1(RSAEngine()),
      OAEPEncoding.withSHA256(RSAEngine()),
    ];

    Object? lastError;
    for (final decryptor in decryptors) {
      try {
        decryptor.init(false, rsaParams);
        return decryptor.process(encryptedKey);
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception('Unable to decrypt AES key with RSA: $lastError');
  }

  static String decryptPayloadWithAES(
    Uint8List aesKey,
    Uint8List iv,
    Uint8List ciphertext,
  ) {
    // Decrypt AES (CBC mode + PKCS7 Padding)
    final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
      ..init(
        false, // decrypt
        PaddedBlockCipherParameters(
          ParametersWithIV(KeyParameter(aesKey), iv),
          null,
        ),
      );

    final decrypted = cipher.process(ciphertext);
    return utf8.decode(decrypted);
  }

  static String decryptPayloadWithAESGCM(
    Uint8List aesKey,
    Uint8List nonce,
    Uint8List ciphertext,
    Uint8List authTag,
  ) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(aesKey),
          authTag.length * 8,
          nonce,
          Uint8List(0),
        ),
      );

    final encryptedPayload = Uint8List.fromList([...ciphertext, ...authTag]);
    final decrypted = cipher.process(encryptedPayload);
    return utf8.decode(decrypted);
  }

  /// RSA sign on hash
  static String signData(RSAPrivateKey privateKey, String plaintext) {
    final pssSigner = PSSSigner(
      RSAEngine(),          
      SHA256Digest(),      
      SHA256Digest()               
    );

    pssSigner.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));

    final sig = pssSigner.generateSignature(
      Uint8List.fromList(utf8.encode(plaintext)),
    );

    return base64Encode(sig.bytes);
  }

  // hash for verify integrity
  static String getHashHex(String plaintext) {
    final hash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(plaintext)),
    );
    return hash.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}

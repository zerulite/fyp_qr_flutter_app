import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/asn1.dart';

class CryptoService {
  static const _storage = FlutterSecureStorage();

  // generate RSA key pair
  static AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> generateRSAKeyPair() {
    final keyGen = RSAKeyGenerator()
      ..init(ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
        _getSecureRandom(),
      ));

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
  static Future<void> savePrivateKey(RSAPrivateKey privateKey) async {
    await _storage.write(key: 'rsa_n', value: privateKey.modulus.toString());
    await _storage.write(key: 'rsa_d', value: privateKey.privateExponent.toString());
    await _storage.write(key: 'rsa_p', value: privateKey.p.toString());
    await _storage.write(key: 'rsa_q', value: privateKey.q.toString());
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
      ..add(ASN1BitString(stringValues: Uint8List.fromList(domainSeq.encode())));

    final base64Encoded = base64.encode(subjectPublicKeyInfo.encode());
    
    final chunks = <String>[];
    for (var i = 0; i < base64Encoded.length; i += 64) {
      chunks.add(base64Encoded.substring(i, i + 64 > base64Encoded.length ? base64Encoded.length : i + 64));
    }
    
    return "-----BEGIN PUBLIC KEY-----\n${chunks.join('\n')}\n-----END PUBLIC KEY-----";
  }

  // access private key from secure space
  static Future<RSAPrivateKey?> getPrivateKey() async {
    try {
      final n = await _storage.read(key: 'rsa_n');
      final d = await _storage.read(key: 'rsa_d');
      final p = await _storage.read(key: 'rsa_p');
      final q = await _storage.read(key: 'rsa_q');

      if (n == null || d == null || p == null || q == null) return null;

      return RSAPrivateKey(
        BigInt.parse(n),
        BigInt.parse(d),
        BigInt.parse(p),
        BigInt.parse(q),
      );
    } catch (e) {
      return null;
    }
  }


  static Uint8List decryptAESKeyWithRSA(RSAPrivateKey privateKey, Uint8List encryptedKey) {
    final engine = PKCS1Encoding(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    return engine.process(encryptedKey);
  }

  static String decryptPayloadWithAES(Uint8List aesKey, Uint8List iv, Uint8List ciphertext) {
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

  /// RSA sign on hash
  static String signData(RSAPrivateKey privateKey, String plaintext) {
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201'); // SHA-256 OID
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    
    final sig = signer.generateSignature(Uint8List.fromList(utf8.encode(plaintext)));
    return base64Encode(sig.bytes);
  }

  // hash for verify integrity
  static String getHash(String plaintext) {
    final hash = SHA256Digest().process(Uint8List.fromList(utf8.encode(plaintext)));
    return base64Encode(hash);
  }
}


import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:asn1lib/asn1lib.dart';
import 'package:pointycastle/asymmetric/api.dart'; // ✅ Correct import for RSAPublicKey

class EncryptionUtils {
  static const String _encryptionHeader = 'ENCPDF01';
  static const int _version = 1;
  static const int _keySize = 256; // bits
  static const int _ivSize = 16; // bytes

  static Uint8List generateAESKey() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(_keySize ~/ 8, (_) => random.nextInt(256)),
    );
  }

  static Uint8List generateIV() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(_ivSize, (_) => random.nextInt(256)),
    );
  }

  static bool validatePemFile(String pemContent) {
    return pemContent.contains('-----BEGIN PUBLIC KEY-----') &&
        pemContent.contains('-----END PUBLIC KEY-----');
  }

  static RSAPublicKey? extractPublicKeyFromPem(String pemContent) {
    try {
      final lines = pemContent.split('\n');
      final keyLines = lines
          .where((line) =>
              line.isNotEmpty &&
              !line.contains('BEGIN') &&
              !line.contains('END'))
          .join();

      final keyBytes = base64.decode(keyLines);
      final asn1Parser = ASN1Parser(keyBytes);
      final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
      final publicKeyBitString = topLevelSeq.elements[1] as ASN1BitString;

      // ✅ Fixed: correct getter for ASN1BitString
      final publicKeyAsn1 = ASN1Parser(publicKeyBitString.valueBytes!).nextObject();
      final publicKeySeq = publicKeyAsn1 as ASN1Sequence;

      final modulus = publicKeySeq.elements[0] as ASN1Integer;
      final exponent = publicKeySeq.elements[1] as ASN1Integer;

      return RSAPublicKey(modulus.valueAsBigInteger, exponent.valueAsBigInteger);
    } catch (e) {
      print('خطأ في استخراج المفتاح العام: $e');
      return null;
    }
  }

  static bool verifyEncryptionFile(File encryptedFile) {
    try {
      final bytes = encryptedFile.readAsBytesSync();
      if (bytes.length < 8) return false;
      final header = String.fromCharCodes(bytes.sublist(0, 8));
      return header == _encryptionHeader;
    } catch (e) {
      print('خطأ في التحقق من الملف: $e');
      return false;
    }
  }

  static Map<String, dynamic>? getEncryptionFileMetadata(File encryptedFile) {
    try {
      final bytes = encryptedFile.readAsBytesSync();
      if (bytes.length < 20) return null;
      final header = String.fromCharCodes(bytes.sublist(0, 8));
      if (header != _encryptionHeader) return null;
      final version = _bytesToInt(bytes.sublist(8, 12));
      final wrappedKeyLength = _bytesToInt(bytes.sublist(12, 16));
      final consumedFlag = bytes[16 + wrappedKeyLength];
      return {
        'header': header,
        'version': version,
        'wrappedKeyLength': wrappedKeyLength,
        'consumed': consumedFlag == 1,
        'fileSize': bytes.length,
      };
    } catch (e) {
      print('خطأ في قراءة بيانات الملف: $e');
      return null;
    }
  }

  static int _bytesToInt(Uint8List bytes) {
    return ((bytes[0] << 24) |
        (bytes[1] << 16) |
        (bytes[2] << 8) |
        bytes[3]);
  }

  static String calculateFileHash(File file) {
    final bytes = file.readAsBytesSync();
    return sha256.convert(bytes).toString();
  }

  static bool validateFileBeforeEncryption(File file) {
    try {
      if (!file.existsSync()) return false;
      if (file.lengthSync() == 0) return false;
      if (file.lengthSync() > 500 * 1024 * 1024) return false;
      return true;
    } catch (e) {
      print('خطأ في التحقق من الملف: $e');
      return false;
    }
  }
}

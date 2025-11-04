import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fighter_doctors_pdf/utils/encryption_utils.dart';

List<int> _intToBytesBE(int value) =>
    [(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF];

void main() {
  group('EncryptionUtils', () {
    test('generateAESKey returns 32 random bytes', () {
      final k1 = EncryptionUtils.generateAESKey();
      final k2 = EncryptionUtils.generateAESKey();
      expect(k1.length, 32);
      expect(k2.length, 32);
      expect(k1, isNot(equals(k2))); // statistically unlikely to collide
    });

    test('generateIV returns 16 random bytes', () {
      final iv = EncryptionUtils.generateIV();
      expect(iv.length, 16);
      expect(iv.any((b) => b != 0), isTrue);
    });

    test('validatePemFile detects BEGIN/END headers', () {
      const malformed = 'MIIBIjANBg...'; // no headers
      const wellFormed = '-----BEGIN PUBLIC KEY-----\nMIIBIjANBg...\n-----END PUBLIC KEY-----\n';
      expect(EncryptionUtils.validatePemFile(malformed), isFalse);
      expect(EncryptionUtils.validatePemFile(wellFormed), isTrue);
    });

    test('verifyEncryptionFile & getEncryptionFileMetadata parse envelope', () async {
      // Envelope layout:
      // 0..7: "ENCPDF01"
      // 8..11: version (1)
      // 12..15: wrappedKeyLength (3)
      // 16..18: wrappedKey bytes
      // 19: consumed flag (1)
      final header = utf8.encode('ENCPDF01');
      final version = _intToBytesBE(1);
      final wrappedKeyLen = _intToBytesBE(3);
      final wrappedKey = [0xAA, 0xBB, 0xCC];
      final consumed = [1];
      final payload = <int>[]
        ..addAll(header)
        ..addAll(version)
        ..addAll(wrappedKeyLen)
        ..addAll(wrappedKey)
        ..addAll(consumed)
        ..addAll(List<int>.filled(8, 0));

      final tmp = File('${Directory.systemTemp.path}/enc_test.bin');
      tmp.writeAsBytesSync(Uint8List.fromList(payload));

      expect(EncryptionUtils.verifyEncryptionFile(tmp), isTrue);
      final meta = EncryptionUtils.getEncryptionFileMetadata(tmp);
      expect(meta != null, isTrue);
      expect(meta!['header'], 'ENCPDF01');
      expect(meta['version'], 1);
      expect(meta['wrappedKeyLength'], 3);
      expect(meta['consumed'], isTrue);
      expect(meta['fileSize'], payload.length);

      if (tmp.existsSync()) tmp.deleteSync();
    });

    test('calculateFileHash of "abc" matches known SHA-256', () async {
      final f = File('${Directory.systemTemp.path}/hash_abc.txt');
      f.writeAsBytesSync(utf8.encode('abc'));
      final hash = EncryptionUtils.calculateFileHash(f);
      expect(hash, 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      if (f.existsSync()) f.deleteSync();
    });

    test('validateFileBeforeEncryption basic cases', () async {
      final empty = File('${Directory.systemTemp.path}/empty.bin');
      empty.writeAsBytesSync(const <int>[]);
      expect(EncryptionUtils.validateFileBeforeEncryption(empty), isFalse);
      if (empty.existsSync()) empty.deleteSync();

      final small = File('${Directory.systemTemp.path}/small.bin');
      small.writeAsBytesSync(List<int>.generate(1024, (i) => i % 256));
      expect(EncryptionUtils.validateFileBeforeEncryption(small), isTrue);
      if (small.existsSync()) small.deleteSync();
    });
  });
}

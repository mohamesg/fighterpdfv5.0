import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class PemHandler {
  /// Save PEM content to file
  static Future<File> savePemFile(String pemContent, String fileName) async {
    try {
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (!downloadsDir.existsSync()) {
        downloadsDir.createSync(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final baseName = fileName.replaceAll('.pdf', '').replaceAll('.encryptedpdf', '');
      final pemFile = File('${downloadsDir.path}/${baseName}_$timestamp.pem');

      await pemFile.writeAsString(pemContent);
      return pemFile;
    } catch (e) {
      print('خطأ في حفظ ملف PEM: $e');
      rethrow;
    }
  }

  /// Read PEM file content
  static Future<String> readPemFile(File pemFile) async {
    try {
      if (!pemFile.existsSync()) {
        throw Exception('ملف PEM غير موجود');
      }
      return await pemFile.readAsString();
    } catch (e) {
      print('خطأ في قراءة ملف PEM: $e');
      rethrow;
    }
  }

  /// Validate PEM file format
  static bool validatePemFormat(String pemContent) {
    try {
      final lines = pemContent.trim().split('\n');
      if (lines.isEmpty) return false;

      final firstLine = lines.first.trim();
      final lastLine = lines.last.trim();

      return firstLine == '-----BEGIN PUBLIC KEY-----' &&
          lastLine == '-----END PUBLIC KEY-----' &&
          lines.length > 2;
    } catch (e) {
      return false;
    }
  }

  /// Extract key metadata from PEM file
  static Map<String, String>? extractPemMetadata(String pemContent) {
    try {
      final lines = pemContent.trim().split('\n');
      if (lines.length < 3) return null;

      // Count key lines (excluding header and footer)
      final keyLines = lines
          .where((line) =>
              line.isNotEmpty &&
              !line.contains('BEGIN') &&
              !line.contains('END'))
          .toList();

      return {
        'keyLength': keyLines.join().length.toString(),
        'lineCount': keyLines.length.toString(),
        'format': 'RSA PUBLIC KEY',
      };
    } catch (e) {
      return null;
    }
  }

  /// Create PEM backup
  static Future<File> createPemBackup(File pemFile) async {
    try {
      final content = await pemFile.readAsString();
      final appDir = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${appDir.path}/pem_backups');

      if (!backupDir.existsSync()) {
        backupDir.createSync(recursive: true);
      }

      final timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final backupFile = File('${backupDir.path}/backup_$timestamp.pem');

      await backupFile.writeAsString(content);
      return backupFile;
    } catch (e) {
      print('خطأ في إنشاء نسخة احتياطية: $e');
      rethrow;
    }
  }

  /// List all PEM backups
  static Future<List<File>> listPemBackups() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${appDir.path}/pem_backups');

      if (!backupDir.existsSync()) {
        return [];
      }

      final files = backupDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.pem'))
          .toList();

      files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      return files;
    } catch (e) {
      print('خطأ في قائمة النسخ الاحتياطية: $e');
      return [];
    }
  }

  /// Delete PEM backup
  static Future<bool> deletePemBackup(File backupFile) async {
    try {
      if (backupFile.existsSync()) {
        await backupFile.delete();
        return true;
      }
      return false;
    } catch (e) {
      print('خطأ في حذف النسخة الاحتياطية: $e');
      return false;
    }
  }

  /// Restore PEM from backup
  static Future<File> restorePemFromBackup(File backupFile) async {
    try {
      final content = await backupFile.readAsString();
      final downloadsDir = Directory('/storage/emulated/0/Download');

      if (!downloadsDir.existsSync()) {
        downloadsDir.createSync(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final restoredFile = File('${downloadsDir.path}/restored_$timestamp.pem');

      await restoredFile.writeAsString(content);
      return restoredFile;
    } catch (e) {
      print('خطأ في استعادة ملف PEM: $e');
      rethrow;
    }
  }

  /// Compare two PEM files
  static Future<bool> comparePemFiles(File file1, File file2) async {
    try {
      final content1 = await file1.readAsString();
      final content2 = await file2.readAsString();
      return content1.trim() == content2.trim();
    } catch (e) {
      print('خطأ في مقارنة ملفات PEM: $e');
      return false;
    }
  }

  /// Export PEM file with metadata
  static Future<File> exportPemWithMetadata(
    File pemFile,
    Map<String, String> metadata,
  ) async {
    try {
      final content = await pemFile.readAsString();
      final metadataStr = metadata.entries
          .map((e) => '# ${e.key}: ${e.value}')
          .join('\n');

      final fullContent = '$metadataStr\n\n$content';

      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (!downloadsDir.existsSync()) {
        downloadsDir.createSync(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final exportFile = File('${downloadsDir.path}/exported_$timestamp.pem');

      await exportFile.writeAsString(fullContent);
      return exportFile;
    } catch (e) {
      print('خطأ في تصدير ملف PEM: $e');
      rethrow;
    }
  }

  /// Validate PEM file integrity
  static Future<bool> validatePemIntegrity(File pemFile) async {
    try {
      if (!pemFile.existsSync()) return false;

      final content = await pemFile.readAsString();
      return validatePemFormat(content);
    } catch (e) {
      return false;
    }
  }

  /// Get PEM file size
  static Future<int> getPemFileSize(File pemFile) async {
    try {
      if (pemFile.existsSync()) {
        return await pemFile.length();
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  /// Get PEM file creation date
  static Future<DateTime?> getPemFileCreationDate(File pemFile) async {
    try {
      if (pemFile.existsSync()) {
        final stat = await pemFile.stat();
        return stat.modified;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

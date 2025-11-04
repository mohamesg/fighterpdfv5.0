import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:flutter_windowmanager/flutter_windowmanager.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Secure PDF Sharing',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        fontFamily: 'Arial',
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const platform = MethodChannel('com.example.fighter_doctors_pdf/crypto');
  
  String _statusMessage = 'اختر ملف PDF للعرض والمشاركة الآمنة';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      await platform.invokeMethod('ensureDeviceKey');
    } catch (e) {
      setState(() {
        _statusMessage = 'خطأ في تهيئة التطبيق: $e';
      });
    }
  }

  // فتح وتشفير PDF (للمرسل)
  Future<void> _openAndEncryptPdf() async {
    try {
      setState(() {
        _isLoading = true;
        _statusMessage = 'جاري اختيار ملف PDF...';
      });

      // اختيار ملف PDF
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'تم الإلغاء';
        });
        return;
      }

      final String originalPath = result.files.single.path!;
      setState(() {
        _statusMessage = 'جاري تشفير الملف...';
      });

      // تشفير الملف
      final Map<dynamic, dynamic> encryptionResult = 
          await platform.invokeMethod('encryptPdfForSharing', {
            'pdfPath': originalPath
          });

      final String encryptedPath = encryptionResult['encryptedPath'];
      final String pemPath = encryptionResult['pemPath'];
      final String tempDecryptedPath = encryptionResult['tempDecryptedPath'];

      setState(() {
        _isLoading = false;
        _statusMessage = 'تم التشفير بنجاح! جاري فتح الملف...';
      });

      // فتح الملف للمرسل
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SecurePdfViewer(
              pdfPath: tempDecryptedPath,
              encryptedPath: encryptedPath,
              pemPath: pemPath,
              isSender: true,
            ),
          ),
        );
      }

      // حذف الملف المؤقت بعد الإغلاق
      _deleteTempFile(tempDecryptedPath);
      
      setState(() {
        _statusMessage = 'تم إغلاق الملف وحذف النسخة المؤقتة';
      });

    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = '❌ خطأ: $e';
      });
    }
  }

  // فتح ملفات مستلمة (للمستقبل)
  Future<void> _openReceivedFiles() async {
    try {
      setState(() {
        _isLoading = true;
        _statusMessage = 'جاري اختيار الملف المشفر...';
      });

      // اختيار ملف .encryptedpdf
      FilePickerResult? encryptedResult = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['encryptedpdf'],
      );

      if (encryptedResult == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'تم الإلغاء';
        });
        return;
      }

      setState(() {
        _statusMessage = 'جاري اختيار ملف المفتاح...';
      });

      // اختيار ملف .pem
      FilePickerResult? pemResult = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pem'],
      );

      if (pemResult == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'تم الإلغاء';
        });
        return;
      }

      final String encryptedPath = encryptedResult.files.single.path!;
      final String pemPath = pemResult.files.single.path!;

      setState(() {
        _statusMessage = 'جاري فك التشفير...';
      });

      // فك التشفير
      final String decryptedPath = await platform.invokeMethod(
        'decryptReceivedPdf',
        {
          'encryptedPath': encryptedPath,
          'pemPath': pemPath,
        },
      );

      setState(() {
        _isLoading = false;
        _statusMessage = 'تم فك التشفير بنجاح';
      });

      // عرض الملف
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SecurePdfViewer(
              pdfPath: decryptedPath,
              isSender: false,
            ),
          ),
        );
      }

      // حذف الملف المؤقت
      _deleteTempFile(decryptedPath);
      
      setState(() {
        _statusMessage = 'تم إغلاق الملف وحذف النسخة المؤقتة';
      });

    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = '❌ خطأ في فك التشفير: $e';
      });
    }
  }

  Future<void> _deleteTempFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print('خطأ في حذف الملف المؤقت: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مشاركة PDF آمنة'),
        centerTitle: true,
        elevation: 2,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade50,
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // أيقونة رئيسية
                Container(
                  padding: const EdgeInsets.all(30),
                  child: Icon(
                    Icons.security,
                    size: 80,
                    color: Colors.blue.shade700,
                  ),
                ),

                // عنوان
                Text(
                  'مشاركة آمنة للملفات',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'شفّر وشارك ملفاتك بأمان تام',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 40),

                // حالة التطبيق
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade200,
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isLoading ? Icons.hourglass_empty : Icons.info_outline,
                        color: Colors.blue.shade700,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _statusMessage,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                // زر: فتح وتشفير PDF جديد
                _buildMainButton(
                  icon: Icons.picture_as_pdf,
                  title: 'فتح ملف PDF',
                  subtitle: 'سيتم تشفيره تلقائياً وإعداد ملفات المشاركة',
                  color: Colors.blue,
                  onPressed: _isLoading ? null : _openAndEncryptPdf,
                ),
                const SizedBox(height: 16),

                // زر: فتح ملفات مستلمة
                _buildMainButton(
                  icon: Icons.folder_open,
                  title: 'فتح ملف مستلم',
                  subtitle: 'اختر الملف المشفر + ملف المفتاح',
                  color: Colors.green,
                  onPressed: _isLoading ? null : _openReceivedFiles,
                ),

                // مؤشر التحميل
                if (_isLoading) ...[
                  const SizedBox(height: 30),
                  const Center(
                    child: CircularProgressIndicator(),
                  ),
                ],

                const SizedBox(height: 40),

                // معلومات إضافية
                _buildInfoCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 5,
      ),
      child: Row(
        children: [
          Icon(icon, size: 40),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, size: 20),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: Colors.amber.shade700),
              const SizedBox(width: 8),
              const Text(
                'كيف يعمل؟',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoStep('1', 'افتح ملف PDF من جهازك'),
          _buildInfoStep('2', 'سيتم تشفيره وفتحه لك تلقائياً'),
          _buildInfoStep('3', 'اضغط "مشاركة" لإرسال الملفين'),
          _buildInfoStep('4', 'المستقبل يفتح بالملفين المستلمين'),
        ],
      ),
    );
  }

  Widget _buildInfoStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.amber.shade200,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// شاشة عرض PDF الآمنة
class SecurePdfViewer extends StatefulWidget {
  final String pdfPath;
  final String? encryptedPath;
  final String? pemPath;
  final bool isSender;

  const SecurePdfViewer({
    super.key,
    required this.pdfPath,
    this.encryptedPath,
    this.pemPath,
    required this.isSender,
  });

  @override
  State<SecurePdfViewer> createState() => _SecurePdfViewerState();
}

class _SecurePdfViewerState extends State<SecurePdfViewer> {
  @override
  void initState() {
    super.initState();
    _enableSecureMode();
  }

  Future<void> _enableSecureMode() async {
    try {
      await FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);
    } catch (e) {
      print('خطأ في تفعيل الوضع الآمن: $e');
    }
  }

  @override
  void dispose() {
    FlutterWindowManager.clearFlags(FlutterWindowManager.FLAG_SECURE);
    super.dispose();
  }

  Future<void> _shareEncryptedFiles() async {
    if (widget.encryptedPath == null || widget.pemPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد ملفات للمشاركة')),
      );
      return;
    }

    try {
      final encryptedFile = XFile(widget.encryptedPath!);
      final pemFile = XFile(widget.pemPath!);

      await SharePlus.instance.share(files: [XFile(encryptedFile.path), XFile(pemFile.path)],
        subject: 'ملف PDF مشفر',
        text: 'ملف PDF مشفر آمن. احتاج الملفين لفتحه.',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إرسال الملفات بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في المشاركة: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isSender ? 'معاينة الملف' : 'عرض الملف'),
        backgroundColor: widget.isSender ? Colors.blue.shade700 : Colors.green.shade700,
        actions: widget.isSender
            ? [
                IconButton(
                  icon: const Icon(Icons.share),
                  tooltip: 'مشاركة الملف المشفر',
                  onPressed: _shareEncryptedFiles,
                ),
              ]
            : null,
      ),
      body: Column(
        children: [
          // بانر تحذيري
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: widget.isSender ? Colors.blue.shade100 : Colors.green.shade100,
            child: Row(
              children: [
                Icon(
                  Icons.shield,
                  color: widget.isSender ? Colors.blue.shade700 : Colors.green.shade700,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.isSender
                        ? '🔒 الملف محمي من التصوير. اضغط "مشاركة" لإرسال الملفات المشفرة.'
                        : '🔒 الملف محمي من التصوير والنسخ',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          
          // عارض الـ PDF
          Expanded(
            child: SfPdfViewer.file(
              File(widget.pdfPath),
              canShowScrollHead: false,
              canShowScrollStatus: false,
              enableDoubleTapZooming: true,
            ),
          ),
        ],
      ),
    );
  }
}

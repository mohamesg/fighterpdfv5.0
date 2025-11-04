import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:flutter_windowmanager/flutter_windowmanager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_pdf_annotations/flutter_pdf_annotations.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Editor & Secure Sharing',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        fontFamily: 'Arial',
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.blue.shade700,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: ChangeNotifierProvider(
        create: (_) => PdfEditorProvider(),
        child: const HomePage(),
      ),
    );
  }
}

class PdfEditorProvider extends ChangeNotifier {
  String _statusMessage = 'اختر ملف PDF للتحرير والمشاركة الآمنة';
  bool _isLoading = false;
  String? _currentPdfPath;
  String? _encryptedPath;
  String? _pemPath;

  String get statusMessage => _statusMessage;
  bool get isLoading => _isLoading;
  String? get currentPdfPath => _currentPdfPath;
  String? get encryptedPath => _encryptedPath;
  String? get pemPath => _pemPath;

  void setStatus(String message) {
    _statusMessage = message;
    notifyListeners();
  }

  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void setPdfPath(String? path) {
    _currentPdfPath = path;
    notifyListeners();
  }

  void setEncryptedPaths(String encrypted, String pem) {
    _encryptedPath = encrypted;
    _pemPath = pem;
    notifyListeners();
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const platform = MethodChannel('com.example.fighter_doctors_pdf/crypto');

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      await platform.invokeMethod('ensureDeviceKey');
    } catch (e) {
      if (mounted) {
        context.read<PdfEditorProvider>().setStatus('خطأ في تهيئة التطبيق: $e');
      }
    }
  }

  Future<void> _openAndEditPdf() async {
    final provider = context.read<PdfEditorProvider>();
    try {
      provider.setLoading(true);
      provider.setStatus('جاري اختيار ملف PDF...');

      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result == null) {
        provider.setLoading(false);
        provider.setStatus('تم الإلغاء');
        return;
      }

      final String originalPath = result.files.single.path!;
      provider.setStatus('جاري فتح محرر PDF...');

      // Open PDF editor with annotations
      String? editedPath;
      await FlutterPdfAnnotations.openPDF(
        filePath: originalPath,
        savePath: originalPath.replaceAll('.pdf', '_edited.pdf'),
        onFileSaved: (savedPath) {
          if (savedPath != null && mounted) {
            provider.setPdfPath(savedPath);
            provider.setStatus('تم تحرير الملف بنجاح');
          }
        },
      );

      if (editedPath != null && mounted) {
        provider.setPdfPath(editedPath);
        provider.setStatus('تم فتح محرر PDF');
        
        if (mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PdfEditorScreen(
                pdfPath: editedPath,
                provider: provider,
              ),
            ),
          );
        }
      }

      provider.setLoading(false);
    } catch (e) {
      provider.setLoading(false);
      provider.setStatus('❌ خطأ: $e');
    }
  }

  Future<void> _encryptAndShare() async {
    final provider = context.read<PdfEditorProvider>();
    try {
      if (provider.currentPdfPath == null) {
        provider.setStatus('الرجاء فتح ملف PDF أولاً');
        return;
      }

      provider.setLoading(true);
      provider.setStatus('جاري تشفير الملف...');

      final Map<dynamic, dynamic> encryptionResult =
          await platform.invokeMethod('encryptPdfForSharing', {
        'pdfPath': provider.currentPdfPath,
      });

      final String encryptedPath = encryptionResult['encryptedPath'];
      final String pemPath = encryptionResult['pemPath'];

      provider.setEncryptedPaths(encryptedPath, pemPath);
      provider.setLoading(false);
      provider.setStatus('تم التشفير بنجاح! جاهز للمشاركة');

      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ShareScreen(
              encryptedPath: encryptedPath,
              pemPath: pemPath,
            ),
          ),
        );
      }
    } catch (e) {
      provider.setLoading(false);
      provider.setStatus('❌ خطأ في التشفير: $e');
    }
  }

  Future<void> _openReceivedFiles() async {
    final provider = context.read<PdfEditorProvider>();
    try {
      provider.setLoading(true);
      provider.setStatus('جاري اختيار الملف المشفر...');

      FilePickerResult? encryptedResult = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['encryptedpdf'],
      );

      if (encryptedResult == null) {
        provider.setLoading(false);
        provider.setStatus('تم الإلغاء');
        return;
      }

      provider.setStatus('جاري اختيار ملف المفتاح...');

      FilePickerResult? pemResult = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pem'],
      );

      if (pemResult == null) {
        provider.setLoading(false);
        provider.setStatus('تم الإلغاء');
        return;
      }

      final String encryptedPath = encryptedResult.files.single.path!;
      final String pemPath = pemResult.files.single.path!;

      provider.setStatus('جاري فك التشفير...');

      final String decryptedPath = await platform.invokeMethod(
        'decryptReceivedPdf',
        {
          'encryptedPath': encryptedPath,
          'pemPath': pemPath,
        },
      );

      provider.setPdfPath(decryptedPath);
      provider.setLoading(false);
      provider.setStatus('تم فك التشفير بنجاح');

      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PdfViewerScreen(
              pdfPath: decryptedPath,
            ),
          ),
        );
      }
    } catch (e) {
      provider.setLoading(false);
      provider.setStatus('❌ خطأ في فك التشفير: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('محرر PDF الآمن'),
        elevation: 0,
      ),
      body: Consumer<PdfEditorProvider>(
        builder: (context, provider, _) {
          return Container(
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
                    // Logo/Icon
                    Container(
                      padding: const EdgeInsets.all(30),
                      child: Image.asset(
                        'assets/images/app_logo.png',
                        height: 100,
                        width: 100,
                      ),
                    ),

                    // Title
                    Text(
                      'محرر PDF آمن',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'حرّر وشفّر وشارك ملفاتك بأمان تام',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Status Message
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
                            provider.isLoading
                                ? Icons.hourglass_empty
                                : Icons.info_outline,
                            color: Colors.blue.shade700,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              provider.statusMessage,
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

                    // Buttons
                    _buildMainButton(
                      icon: Icons.edit,
                      title: 'تحرير ملف PDF',
                      subtitle: 'أضف تعليقات وملاحظات وارسم على الملف',
                      color: Colors.blue,
                      onPressed: provider.isLoading ? null : _openAndEditPdf,
                    ),
                    const SizedBox(height: 16),

                    _buildMainButton(
                      icon: Icons.lock,
                      title: 'تشفير وإرسال',
                      subtitle: 'شفّر الملف وأرسله بأمان',
                      color: Colors.green,
                      onPressed: provider.isLoading ? null : _encryptAndShare,
                    ),
                    const SizedBox(height: 16),

                    _buildMainButton(
                      icon: Icons.folder_open,
                      title: 'فتح ملف مستلم',
                      subtitle: 'فك تشفير الملفات المستلمة',
                      color: Colors.orange,
                      onPressed: provider.isLoading ? null : _openReceivedFiles,
                    ),

                    if (provider.isLoading) ...[
                      const SizedBox(height: 30),
                      const Center(
                        child: CircularProgressIndicator(),
                      ),
                    ],

                    const SizedBox(height: 40),

                    // Info Card
                    _buildInfoCard(),
                  ],
                ),
              ),
            ),
          );
        },
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
          _buildInfoStep('1', 'افتح ملف PDF وحرّره بإضافة ملاحظات'),
          _buildInfoStep('2', 'شفّر الملف تلقائياً بمفاتيح آمنة'),
          _buildInfoStep('3', 'شارك الملفات المشفرة بأمان'),
          _buildInfoStep('4', 'المستقبل يفك التشفير بسهولة'),
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

class PdfEditorScreen extends StatefulWidget {
  final String pdfPath;
  final PdfEditorProvider provider;

  const PdfEditorScreen({
    super.key,
    required this.pdfPath,
    required this.provider,
  });

  @override
  State<PdfEditorScreen> createState() => _PdfEditorScreenState();
}

class _PdfEditorScreenState extends State<PdfEditorScreen> {
  late PdfViewerController _pdfViewerController;

  @override
  void initState() {
    super.initState();
    _pdfViewerController = PdfViewerController();
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
    _pdfViewerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('محرر PDF'),
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.blue.shade100,
            child: Row(
              children: [
                Icon(
                  Icons.shield,
                  color: Colors.blue.shade700,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '🔒 الملف محمي من التصوير والنسخ',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SfPdfViewer.file(
              File(widget.pdfPath),
              controller: _pdfViewerController,
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

class ShareScreen extends StatelessWidget {
  final String encryptedPath;
  final String pemPath;

  const ShareScreen({
    super.key,
    required this.encryptedPath,
    required this.pemPath,
  });

  Future<void> _shareFiles() async {
    try {
      final encryptedFile = XFile(encryptedPath);
      final pemFile = XFile(pemPath);

      await SharePlus.instance.share(files: [XFile(encryptedFile.path), XFile(pemFile.path)],
        subject: 'ملف PDF مشفر آمن',
        text: 'ملف PDF مشفر بأمان. احتاج الملفين معاً لفتحه.',
      );
    } catch (e) {
      print('خطأ في المشاركة: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مشاركة الملف المشفر'),
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 80,
                color: Colors.green.shade700,
              ),
              const SizedBox(height: 20),
              const Text(
                'الملف جاهز للمشاركة',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'تم تشفير الملف بنجاح\nالآن يمكنك مشاركته بأمان',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: _shareFiles,
                icon: const Icon(Icons.share),
                label: const Text('مشاركة الملفات'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PdfViewerScreen extends StatefulWidget {
  final String pdfPath;

  const PdfViewerScreen({
    super.key,
    required this.pdfPath,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late PdfViewerController _pdfViewerController;

  @override
  void initState() {
    super.initState();
    _pdfViewerController = PdfViewerController();
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
    _pdfViewerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('عرض الملف المفكوك'),
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.green.shade100,
            child: Row(
              children: [
                Icon(
                  Icons.shield,
                  color: Colors.green.shade700,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '🔒 الملف محمي من التصوير والنسخ',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SfPdfViewer.file(
              File(widget.pdfPath),
              controller: _pdfViewerController,
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
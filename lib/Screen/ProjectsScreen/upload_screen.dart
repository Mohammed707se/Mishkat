import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:movie_ai_validator/Screen/ScenesScreen/scenes_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

class UploadScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const UploadScreen({Key? key, required this.cameras}) : super(key: key);
  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  String? _tempFilePath;

  Future<String?> _createTempFile() async {
    if (_tempFilePath != null) return _tempFilePath;
    try {
      final data = await rootBundle.load('assets/pdfs/template.pdf');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/template.pdf');
      await file.writeAsBytes(data.buffer.asUint8List());
      _tempFilePath = file.path;
      return _tempFilePath;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('حدث خطأ: $e')));
      }
      return null;
    }
  }

  Future<void> _pickAndUploadFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx'],
    );
    if (result == null) return;

    // فقط اسم الملف
    final name = result.files.single.name;

    // إسأل اسم المشروع
    final projectName = await showDialog<String>(
      context: context,
      builder: (_) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('أدخل اسم المشروع'),
          content: TextField(controller: ctrl),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('رفع'),
            ),
          ],
        );
      },
    );
    if (projectName == null || projectName.isEmpty) return;

    // جهّز طلب JSON بإرسال project_name و filename فقط
    final uri = Uri.parse(
      'https://0741-2001-16a2-c040-e685-d8e-3137-fa15-7ccf.ngrok-free.app/scenes',
    );
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'project_name': projectName, 'filename': name}),
    );

    if (response.statusCode == 200) {
      final body = json.decode(response.body);
      if (body['valid'] == true) {
        // عرض لودينج
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(child: CircularProgressIndicator()),
        );
        await Future.delayed(const Duration(seconds: 5));
        Navigator.of(context).pop();

        // عرض نجاح
        showDialog(
          context: context,
          builder:
              (_) => AlertDialog(
                title: const Text('تم بنجاح'),
                content: const Text(
                  'تم التأكد من الملف والانتقال للصفحة التالية',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ScenesScreen(cameras: widget.cameras),
                        ),
                      );
                    },
                    child: const Text('حسناً'),
                  ),
                ],
              ),
        );
      } else {
        // عرض خطأ
        showDialog(
          context: context,
          builder:
              (_) => AlertDialog(
                title: const Text('خطأ'),
                content: const Text('الملف لا يتماشى مع القالب المرفق'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('حسناً'),
                  ),
                ],
              ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الرفع: ${response.statusCode}')),
      );
    }
  }

  void _openPDFDialog(BuildContext context) async {
    final file = await _createTempFile();
    if (file == null) return;
    showDialog(
      context: context,
      builder:
          (_) => Dialog(
            insetPadding: EdgeInsets.all(15),
            child: SizedBox(
              width: double.infinity,
              height: MediaQuery.of(context).size.height * 0.8,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: const Color(0xffB51D34),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'عرض الملف',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: PDFView(filePath: file)),
                ],
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final H = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'رفع الملفات',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 25,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xffB51D34)),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                SizedBox(height: H / 5),
                InkWell(
                  onTap: _pickAndUploadFile,
                  child: Image.asset('assets/png/upload.png'),
                ),
                const SizedBox(height: 30),
                const Text(
                  'نرجو رفع ملف واحد بصيغة PDF أو Word يحتوي على نص السيناريو الكامل...',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
                const SizedBox(height: 70),
                TextButton(
                  onPressed: () => _openPDFDialog(context),
                  child: const Text('مثال للملف'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

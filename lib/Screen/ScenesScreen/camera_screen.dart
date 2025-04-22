import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:gallery_saver/gallery_saver.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';

import 'dart:io' show Platform, File, Directory;

class VideoAnalyzerScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const VideoAnalyzerScreen({Key? key, required this.cameras})
    : super(key: key);

  @override
  _VideoAnalyzerScreenState createState() => _VideoAnalyzerScreenState();
}

class _VideoAnalyzerScreenState extends State<VideoAnalyzerScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  IOWebSocketChannel? _channel;
  bool _isAnalyzing = false;
  bool _isProcessing = false;
  bool _isRecording = false;
  String _status = 'جاري طلب الوصول إلى الكاميرا والميكروفون...';
  List<String> _logs = [];
  List<Detection> _detections = [];

  Timer? _analysisTimer;

  String? _videoPath;
  bool _isFrontCamera = false;
  int _selectedCameraIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // إجبار الشاشة على الوضع الأفقي
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _initPermissionsAndCamera();
  }

  @override
  void dispose() {
    _analysisTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);

    // Safe shutdown sequence
    if (_isRecording) {
      _stopRecordingAndAnalysis();
    }

    _disconnectWebSocket();

    // Safe controller disposal
    final cameraController = _controller;
    _controller = null; // Immediately set to null to prevent access
    cameraController?.dispose();

    // Restore screen orientation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // More robust lifecycle handling
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      // Stop any active processes first
      if (_isRecording) {
        _stopRecordingAndAnalysis();
      }

      if (_isAnalyzing) {
        _analysisTimer?.cancel();
        _analysisTimer = null;
        _isAnalyzing = false;
      }

      // Dispose controller safely
      final cameraController = _controller;
      _controller = null; // Immediately set to null to prevent access
      cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      // Only reinitialize if we don't have an active controller
      if (_controller == null || !_controller!.value.isInitialized) {
        _initializeCamera(widget.cameras[_selectedCameraIndex]);
      }
    }
  }

  Future<void> _initPermissionsAndCamera() async {
    // Request camera and microphone permissions
    Map<Permission, PermissionStatus> statuses =
        await [Permission.camera, Permission.microphone].request();

    if (widget.cameras.isEmpty) {
      setState(() {
        _status = 'لا توجد كاميرات متاحة';
      });
      return;
    }

    // Setup camera only once
    await _setupCamera();
  }

  Future<void> _setupCamera() async {
    if (widget.cameras.isEmpty) {
      setState(() {
        _status = 'لا توجد كاميرات متاحة';
      });
      return;
    }

    // تفقد الكاميرات المتاحة وطباعتها في السجل للتشخيص
    _log('الكاميرات المتاحة: ${widget.cameras.length}');
    for (int i = 0; i < widget.cameras.length; i++) {
      _log(
        'كاميرا $i: ${widget.cameras[i].name}, الاتجاه: ${widget.cameras[i].lensDirection}',
      );
    }

    // استخدام الكاميرا الأولى افتراضيًا لتجنب أي أخطاء
    _selectedCameraIndex = 0;

    // محاولة العثور على الكاميرا الخلفية إذا كانت متوفرة
    for (int i = 0; i < widget.cameras.length; i++) {
      if (widget.cameras[i].lensDirection == CameraLensDirection.back) {
        _selectedCameraIndex = i;
        break;
      }
    }

    await _initializeCamera(widget.cameras[_selectedCameraIndex]);
  }

  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    if (_controller != null) {
      await _controller!.dispose();
    }

    final CameraController cameraController = CameraController(
      cameraDescription,
      ResolutionPreset.max, // استخدم دقة متوسطة لتقليل المشاكل
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.bgra8888, // مهم جدًا لأجهزة iOS
    );

    _controller = cameraController;

    try {
      await cameraController.initialize();

      if (mounted) {
        setState(() {
          _status = 'تم تشغيل الكاميرا. اضغط على زر التسجيل للبدء.';
          _isFrontCamera =
              cameraDescription.lensDirection == CameraLensDirection.front;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'خطأ في تشغيل الكاميرا: $e';
        });
      }
      print('خطأ تهيئة الكاميرا: $e');
    }
  }

  Future<void> _toggleCameraDirection() async {
    // Check if multiple cameras are available
    if (widget.cameras.length <= 1) {
      // Show message to user if no other cameras
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('لا توجد كاميرات إضافية متاحة')));
      return;
    }

    // Update UI to show switching in progress
    setState(() {
      _status = 'جاري تبديل الكاميرا...';
    });

    // Stop any active processes first
    if (_isRecording) {
      await _stopRecordingAndAnalysis();
    }

    // Calculate next camera index
    int newIndex = (_selectedCameraIndex + 1) % widget.cameras.length;

    try {
      // Safely dispose the current controller
      final oldController = _controller;
      _controller = null; // Set to null immediately to prevent access attempts

      // Wait for disposal to complete
      if (oldController != null) {
        await oldController.dispose();
      }

      // Initialize the new camera
      _selectedCameraIndex = newIndex;
      await _initializeCamera(widget.cameras[newIndex]);

      setState(() {
        _isFrontCamera =
            widget.cameras[newIndex].lensDirection == CameraLensDirection.front;
        _status = 'تم تبديل الكاميرا بنجاح';
      });
    } catch (e) {
      setState(() {
        _status = 'فشل في تبديل الكاميرا: $e';
      });
      _log('خطأ في تبديل الكاميرا: $e');
    }
  }

  Future<void> _connectWebSocket() async {
    if (_channel != null) return;
    _log('جاري الاتصال بالخادم...');
    setState(() => _status = 'جاري الاتصال بالخادم...');
    try {
      _channel = IOWebSocketChannel.connect(
        'ws://0741-2001-16a2-c040-e685-d8e-3137-fa15-7ccf.ngrok-free.app/ws/analyze_video',
      );
      _channel!.stream.listen(
        _handleServerMessage,
        onError: (e) {
          _log('خطأ في WebSocket: $e');
          setState(() => _status = 'خطأ في الاتصال بالخادم.');
          _disconnectWebSocket();
        },
        onDone: () {
          _log('تم إغلاق الاتصال بالخادم');
          setState(() => _status = 'انقطع الاتصال بالخادم.');
        },
      );
      _log('تم الاتصال بالخادم');
    } catch (e) {
      _log('فشل الاتصال: $e');
      setState(() => _status = 'فشل في الاتصال: $e');
      print(e);
      rethrow;
    }
  }

  void _disconnectWebSocket() {
    _channel?.sink.close();
    _channel = null;
  }

  Future<void> _startRecordingAndAnalysis() async {
    if (_isRecording ||
        _controller == null ||
        !_controller!.value.isInitialized)
      return;

    try {
      _log('بدء عملية التسجيل...');

      // إنشاء مسار لحفظ الفيديو
      final Directory appDir = await getTemporaryDirectory();
      final String videoDirectory = '${appDir.path}/Videos';
      await Directory(videoDirectory).create(recursive: true);
      final String filePath =
          '$videoDirectory/${DateTime.now().millisecondsSinceEpoch}.mp4';
      _videoPath = filePath;

      // بدء التحليل
      await _connectWebSocket();

      // بدء تسجيل الفيديو
      await _controller!.startVideoRecording();

      setState(() {
        _isRecording = true;
        _isAnalyzing = true;
        _status = 'جاري التسجيل والتحليل...';
      });

      // استخدام مؤقت لأخذ لقطات كل 500 ميلي ثانية وإرسالها للتحليل
      _analysisTimer = Timer.periodic(Duration(milliseconds: 500), (
        timer,
      ) async {
        if (_isAnalyzing && !_isProcessing && _channel != null) {
          _isProcessing = true;
          try {
            // التقاط صورة
            final XFile imageFile = await _controller!.takePicture();

            // قراءة الصورة وتحويلها
            final File file = File(imageFile.path);
            final Uint8List bytes = await file.readAsBytes();

            // إرسال الصورة للتحليل
            _channel!.sink.add(bytes);

            // حذف الملف المؤقت
            await file.delete();
          } catch (e) {
            _log('خطأ في إرسال الصورة للتحليل: $e');
          } finally {
            _isProcessing = false;
          }
        }
      });

      _log('تم بدء التسجيل والتحليل بنجاح');
    } catch (e) {
      _log('خطأ في بدء التسجيل: $e');
      setState(() => _status = 'خطأ في بدء التسجيل: $e');
    }
  }

  Future<void> _stopRecordingAndAnalysis() async {
    if (!_isRecording) return;

    _analysisTimer?.cancel();
    _analysisTimer = null;

    try {
      _log('إيقاف التسجيل...');

      setState(() => _isAnalyzing = false);

      // إيقاف تحليل الصور
      if (_isAnalyzing) {
        await _controller?.stopImageStream();
        setState(() => _isAnalyzing = false);
      }

      // إيقاف تسجيل الفيديو
      final XFile videoFile = await _controller!.stopVideoRecording();
      _log('تم إيقاف التسجيل: ${videoFile.path}');

      // طرق مختلفة لحفظ الفيديو حسب نظام التشغيل
      if (Platform.isIOS) {
        try {
          // على iOS، استخدم GallerySaver فقط (يعمل جيدًا مع iOS)
          final result = await GallerySaver.saveVideo(videoFile.path);
          _log('تم الحفظ على iOS: $result');
        } catch (e) {
          _log('خطأ في حفظ الفيديو على iOS: $e');

          // محاولة بديلة مع ImageGallerySaver
          try {
            final result = await ImageGallerySaver.saveFile(videoFile.path);
            _log('تم الحفظ على iOS باستخدام ImageGallerySaver: $result');
          } catch (iosError) {
            _log('فشل جميع محاولات الحفظ على iOS: $iosError');
            rethrow;
          }
        }
      } else {
        // على أندرويد، استخدم الطرق المتعددة كما كان سابقًا
        try {
          // الطريقة الأولى: استخدام GallerySaver
          await GallerySaver.saveVideo(videoFile.path);
          _log('تم الحفظ بواسطة GallerySaver');
        } catch (galleryError) {
          _log('فشل الحفظ بواسطة GallerySaver: $galleryError');

          // الطريقة الثانية: استخدام ImageGallerySaver
          try {
            final result = await ImageGallerySaver.saveFile(videoFile.path);
            _log('تم الحفظ بواسطة ImageGallerySaver: $result');
          } catch (imageGalleryError) {
            _log('فشل الحفظ بواسطة ImageGallerySaver: $imageGalleryError');

            // نسخ الملف يدويًا إلى مجلد DCIM (خاص بأندرويد فقط)
            try {
              final String dcimPath = '/storage/emulated/0/DCIM/Camera/';
              final String fileName =
                  'VID_${DateTime.now().millisecondsSinceEpoch}.mp4';

              final directory = Directory(dcimPath);
              if (!(await directory.exists())) {
                await directory.create(recursive: true);
              }
              await File(videoFile.path).copy('$dcimPath$fileName');
              _log('تم نسخ الفيديو يدويًا إلى: $dcimPath$fileName');
            } catch (copyError) {
              _log('فشل نسخ الفيديو يدويًا: $copyError');
              rethrow;
            }
          }
        }
      }

      // تحديث حالة الواجهة بعد نجاح العملية
      setState(() {
        _isRecording = false;
        _status = 'تم حفظ الفيديو بنجاح';
      });

      // عرض رسالة للمستخدم
      _showSuccessMessage('تم حفظ الفيديو بنجاح في معرض الصور');

      // إغلاق اتصال WebSocket إذا لم يعد هناك حاجة له
      if (!_isAnalyzing) {
        _disconnectWebSocket();
      }
    } catch (e) {
      _log('خطأ في إيقاف التسجيل: $e');
      setState(() {
        _isRecording = false;
        _status = 'خطأ في حفظ الفيديو: $e';
      });

      // محاولة عرض رسالة خطأ مفيدة للمستخدم
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'فشل حفظ الفيديو: يرجى التأكد من صلاحيات الوصول للصور والفيديو',
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  Future<Uint8List> _convertCameraImageToJpeg(CameraImage image) async {
    final width = image.width;
    final height = image.height;

    // 1) حالة BGRA8888 (iOS): plane واحد بصيغة BGRA
    if (Platform.isIOS) {
      // على iOS، الصورة تكون بتنسيق BGRA8888 في plane واحد
      if (image.format.group == ImageFormatGroup.bgra8888) {
        final img.Image capturedImage = img.Image.fromBytes(
          width: image.width,
          height: image.height,
          bytes: image.planes[0].bytes.buffer,
          order: img.ChannelOrder.bgra,
        );
        return Uint8List.fromList(img.encodeJpg(capturedImage, quality: 80));
      }
    }

    // 2) حالة YUV420 (Android): ثلاث planes على الأقل
    if (image.planes.length >= 3) {
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      final uvRowStride = uPlane.bytesPerRow;
      final uvPixelStride = uPlane.bytesPerPixel!;

      // أنشئ صورة فارغة للرسم بالـ RGB
      final rgbImage = img.Image(width: width, height: height);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final yp = yPlane.bytes[y * yPlane.bytesPerRow + x];
          final up =
              uPlane.bytes[(y >> 1) * uvRowStride + (x >> 1) * uvPixelStride];
          final vp =
              vPlane.bytes[(y >> 1) * uvRowStride + (x >> 1) * uvPixelStride];

          // معادلات تحويل من YUV إلى RGB
          final r = (yp + 1.370705 * (vp - 128)).clamp(0, 255).toInt();
          final g =
              (yp - 0.337633 * (up - 128) - 0.698001 * (vp - 128))
                  .clamp(0, 255)
                  .toInt();
          final b = (yp + 1.732446 * (up - 128)).clamp(0, 255).toInt();

          // ضع البيكسل مع alpha = 255
          rgbImage.setPixelRgba(x, y, r, g, b, 255);
        }
      }

      return Uint8List.fromList(img.encodeJpg(rgbImage, quality: 80));
    }

    // في حالة تنسيق غير مدعوم
    throw Exception(
      'Unsupported CameraImage format with ${image.planes.length} planes',
    );
  }

  /// يرسل الإطار للخادم لمعالجته
  Future<void> _processFrame(CameraImage frame) async {
    if (!_isAnalyzing || _isProcessing || _channel == null) return;
    _isProcessing = true;

    try {
      final jpeg = await _convertCameraImageToJpeg(frame);
      _channel!.sink.add(jpeg);
    } catch (e) {
      _log('خطأ في إرسال الإطار: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// تعالج قائمة الاكتشافات الواردة من الخادم
  void _handleDetections(List<dynamic> annotations) {
    // إذا القائمة فارغة، لا شيء لمعالجته
    if (annotations.isEmpty) return;

    for (final ann in annotations) {
      // استخراج الحقول بأمان
      final object = ann['object'] ?? 'غير معروف';
      final confidence = (ann['confidence'] ?? 0.0) as double;
      final message = ann['message'] ?? '';

      final det = Detection(
        object: object,
        confidence: confidence,
        message: message,
      );

      // أضف للاحتفاظ بالـ 20 اكتشاف الأحدث فقط
      setState(() {
        _detections.insert(0, det);
        if (_detections.length > 20) {
          _detections.removeLast();
        }
      });

      // عرض إشعار عائم للمستخدم
      _showOverlayNotification(det.object, det.confidence);
      _log('اكتشاف: $object (${(confidence * 100).toStringAsFixed(0)}%)');
    }
  }

  void _handleServerMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String);
      if (data['annotations'] != null && data['annotations'].isNotEmpty) {
        _handleDetections(data['annotations']);
      }
    } catch (e) {
      _log('خطأ في معالجة الرسالة: $e');
    }
  }

  void _showOverlayNotification(String object, double confidence) {
    final overlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: 20,
          left: 20,
          right: 20,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.red),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$object (${(confidence * 100).toStringAsFixed(0)}%)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context)!.insert(overlay);
    Future.delayed(Duration(seconds: 3), () => overlay.remove());
  }

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _log(String text) {
    final time = TimeOfDay.now().format(context);
    setState(() => _logs.add('[$time] $text'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Camera preview with safe null check
          _controller != null && _controller!.value.isInitialized
              ? _buildCameraPreview()
              : Container(
                color: Colors.black,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text(
                        _status,
                        style: TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

          // Status bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top,
                left: 16,
                right: 16,
                bottom: 8,
              ),
              color: Colors.black.withOpacity(0.5),
              child: Text(
                _status,
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),

          // Control buttons
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Camera toggle button
                FloatingActionButton(
                  heroTag: 'btn1',
                  backgroundColor: Colors.white.withOpacity(0.7),
                  child: Icon(Icons.flip_camera_ios, color: Colors.black),
                  // Disable if camera is not initialized
                  onPressed:
                      (_controller != null && _controller!.value.isInitialized)
                          ? _toggleCameraDirection
                          : null,
                ),

                SizedBox(width: 40),

                // Record/stop button
                FloatingActionButton(
                  heroTag: 'btn2',
                  backgroundColor:
                      _isRecording ? Colors.red : Colors.white.withOpacity(0.7),
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.videocam,
                    color: _isRecording ? Colors.white : Colors.red,
                    size: 36,
                  ),
                  // Disable if camera is not initialized
                  onPressed:
                      (_controller != null && _controller!.value.isInitialized)
                          ? (_isRecording
                              ? _stopRecordingAndAnalysis
                              : _startRecordingAndAnalysis)
                          : null,
                ),

                SizedBox(width: 40),

                // Detections list button
                FloatingActionButton(
                  heroTag: 'btn3',
                  backgroundColor: Colors.white.withOpacity(0.7),
                  child: Icon(Icons.list, color: Colors.black),
                  onPressed: _showDetectionsList,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    // Safety check - ensure controller exists and is initialized
    if (_controller == null || !_controller!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Text(
            'جاري تهيئة الكاميرا...',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    // Calculate correct aspect ratio
    final size = MediaQuery.of(context).size;
    final deviceRatio = size.width / size.height;
    final cameraRatio = _controller!.value.aspectRatio;

    // Calculate scale to fill screen
    double scale =
        deviceRatio < cameraRatio
            ? size.height / (size.width / cameraRatio)
            : size.width / (size.height * cameraRatio);

    return Transform.scale(
      scale: scale,
      child: Center(
        child: ValueListenableBuilder<CameraValue>(
          valueListenable: _controller!,
          builder: (context, value, child) {
            // Only render if the controller is still initialized
            if (!value.isInitialized) {
              return Container(color: Colors.black);
            }
            return CameraPreview(_controller!);
          },
        ),
      ),
    );
  }

  void _showDetectionsList() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.3,
            maxChildSize: 0.8,
            builder:
                (_, controller) => Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الاكتشافات الأخيرة',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 16),
                      Expanded(
                        child:
                            _detections.isEmpty
                                ? Center(
                                  child: Text('لا توجد اكتشافات حتى الآن'),
                                )
                                : ListView.builder(
                                  controller: controller,
                                  itemCount: _detections.length,
                                  itemBuilder: (_, i) {
                                    final det = _detections[i];
                                    return Card(
                                      margin: EdgeInsets.only(bottom: 8),
                                      child: ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: Colors.blue.shade100,
                                          child: Icon(
                                            Icons.remove_red_eye,
                                            color: Colors.blue,
                                          ),
                                        ),
                                        title: Text(det.object),
                                        subtitle: Text(det.message),
                                        trailing: Text(
                                          '${(det.confidence * 100).toStringAsFixed(0)}%',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }
}

class Detection {
  final String object;
  final double confidence;
  final String message;

  Detection({
    required this.object,
    required this.confidence,
    required this.message,
  });
}

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:movie_ai_validator/home_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

// دالة للحصول على الكاميرات مع معالجة الأخطاء
Future<List<CameraDescription>> getCameras() async {
  try {
    // محاولة الحصول على الكاميرات
    final cameras = await availableCameras();
    print('تم العثور على ${cameras.length} كاميرا');
    for (var i = 0; i < cameras.length; i++) {
      print('كاميرا $i: ${cameras[i].name}, ${cameras[i].lensDirection}');
    }
    return cameras;
  } catch (e) {
    print('خطأ في الحصول على الكاميرات: $e');

    // محاولة ثانية بعد تأخير قصير (يحل بعض المشاكل على iOS)
    await Future.delayed(Duration(milliseconds: 800));
    try {
      final cameras = await availableCameras();
      print('المحاولة الثانية: تم العثور على ${cameras.length} كاميرا');
      return cameras;
    } catch (e2) {
      print('فشل المحاولة الثانية: $e2');

      // محاولة أخيرة بعد تأخير أطول
      await Future.delayed(Duration(seconds: 2));
      try {
        return await availableCameras();
      } catch (e3) {
        print('فشلت جميع المحاولات: $e3');
        return [];
      }
    }
  }
}

void main() async {
  // ضروري لضمان تهيئة Flutter قبل استدعاء أي API أصلي
  WidgetsFlutterBinding.ensureInitialized();

  // الحصول على قائمة الكاميرات مع معالجة الأخطاء
  final cameras = await getCameras();

  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const MyApp({Key? key, required this.cameras}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // طباعة معلومات الكاميرات مرة أخرى عند بناء التطبيق
    print('بناء التطبيق مع ${cameras.length} كاميرا');

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFFAA2A2A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFAA2A2A),
          primary: const Color(0xFFAA2A2A),
        ),
        useMaterial3: false,
        fontFamily: 'Almarai',
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontWeight: FontWeight.w700),
          displayMedium: TextStyle(fontWeight: FontWeight.w700),
          displaySmall: TextStyle(fontWeight: FontWeight.w700),

          headlineLarge: TextStyle(fontWeight: FontWeight.w700),
          headlineMedium: TextStyle(fontWeight: FontWeight.w700),
          headlineSmall: TextStyle(fontWeight: FontWeight.w700),

          titleLarge: TextStyle(fontWeight: FontWeight.w700),
          titleMedium: TextStyle(fontWeight: FontWeight.w600),
          titleSmall: TextStyle(fontWeight: FontWeight.w600),

          bodyLarge: TextStyle(fontWeight: FontWeight.w400),
          bodyMedium: TextStyle(fontWeight: FontWeight.w400),
          bodySmall: TextStyle(fontWeight: FontWeight.w400),
        ),
      ),
      home: HomePage(cameras: cameras),

      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar', '')],
      locale: const Locale('ar', ''),
    );
  }
}

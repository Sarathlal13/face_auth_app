import 'package:flutter/material.dart';
import 'package:mploye_auth/face_auth.dart' show FaceDetectorPage;
import 'package:mploye_auth/home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    ),
  );
}
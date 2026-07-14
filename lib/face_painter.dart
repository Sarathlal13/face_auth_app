import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FacePainter extends CustomPainter {

  final List<Face> faces;

  FacePainter(this.faces);

  @override
  void paint(Canvas canvas, Size size) {

    final paint = Paint()
      ..color = Colors.green
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    for (final face in faces) {

      canvas.drawRect(
        face.boundingBox,
        paint,
      );

    }

  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;

}
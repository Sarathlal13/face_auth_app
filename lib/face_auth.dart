import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:mploye_auth/face_painter.dart' show FacePainter;
import 'package:mploye_auth/face_rec.dart';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class FaceDetectorPage extends StatefulWidget {
  const FaceDetectorPage({
    super.key,
    this.isRegistration = false,
    this.employeeId = "",
  });
  final bool isRegistration;
  final String employeeId;
  @override
  State<FaceDetectorPage> createState() => _FaceDetectorPageState();
}

class _FaceDetectorPageState extends State<FaceDetectorPage> {
  CameraController? controller;
  late CameraDescription frontCamera;
  late FaceDetector detector;
  late FaceRecognition faceRecognition;
  bool processing = false;
  List<Face> detectedFaces = [];
  bool leftEyeClosed = false;
  bool rightEyeClosed = false;
  bool blinkCompleted = false;

  bool smileCompleted = false;
  bool imageCaptured = false;
  String status = "Looking for face...";
  @override
  void initState() {
    super.initState();

    detector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableContours: true,
        enableTracking: true,
      ),
    );
    faceRecognition = FaceRecognition();
    // faceRecognition.loadModel();

    initCamera();
  }

  void showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(child: Text("Processing...\nPlease wait")),
            ],
          ),
        );
      },
    );
  }

  void hideLoadingDialog() {
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> captureImage() async {
    if (controller == null || !controller!.value.isInitialized) return;

    try {
      await controller!.stopImageStream();

      final XFile file = await controller!.takePicture();
      showLoadingDialog();
      debugPrint("Captured : ${file.path}");

      final url = widget.isRegistration
          ? "https://crabbing-bunt-crispy.ngrok-free.dev/register"
          : "https://crabbing-bunt-crispy.ngrok-free.dev/verify";

      final request = http.MultipartRequest("POST", Uri.parse(url));

      if (widget.isRegistration) {
        request.fields["employee_id"] = widget.employeeId;
      }

      request.files.add(await http.MultipartFile.fromPath("photo", file.path));

      final response = await request.send();
      final body = await response.stream.bytesToString();
      final result = jsonDecode(body);
      hideLoadingDialog();
      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(
              widget.isRegistration ? "Registration" : "Verification",
            ),
            content: Text(
              widget.isRegistration
                  ? "Employee ${widget.employeeId} registered successfully."
                  : result["matched"]
                  ? """Employee : ${result["employee_id"]}

Similarity : ${result["similarity"]}

Confidence : ${result["confidence"]}"""
                  : "Face Not Recognized",
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  // Close dialog
                  Navigator.of(dialogContext).pop();

                  if (widget.isRegistration) {
                    // Return to registration page
                    Navigator.of(context).pop();
                  } else {
                    // Reset liveness state
                    blinkCompleted = false;

                    smileCompleted = false;
                    leftEyeClosed = false;
                    rightEyeClosed = false;
                    imageCaptured = false;
                    status = "Looking for face...";

                    // Restart camera
                    await controller!.startImageStream(processImage);

                    if (mounted) {
                      setState(() {});
                    }
                  }
                },
                child: const Text("OK"),
              ),
            ],
          );
        },
      );
    } catch (e, s) {
      debugPrint("ERROR: $e");
      debugPrint(s.toString());
      hideLoadingDialog();

      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Error"),
            content: Text(e.toString()),
          ),
        );
      }
    }
  }

  Future<void> initCamera() async {
    final cameras = await availableCameras();

    frontCamera = cameras.firstWhere(
      (e) => e.lensDirection == CameraLensDirection.front,
    );

    controller = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    await controller!.initialize();

    controller!.startImageStream(processImage);

    if (mounted) setState(() {});
  }

  InputImage? inputImageFromCameraImage(CameraImage image) {
    final bytes = WriteBuffer();

    for (final plane in image.planes) {
      bytes.putUint8List(plane.bytes);
    }

    final allBytes = bytes.done().buffer.asUint8List();

    final imageSize = Size(image.width.toDouble(), image.height.toDouble());

    final rotation =
        InputImageRotationValue.fromRawValue(frontCamera.sensorOrientation) ??
        InputImageRotation.rotation0deg;

    final format =
        InputImageFormatValue.fromRawValue(image.format.raw) ??
        InputImageFormat.nv21;

    final metadata = InputImageMetadata(
      size: imageSize,
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return InputImage.fromBytes(bytes: allBytes, metadata: metadata);
  }

  Future<void> processImage(CameraImage image) async {
    if (processing) return;

    processing = true;

    try {
      final inputImage = inputImageFromCameraImage(image);

      if (inputImage == null) {
        processing = false;
        return;
      }

      final faces = await detector.processImage(inputImage);

      if (!mounted) return;

      if (faces.length != 1) {
        setState(() {
          detectedFaces = [];
          status = "Show exactly one face";
        });
        return;
      }

      final face = faces.first;

      final leftEye = face.leftEyeOpenProbability ?? 1.0;
      final rightEye = face.rightEyeOpenProbability ?? 1.0;
      final smile = face.smilingProbability ?? 0.0;

      debugPrint("Smile : $smile");

      debugPrint(
        "Left:${leftEye.toStringAsFixed(2)} "
        "Right:${rightEye.toStringAsFixed(2)} ",
      );

      //--------------------------------------
      // STEP 1 - Blink
      //--------------------------------------
      if (!blinkCompleted) {
        status = "Please Blink";

        if (leftEye < 0.3 && rightEye < 0.3) {
          leftEyeClosed = true;
          rightEyeClosed = true;
        }

        if (leftEyeClosed &&
            rightEyeClosed &&
            leftEye > 0.8 &&
            rightEye > 0.8) {
          blinkCompleted = true;
          status = "Blink Detected ✅";

          debugPrint("Blink Success");
        }
      }
      //--------------------------------------
      // STEP 2 - Turn Left
      //--------------------------------------
      else if (!smileCompleted) {
        status = "Please Smile";

        if (smile > 0.75) {
          smileCompleted = true;
          status = "Smile Detected 😊";

          debugPrint("Smile Success");
        }
      }
      //--------------------------------------
      // STEP 3 - Success
      //--------------------------------------
      else {
        status = "Liveness Passed ✅";

        if (!imageCaptured) {
          imageCaptured = true;

          Future.delayed(const Duration(milliseconds: 800), () {
            captureImage();
          });
        }
      }
      //--------------------------------------
      // STEP 5 - Success
      //--------------------------------------

      setState(() {
        detectedFaces = faces;
      });
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      processing = false;
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    detector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isRegistration ? "Register Employee" : "Verify Employee",
        ),
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                blinkCompleted = false;
                leftEyeClosed = false;
                rightEyeClosed = false;
                status = "Looking for face...";
              });
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          CameraPreview(controller!),
          // Center(
          //   child: Container(
          //     width: 260,
          //     height: 260,
          //     decoration: BoxDecoration(
          //       shape: BoxShape.circle,
          //       border: Border.all(color: Colors.white, width: 3),
          //     ),
          //   ),
          // ),
          CustomPaint(painter: FacePainter(detectedFaces), size: Size.infinite),
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

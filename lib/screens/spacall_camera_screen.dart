import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter/services.dart';

class SpacallCameraScreen extends StatefulWidget {
  final bool isFace;
  final bool isBlinkRequired;

  const SpacallCameraScreen({
    super.key,
    this.isFace = false,
    this.isBlinkRequired = false,
  });

  @override
  State<SpacallCameraScreen> createState() => _SpacallCameraScreenState();
}

class _SpacallCameraScreenState extends State<SpacallCameraScreen> {
  CameraController? _controller;
  FaceDetector? _faceDetector;
  TextRecognizer? _textRecognizer;
  bool _isBusy = false;
  bool _isIdDetected = false;
  bool _captureComplete = false;
  bool _isProcessing = false;
  String _status = '';

  // Face Liveness state
  bool _eyesOpened = false;
  bool _eyesClosed = false;

  @override
  void initState() {
    super.initState();
    _status = widget.isFace
        ? 'Align your face in the circle'
        : 'Align ID card in the box';
    _initializeCamera();
    if (widget.isFace) {
      _initializeFaceDetector();
    } else {
      _initializeTextRecognizer();
    }
  }

  void _initializeTextRecognizer() {
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  }

  void _initializeFaceDetector() {
    final options = FaceDetectorOptions(
      enableClassification: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.accurate,
    );
    _faceDetector = FaceDetector(options: options);
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();

    // Auto-select camera: Front for face, Back for everything else
    final targetDirection = widget.isFace
        ? CameraLensDirection.front
        : CameraLensDirection.back;

    final camera = cameras.firstWhere(
      (c) => c.lensDirection == targetDirection,
      orElse: () => cameras.first,
    );

    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    await _controller?.initialize();
    if (!mounted) return;

    setState(() {});

    if (widget.isFace || !widget.isFace) {
      _controller?.startImageStream(_processCameraImage);
    }
  }

  void _processCameraImage(CameraImage image) async {
    if (_isBusy || _captureComplete || _isProcessing) return;
    _isBusy = true;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;

      if (widget.isFace) {
        final faces = await _faceDetector?.processImage(inputImage);

        if (faces != null && faces.isNotEmpty) {
          final face = faces.first;

          if (widget.isBlinkRequired) {
            setState(() {
              _status = 'Looking good! Now blink your eyes...';
            });

            final double? leftEye = face.leftEyeOpenProbability;
            final double? rightEye = face.rightEyeOpenProbability;

            if (leftEye != null && rightEye != null) {
              if (!_eyesOpened && leftEye > 0.7 && rightEye > 0.7) {
                _eyesOpened = true;
              } else if (_eyesOpened &&
                  !_eyesClosed &&
                  leftEye < 0.2 &&
                  rightEye < 0.2) {
                _eyesClosed = true;
              } else if (_eyesOpened &&
                  _eyesClosed &&
                  leftEye > 0.7 &&
                  rightEye > 0.7) {
                _onCaptureRequested();
              }
            }
          } else {
            // Face detected, no blink required (optional capture trigger)
            setState(() {
              _status = 'Face detected! Tap to capture.';
            });
          }
        } else {
          setState(() {
            _status = 'Face not detected';
            _eyesOpened = false;
            _eyesClosed = false;
          });
        }
      } else {
        // ID Card Detection Logic (OCR)
        final recognizedText = await _textRecognizer?.processImage(inputImage);

        final text = recognizedText?.text.trim() ?? '';
        final upperText = text.toUpperCase();

        final hasKeywords =
            upperText.contains('NAME') ||
            upperText.contains('ID') ||
            upperText.contains('IDENTITY') ||
            upperText.contains('PHILIPPINES') ||
            upperText.contains('CARD') ||
            upperText.contains('REPUBLIC') ||
            upperText.contains('PLACE') ||
            upperText.contains('DATE') ||
            upperText.contains('ADDRESS') ||
            upperText.contains('BLOOD') ||
            upperText.contains('ISSUE') ||
            upperText.contains('EXPIRY') ||
            upperText.contains('VALID') ||
            upperText.contains('SERIAL') ||
            upperText.contains('SIGNATURE') ||
            upperText.contains('NATIONAL') ||
            upperText.contains('RESIDENT');

        if (text.length > 25 && hasKeywords) {
          // If we detect enough text, consider it an ID
          if (!_isIdDetected) {
            setState(() {
              _isIdDetected = true;
              _status = 'ID Detected! Tap to capture.';
            });
          }
        } else {
          if (_isIdDetected) {
            setState(() {
              _isIdDetected = false;
              _status = 'Align ID card in the box';
            });
          }
        }
      }
    } catch (e) {
      print('Detection error: $e');
    } finally {
      _isBusy = false;
    }
  }

  void _onCaptureRequested() async {
    if (_captureComplete) return;

    // Reject capture for ID scans if not clearly detected
    if (!widget.isFace && !_isIdDetected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please align your ID card correctly in the box until detected.',
          ),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _captureComplete = true;
      _status = 'Capturing...';
    });

    try {
      _isProcessing = true;
      await _controller?.stopImageStream();

      final XFile? file = await _controller?.takePicture();

      if (!mounted) return;

      if (file != null) {
        Navigator.pop(context, file);
      }
    } catch (e) {
      print('Capture error: $e');
      setState(() {
        _captureComplete = false;
        _isProcessing = false;
        _controller?.startImageStream(_processCameraImage);
      });
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_controller == null) return null;

    final camera = _controller!.description;
    final sensorOrientation = camera.sensorOrientation;

    final orientations = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = orientations[DeviceOrientation.portraitUp];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888))
      return null;

    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceDetector?.close();
    _textRecognizer?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.blue)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview
          Center(child: CameraPreview(_controller!)),

          // Overlay (Circle for Face, Rectangle for ID)
          Center(
            child: widget.isFace
                ? _buildCircleOverlay()
                : _buildRectangleOverlay(),
          ),

          // Text Prompts
          Positioned(
            bottom: widget.isFace ? 120 : 60,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                  ),
                ),
                if (widget.isFace &&
                    widget.isBlinkRequired &&
                    !_captureComplete)
                  _buildBlinkProgress(),
              ],
            ),
          ),

          // Action Buttons
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!widget.isBlinkRequired)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: GestureDetector(
                      onTap: _onCaptureRequested,
                      child: Container(
                        height: 80,
                        width: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          color: Colors.white.withOpacity(0.2),
                        ),
                        child: Center(
                          child: Container(
                            height: 60,
                            width: 60,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Close Button
          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircleOverlay() {
    const goldColor = Color(0xFFD4AF37);
    return Container(
      width: 280,
      height: 280,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: _captureComplete ? Colors.green : goldColor,
          width: 4,
        ),
      ),
      child: _captureComplete
          ? const Icon(Icons.check_circle, color: Colors.green, size: 80)
          : null,
    );
  }

  Widget _buildRectangleOverlay() {
    const goldColor = Color(0xFFD4AF37);
    return Container(
      width: 320,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _captureComplete
              ? Colors.green
              : (_isIdDetected ? Colors.green : goldColor),
          width: 4,
        ),
      ),
      child: _captureComplete
          ? const Icon(Icons.check_circle, color: Colors.green, size: 80)
          : null,
    );
  }

  Widget _buildBlinkProgress() {
    return Column(
      children: [
        const SizedBox(height: 20),
        Container(
          width: 200,
          height: 10,
          decoration: BoxDecoration(
            color: Colors.grey[800],
            borderRadius: BorderRadius.circular(5),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: _eyesOpened ? (_eyesClosed ? 0.8 : 0.4) : 0.1,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

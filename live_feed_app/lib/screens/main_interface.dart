import 'dart:async';
import 'dart:collection'; // Added for Queue
import 'dart:typed_data';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'dart:convert';
import '../services/voice_feedback.dart';

class MainInterfaceScreen extends StatefulWidget {
  const MainInterfaceScreen({super.key});

  @override
  State<MainInterfaceScreen> createState() => _MainInterfaceScreenState();
}

class _MainInterfaceScreenState extends State<MainInterfaceScreen> {
  CameraController? _cameraController;
  bool _isDetecting = false;
  bool _isFrameInFlight = false;
  String _currentExercise = 'Push-Ups';
  String _currentExerciseApi = 'pushup';
  String _feedbackMessage = '';
  String _predictionResult = '';
  DateTime? _lastVoiceTime;
  String _lastSpokenFeedback = '';
  final Duration _voiceInterval = const Duration(seconds: 2);

  final VoiceFeedback _voiceFeedback = VoiceFeedback();
  final http.Client _httpClient = http.Client();

  final String _backendBaseUrl = "http://172.16.106.34:8000";

  // ==================== NEW: Drop-Oldest Frame Queue ====================
  final Queue<Uint8List> _frameQueue = Queue<Uint8List>();
  bool _isProcessing = false; // Replaced _isFramePipelineBusy
  Timer? _queueProcessorTimer;

  // Throttling
  DateTime? _lastProcessedTime;
  final int throttleMilliseconds = 250; // You can keep 250 or increase to 300
  Timer? _captureTimer;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    _queueProcessorTimer?.cancel();
    _cameraController?.dispose();
    _httpClient.close();
    _frameQueue.clear();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isNotEmpty) {
      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.low,
        enableAudio: false,
      );
      await _cameraController!.initialize();
      if (mounted) setState(() {});
    }
  }

  void _toggleDetection() {
    setState(() {
      _isDetecting = !_isDetecting;
      _feedbackMessage = _isDetecting
          ? _buildStartHint(_currentExerciseApi)
          : 'Detection stopped. Great effort!';

      if (_isDetecting) {
        _lastVoiceTime = null;
        _lastSpokenFeedback = '';
      }

      _voiceFeedback.speak(_feedbackMessage);

      if (_isDetecting) {
        _resetExerciseBuffer();
        _startDetection();
      } else {
        _stopDetection();
      }
    });
  }

  Uri _buildPredictUri() {
    return Uri.parse(
      "$_backendBaseUrl/predict_frame",
    ).replace(queryParameters: {'exercise': _currentExerciseApi});
  }

  String _buildStartHint(String exerciseApi) {
    if (exerciseApi == 'pushup') {
      return 'Starting push-up detection. Hold steady briefly while sequence builds.';
    }
    return 'Starting detection. Keep your full body in frame.';
  }

  Future<void> _resetExerciseBuffer() async {
    try {
      final uri = Uri.parse(
        "$_backendBaseUrl/reset",
      ).replace(queryParameters: {'exercise': _currentExerciseApi});
      await http.post(uri).timeout(const Duration(seconds: 3));
    } catch (_) {
      // Buffer reset is best-effort only.
    }
  }

  void _startDetection() {
    _frameQueue.clear();
    _isProcessing = false;
    _lastProcessedTime = null;

    if (Platform.isWindows) {
      _captureTimer = Timer.periodic(
        Duration(milliseconds: throttleMilliseconds),
        (_) {
          _captureAndProcessFrame();
        },
      );
    } else {
      _cameraController!.startImageStream(_onCameraFrameAvailable);
    }
  }

  void _stopDetection() {
    if (Platform.isWindows) {
      _captureTimer?.cancel();
    } else {
      _cameraController!.stopImageStream();
    }
    _queueProcessorTimer?.cancel();
    _frameQueue.clear();
    _isProcessing = false;

    _voiceFeedback.stop();
    if (mounted) {
      setState(() {
        _predictionResult = '';
        _feedbackMessage = 'Detection paused';
      });
    }
  }

  // ==================== NEW: Mobile Frame Handler with Queue ====================
  void _onCameraFrameAvailable(CameraImage cameraImage) {
    if (!_isDetecting) return;

    // Convert to JPG asynchronously (non-blocking)
    _convertCameraImageToJpg(cameraImage)
        .then((jpgBytes) {
          if (jpgBytes == null) return;

          // Drop oldest frame if queue is full (prevents backlog)
          if (_frameQueue.length >= 6) {
            _frameQueue.removeFirst();
          }
          _frameQueue.addLast(jpgBytes);

          // Start processing if not busy
          if (!_isProcessing) {
            _processNextFrameFromQueue();
          }
        })
        .catchError((e) {
          debugPrint("Frame conversion error: $e");
        });
  }

  // ==================== NEW: Queue Processor ====================
  Future<void> _processNextFrameFromQueue() async {
    if (!_isDetecting || _isProcessing || _frameQueue.isEmpty) {
      return;
    }

    _isProcessing = true;

    try {
      final Uint8List jpgBytes = _frameQueue.removeFirst();
      await _sendFrameToBackend(jpgBytes);
    } catch (e) {
      if (mounted) {
        setState(() {
          _predictionResult = "Error: $e";
        });
      }
    } finally {
      _isProcessing = false;

      // Process next frame immediately if queue still has frames
      if (_frameQueue.isNotEmpty && _isDetecting) {
        Future.delayed(const Duration(milliseconds: 30), () {
          _processNextFrameFromQueue();
        });
      }
    }
  }

  // Kept your original Windows capture method (slightly updated)
  Future<void> _captureAndProcessFrame() async {
    if (!_isDetecting ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isProcessing) {
      return;
    }

    final now = DateTime.now();
    if (_lastProcessedTime != null &&
        now.difference(_lastProcessedTime!).inMilliseconds <
            throttleMilliseconds) {
      return;
    }
    _lastProcessedTime = now;
    _isFrameInFlight = true;

    try {
      final XFile picture = await _cameraController!.takePicture();
      final Uint8List jpgBytes = await picture.readAsBytes();

      if (_frameQueue.length >= 6) {
        _frameQueue.removeFirst();
      }
      _frameQueue.addLast(jpgBytes);

      if (!_isProcessing) {
        _processNextFrameFromQueue();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _predictionResult = "Error: $e";
        });
      }
    } finally {
      _isFrameInFlight = false;
    }
  }

  Future<void> _sendFrameToBackend(Uint8List jpgBytes) async {
    if (!_isDetecting) return;

    try {
      var request = http.MultipartRequest('POST', _buildPredictUri());
      request.files.add(
        http.MultipartFile.fromBytes('file', jpgBytes, filename: 'frame.jpg'),
      );

      var response = await _httpClient
          .send(request)
          .timeout(const Duration(seconds: 5)); // Slightly increased timeout

      if (response.statusCode == 200) {
        var respStr = await response.stream.bytesToString();
        var data = json.decode(respStr);

        String prediction = data['prediction'] ?? 'Unknown';
        double prob = (data['probability'] as num?)?.toDouble() ?? 0.0;
        String feedback = data['feedback'] ?? 'No feedback';

        final bool isFinalPrediction =
            prediction == 'Correct' || prediction == 'Incorrect';
        String newPrediction = isFinalPrediction
            ? "$prediction (${(prob * 100).toStringAsFixed(1)}%)"
            : prediction;

        final now = DateTime.now();
        bool canSpeakByTime =
            _lastVoiceTime == null ||
            now.difference(_lastVoiceTime!) >= _voiceInterval;
        bool shouldSpeak =
            isFinalPrediction &&
            feedback.isNotEmpty &&
            canSpeakByTime &&
            feedback != _lastSpokenFeedback;

        if (mounted && _isDetecting) {
          final bool uiChanged =
              _predictionResult != newPrediction ||
              _feedbackMessage != feedback;

          if (uiChanged) {
            setState(() {
              _predictionResult = newPrediction;
              _feedbackMessage = feedback;
            });
          }

          if (shouldSpeak) {
            _voiceFeedback.speak(feedback);
            _lastVoiceTime = now;
            _lastSpokenFeedback = feedback;
          }
        }
      } else {
        if (mounted && _isDetecting) {
          setState(() {
            _predictionResult = "Server Error: ${response.statusCode}";
            _feedbackMessage = "Connection issue";
          });
        }
      }
    } catch (e) {
      if (mounted && _isDetecting) {
        setState(() {
          _predictionResult = "Error: $e";
          _feedbackMessage = "Check connection or camera";
        });
      }
    }
  }

  Future<Uint8List> _convertCameraImageToJpg(CameraImage image) async {
    img.Image? convertedImage;

    if (image.format.group == ImageFormatGroup.yuv420) {
      final int width = image.width;
      final int height = image.height;

      final Uint8List yBytes = image.planes[0].bytes;
      final Uint8List uBytes = image.planes[1].bytes;
      final Uint8List vBytes = image.planes[2].bytes;

      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

      convertedImage = img.Image(width: width, height: height);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int yIndex = y * image.planes[0].bytesPerRow + x;
          final int yp = yBytes[yIndex];

          final int uvX = (x ~/ 2) * uvPixelStride;
          final int uvY = (y ~/ 2) * uvRowStride;
          final int uvIndex = uvY + uvX;

          final int up = uBytes[uvIndex] - 128;
          final int vp = vBytes[uvIndex] - 128;

          int r = (yp + (1.402 * vp)).round().clamp(0, 255);
          int g = (yp - (0.344136 * up) - (0.714136 * vp)).round().clamp(
            0,
            255,
          );
          int b = (yp + (1.772 * up)).round().clamp(0, 255);

          convertedImage.setPixelRgba(x, y, r, g, b, 255);
        }
      }
    } else if (image.format.group == ImageFormatGroup.bgra8888) {
      final plane = image.planes[0];
      convertedImage = img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: plane.bytes.buffer,
        rowStride: plane.bytesPerRow,
        order: img.ChannelOrder.bgra,
      );
    } else {
      throw Exception('Unsupported image format');
    }

    final img.Image source = convertedImage!;
    final img.Image compressed = source.width > 320
        ? img.copyResize(source, width: 320)
        : source;
    return Uint8List.fromList(img.encodeJpg(compressed, quality: 60));
  }

  void _showExerciseSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withOpacity(0.8),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            const Text(
              'Select Exercise',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const Divider(
              color: Colors.white54,
              thickness: 1,
              indent: 16,
              endIndent: 16,
            ),
            ListTile(
              leading: const Icon(Icons.fitness_center, color: Colors.white),
              title: const Text(
                'Push-Ups',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                setState(() {
                  _currentExercise = 'Push-Ups';
                  _currentExerciseApi = 'pushup';
                  _feedbackMessage = '';
                  _predictionResult = '';
                });
                _resetExerciseBuffer();
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.fitness_center, color: Colors.white),
              title: const Text(
                'Deadlift',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                setState(() {
                  _currentExercise = 'Deadlift';
                  _currentExerciseApi = 'deadlift';
                  _feedbackMessage = '';
                  _predictionResult = '';
                });
                _resetExerciseBuffer();
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.fitness_center, color: Colors.white),
              title: const Text('Plank', style: TextStyle(color: Colors.white)),
              onTap: () {
                setState(() {
                  _currentExercise = 'Plank';
                  _currentExerciseApi = 'plank';
                  _feedbackMessage = '';
                  _predictionResult = '';
                });
                _resetExerciseBuffer();
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.fitness_center, color: Colors.white),
              title: const Text(
                'Bicep Curl',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                setState(() {
                  _currentExercise = 'Bicep Curl';
                  _currentExerciseApi = 'bicep';
                  _feedbackMessage = '';
                  _predictionResult = '';
                });
                _resetExerciseBuffer();
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/background.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.3)),
                child: SafeArea(
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'FitPose',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1.5,
                            ),
                          ),
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(
                              Icons.settings,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.fitness_center,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _currentExercise,
                              style: const TextStyle(
                                fontSize: 18,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _predictionResult,
                        style: TextStyle(
                          color: _predictionResult.contains("Correct")
                              ? Colors.green
                              : (_predictionResult.contains("Incorrect")
                                    ? Colors.red
                                    : Colors.yellow),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          _feedbackMessage,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _toggleDetection,
                        icon: Icon(
                          _isDetecting ? Icons.stop : Icons.play_arrow,
                          color: Colors.indigo,
                        ),
                        label: Text(
                          _isDetecting ? 'Stop' : 'Start',
                          style: const TextStyle(
                            color: Colors.indigo,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _cameraController?.value.isInitialized == true
                    ? CameraPreview(_cameraController!)
                    : const Center(
                        child: CircularProgressIndicator(color: Colors.indigo),
                      ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.3)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      onPressed: _showExerciseSelector,
                      icon: const Icon(
                        Icons.list,
                        color: Colors.white,
                        size: 30,
                      ),
                      tooltip: 'Select Exercise',
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(
                        Icons.history,
                        color: Colors.white,
                        size: 30,
                      ),
                      tooltip: 'Workout History',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

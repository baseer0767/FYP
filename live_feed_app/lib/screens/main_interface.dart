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
import '../theme/gym_theme.dart';
import 'workout_hub_screen.dart';

class MainInterfaceScreen extends StatefulWidget {
  const MainInterfaceScreen({
    super.key,
    this.initialExerciseLabel = 'Push-Ups',
    this.initialExerciseApi = 'pushup',
  });

  final String initialExerciseLabel;
  final String initialExerciseApi;

  @override
  State<MainInterfaceScreen> createState() => _MainInterfaceScreenState();
}

class _MainInterfaceScreenState extends State<MainInterfaceScreen> {
  CameraController? _cameraController;
  bool _isDetecting = false;
  bool _isFrameInFlight = false;
  late String _currentExercise;
  late String _currentExerciseApi;
  String _feedbackMessage = '';
  String _predictionResult = '';
  DateTime? _lastVoiceTime;
  String _lastSpokenFeedback = '';
  final Duration _voiceInterval = const Duration(seconds: 2);

  final VoiceFeedback _voiceFeedback = VoiceFeedback();
  final http.Client _httpClient = http.Client();

  final String _backendBaseUrl = "http://192.168.44.65:8000";

  // ==================== NEW: Drop-Oldest Frame Queue ====================
  final Queue<Uint8List> _frameQueue = Queue<Uint8List>();
  bool _isProcessing = false; // Replaced _isFramePipelineBusy
  Timer? _queueProcessorTimer;

  // Throttling
  DateTime? _lastProcessedTime;
  final int throttleMilliseconds = 250; // You can keep 250 or increase to 300
  Timer? _captureTimer;

  void _goBackToHub() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const WorkoutHubScreen()),
    );
  }

  Widget _glassPanel({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
          borderRadius: BorderRadius.circular(28),
        ),
        child: child,
      ),
    );
  }

  Widget _statusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.34)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _currentExercise = widget.initialExerciseLabel;
    _currentExerciseApi = widget.initialExerciseApi;
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
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _glassPanel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  Container(
                    width: 52,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.28),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Select exercise',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      _statusPill('Push-Ups', GymColors.accentCool),
                      _statusPill('Deadlift', GymColors.accentSoft),
                      _statusPill('Plank', GymColors.accent),
                      _statusPill('Bicep Curl', Colors.redAccent),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ...[
                    ('Push-Ups', 'pushup'),
                    ('Deadlift', 'deadlift'),
                    ('Plank', 'plank'),
                    ('Bicep Curl', 'bicep'),
                  ].map(
                    (exercise) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        tileColor: Colors.white.withOpacity(0.04),
                        leading: const Icon(
                          Icons.fitness_center_rounded,
                          color: Colors.white,
                        ),
                        title: Text(
                          exercise.$1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: Colors.white54,
                          size: 16,
                        ),
                        onTap: () {
                          setState(() {
                            _currentExercise = exercise.$1;
                            _currentExerciseApi = exercise.$2;
                            _feedbackMessage = '';
                            _predictionResult = '';
                          });
                          _resetExerciseBuffer();
                          Navigator.pop(context);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/background.png',
              fit: BoxFit.cover,
              color: Colors.black.withOpacity(0.66),
              colorBlendMode: BlendMode.darken,
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xF105070A),
                    Color(0xDD0D1320),
                    Color(0xF105070A),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-1.0, -1.0),
                    radius: 1.2,
                    colors: [
                      GymColors.accent.withOpacity(0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                children: [
                  _glassPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                onPressed: _goBackToHub,
                                icon: const Icon(
                                  Icons.arrow_back_rounded,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Expanded(
                                child: Text(
                                  'FitPose',
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: _showExerciseSelector,
                                icon: const Icon(
                                  Icons.list_rounded,
                                  color: Colors.white,
                                ),
                                tooltip: 'Select Exercise',
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            alignment: WrapAlignment.center,
                            children: [
                              _statusPill(_currentExercise, GymColors.accent),
                              _statusPill(
                                _isDetecting
                                    ? 'Live training'
                                    : 'Ready to start',
                                _isDetecting
                                    ? GymColors.accentSoft
                                    : GymColors.accentCool,
                              ),
                              _statusPill('Theme locked', GymColors.accent),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _predictionResult,
                            style: TextStyle(
                              color: _predictionResult.contains('Correct')
                                  ? Colors.greenAccent
                                  : (_predictionResult.contains('Incorrect')
                                        ? Colors.redAccent
                                        : Colors.white.withOpacity(0.82)),
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _feedbackMessage.isEmpty
                                ? 'Press start when you are ready to train.'
                                : _feedbackMessage,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.white.withOpacity(0.78),
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 54,
                            child: ElevatedButton.icon(
                              onPressed: _toggleDetection,
                              icon: Icon(
                                _isDetecting
                                    ? Icons.stop_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.black,
                              ),
                              label: Text(
                                _isDetecting
                                    ? 'Stop Training'
                                    : 'Start Training',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: GymColors.accent,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: _glassPanel(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: _cameraController?.value.isInitialized == true
                              ? CameraPreview(_cameraController!)
                              : const Center(
                                  child: CircularProgressIndicator(
                                    color: GymColors.accent,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _glassPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            onPressed: _showExerciseSelector,
                            icon: const Icon(
                              Icons.list_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                            tooltip: 'Select Exercise',
                          ),
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(
                              Icons.history_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                            tooltip: 'Workout History',
                          ),
                          IconButton(
                            onPressed: _goBackToHub,
                            icon: const Icon(
                              Icons.home_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                            tooltip: 'Back to hub',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

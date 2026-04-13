import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/voice_feedback.dart';

class VideoCheckerScreen extends StatefulWidget {
  const VideoCheckerScreen({super.key});

  @override
  State<VideoCheckerScreen> createState() => _VideoCheckerScreenState();
}

class _VideoCheckerScreenState extends State<VideoCheckerScreen> {
  late final Player _player;
  VideoController? _videoController;

  bool _isProcessing = false;
  bool _isVideoPlaying = false;
  String _currentExercise = 'Push-Ups';
  String _currentExerciseApi = 'pushup';
  String _predictionResult = '';
  String _feedbackMessage = '';

  final VoiceFeedback _voiceFeedback = VoiceFeedback();
  final String _backendBaseUrl = "http://172.16.106.34:8000";

  Timer? _processingTimer;
  DateTime? _lastProcessedTime;
  DateTime? _lastFeedbackTime;
  final int _throttleMs = 200; // Send frames ~5 FPS
  final Duration _feedbackInterval = const Duration(seconds: 5); // ← NOW 5 SECONDS

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);

    _player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() {
          _isVideoPlaying = playing;
        });
      }
    });
  }

  @override
  void dispose() {
    _processingTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickVideo(source: ImageSource.gallery);

    if (pickedFile != null && mounted) {
      final filePath = pickedFile.path;

      await _player.open(Media(filePath));
      await _player.play();
      await _player.setPlaylistMode(PlaylistMode.loop);

      setState(() {});
    }
  }

  void _togglePlayPause() {
    if (_isVideoPlaying) {
      _player.pause();
    } else {
      _player.play();
    }
    if (mounted) setState(() {}); // Force icon update
  }

  void _toggleProcessing() {
    setState(() {
      _isProcessing = !_isProcessing;
      _feedbackMessage = _isProcessing
          ? 'Analyzing video... (feedback every 5 seconds)'
          : 'Analysis stopped';

      _voiceFeedback.speak(_feedbackMessage);

      if (_isProcessing) {
        _lastFeedbackTime = null;
        _resetExerciseBuffer();
        _startProcessingFrames();
      } else {
        _stopProcessingFrames();
      }
    });
  }

  Uri _buildPredictUri() {
    return Uri.parse("$_backendBaseUrl/predict_frame").replace(
      queryParameters: {'exercise': _currentExerciseApi},
    );
  }

  Future<void> _resetExerciseBuffer() async {
    try {
      final uri = Uri.parse("$_backendBaseUrl/reset").replace(
        queryParameters: {'exercise': _currentExerciseApi},
      );
      await http.post(uri).timeout(const Duration(seconds: 3));
    } catch (_) {
      // Buffer reset is best-effort only.
    }
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
                color: Colors.white54, thickness: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.fitness_center, color: Colors.white),
              title: const Text('Push-Ups', style: TextStyle(color: Colors.white)),
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
              title: const Text('Deadlift', style: TextStyle(color: Colors.white)),
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
              title: const Text('Bicep Curl', style: TextStyle(color: Colors.white)),
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

  void _startProcessingFrames() {
    _lastProcessedTime = null;
    _processingTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_isProcessing && _isVideoPlaying) {
        _extractAndSendFrame();
      }
    });
  }

  void _stopProcessingFrames() {
    _processingTimer?.cancel();
    if (mounted) {
      setState(() {
        _predictionResult = '';
        _feedbackMessage = 'Analysis stopped';
      });
    }
  }

  Future<void> _extractAndSendFrame() async {
    if (!_isProcessing || !_player.state.playlist.medias.isNotEmpty) return;

    final now = DateTime.now();

    if (_lastProcessedTime != null &&
        now.difference(_lastProcessedTime!).inMilliseconds < _throttleMs) {
      return;
    }
    _lastProcessedTime = now;

    try {
      final Uint8List? frameBytes = await _player.screenshot();

      if (frameBytes != null && frameBytes.isNotEmpty) {
        await _sendFrameToBackend(frameBytes);
      }
    } catch (e) {
      debugPrint("Screenshot capture error: $e");
    }
  }

  Future<void> _sendFrameToBackend(Uint8List imageBytes) async {
    if (!_isProcessing) return;

    try {
      var request = http.MultipartRequest('POST', _buildPredictUri());
      request.files.add(
        http.MultipartFile.fromBytes('file', imageBytes, filename: 'frame.jpg'),
      );

      var response = await request.send().timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final data = json.decode(respStr);

        final String prediction = data['prediction'] ?? 'Unknown';
        final double prob = (data['probability'] as num?)?.toDouble() ?? 0.0;
        final String feedback = data['feedback'] ?? 'Analyzing...';

        final String newPrediction = "$prediction (${(prob * 100).toStringAsFixed(1)}%)";
        final bool shouldSpeak = prediction == "Correct" || prediction == "Incorrect";

        final now = DateTime.now();
        final bool canShowFeedback = _lastFeedbackTime == null ||
            now.difference(_lastFeedbackTime!) >= _feedbackInterval;

        if (canShowFeedback && mounted) {
          setState(() {
            _predictionResult = newPrediction;
            _feedbackMessage = feedback;
          });

          if (shouldSpeak && feedback.isNotEmpty) {
            _voiceFeedback.speak(feedback);
          }

          _lastFeedbackTime = now;
        }
      } else {
        final now = DateTime.now();
        if ((_lastFeedbackTime == null || now.difference(_lastFeedbackTime!) >= _feedbackInterval) && mounted) {
          setState(() {
            _predictionResult = "Server Error: ${response.statusCode}";
            _feedbackMessage = "Connection issue";
          });
          _lastFeedbackTime = now;
        }
      }
    } catch (e) {
      debugPrint("Send error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasVideo = _player.state.playlist.medias.isNotEmpty;

    final double aspectRatio = hasVideo
        ? (_player.state.width ?? 16) / (_player.state.height ?? 9)
        : 16 / 9;

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
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5),
                          ),
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.settings, color: Colors.white, size: 28),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.fitness_center, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              '$_currentExercise (Video)',
                              style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w600),
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
                              : (_predictionResult.contains("Incorrect") ? Colors.red : Colors.yellow),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          _feedbackMessage,
                          style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600, height: 1.4),
                          textAlign: TextAlign.center,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _toggleProcessing,
                        icon: Icon(_isProcessing ? Icons.stop : Icons.play_arrow, color: Colors.indigo),
                        label: Text(
                          _isProcessing ? 'Stop Analysis' : 'Start Analysis',
                          style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Expanded(
                child: hasVideo && _videoController != null
                    ? AspectRatio(
                        aspectRatio: aspectRatio,
                        child: Video(controller: _videoController!),
                      )
                    : const Center(
                        child: Text(
                          "No video selected\nTap the folder icon below to pick one",
                          style: TextStyle(color: Colors.white70, fontSize: 18),
                          textAlign: TextAlign.center,
                        ),
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
                      icon: const Icon(Icons.list, color: Colors.white, size: 30),
                      tooltip: 'Select Exercise',
                    ),
                    IconButton(
                      onPressed: _pickVideo,
                      icon: const Icon(Icons.folder_open, color: Colors.white, size: 30),
                      tooltip: 'Pick Video',
                    ),
                    IconButton(
                      onPressed: hasVideo ? _togglePlayPause : null,
                      icon: Icon(
                        _isVideoPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        color: Colors.white,
                        size: 48,
                      ),
                      tooltip: _isVideoPlaying ? 'Pause Video' : 'Play Video',
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.history, color: Colors.white, size: 30),
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
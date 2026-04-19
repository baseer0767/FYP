import 'package:flutter_tts/flutter_tts.dart';

class VoiceFeedback {
  static final VoiceFeedback _instance = VoiceFeedback._internal();
  factory VoiceFeedback() => _instance;

  late FlutterTts _tts;
  bool _isSpeaking = false;

  VoiceFeedback._internal() {
    _tts = FlutterTts();
    _init();
  }

  void _init() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setCompletionHandler(() {
      _isSpeaking = false;
    });
  }

  Future<void> speak(String text) async {
    if (_isSpeaking) return;
    _isSpeaking = true;
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
    _isSpeaking = false;
  }
}

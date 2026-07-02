import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceInputService {
  static final _speech = stt.SpeechToText();
  static bool _initialized = false;

  static Future<bool> ensureReady() async {
    if (_initialized) return _speech.isAvailable;
    _initialized = await _speech.initialize(
      onStatus: (_) {},
      onError: (_) {},
    );
    return _initialized;
  }

  static Future<void> start({
    required void Function(String partial, bool isFinal) onResult,
    String localeId = 'ko_KR',
  }) async {
    final ok = await ensureReady();
    if (!ok) return;
    await _speech.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        localeId: localeId,
      ),
    );
  }

  static Future<void> stop() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
  }

  static Future<void> cancel() async {
    if (_speech.isListening) {
      await _speech.cancel();
    }
  }

  static bool get isListening => _speech.isListening;
}

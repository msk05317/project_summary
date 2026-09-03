import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceInputService {
  static final _speech = stt.SpeechToText();
  static bool _initialized = false;

  static void Function()? onStatusChange;
  static void Function(String errorMsg)? onError;

  static Future<bool> ensureReady() async {
    if (_initialized) return _speech.isAvailable;
    _initialized = await _speech.initialize(
      onStatus: (status) {
        onStatusChange?.call();
      },
      onError: (err) {
        onError?.call(err.errorMsg);
      },
    );
    return _initialized;
  }

  static Future<void> start({
    required void Function(String partial, bool isFinal) onResult,
    String localeId = 'ko_KR',
    Duration pauseFor = const Duration(seconds: 15),
    Duration listenFor = const Duration(seconds: 300),
  }) async {
    final ok = await ensureReady();
    if (!ok) return;
    await _speech.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
        listenMode: stt.ListenMode.dictation,
        pauseFor: pauseFor,
        listenFor: listenFor,
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

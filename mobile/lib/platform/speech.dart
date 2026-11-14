import 'package:flutter_tts/flutter_tts.dart';

/// Says short messages out loud (alerts while driving).
abstract class Speaker {
  Future<void> say(String text);
}

class SilentSpeaker implements Speaker {
  final said = <String>[];

  @override
  Future<void> say(String text) async => said.add(text);
}

class TtsSpeaker implements Speaker {
  late final _tts = FlutterTts();

  @override
  Future<void> say(String text) async {
    try {
      await _tts.speak(text);
    } catch (_) {
      // No speech engine (or running in tests): the alert still shows and vibrates.
    }
  }
}

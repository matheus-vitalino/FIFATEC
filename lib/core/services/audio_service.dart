import 'package:audioplayers/audioplayers.dart';

class AudioService {
  static final AudioPlayer _player = AudioPlayer();

  static Future<void> playWhistle() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('audio/whistle.mp3'));
    } catch (_) {
      // Silencia falhas para não travar a partida se o arquivo não existir ou falhar.
    }
  }
}

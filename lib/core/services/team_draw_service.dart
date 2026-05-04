import 'package:uuid/uuid.dart';
import '../models/player.dart';
import '../models/team.dart';

class TeamDrawService {
  final _uuid = const Uuid();

  static const _colors = [
    '#E53935', '#1E88E5', '#43A047', '#FB8C00',
    '#8E24AA', '#00ACC1', '#F4511E', '#6D4C41',
  ];

  static const _letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  /// Gera confrontos de chaveamento simples
  List<List<int>> generateBracket(int teamCount) {
    final matches = <List<int>>[];
    for (int i = 0; i < teamCount - 1; i += 2) {
      matches.add([i, i + 1]);
    }
    if (teamCount % 2 != 0) {
      matches.add([teamCount - 1, -1]); // bye
    }
    return matches;
  }

  String _letter(int index) => _letters[index % _letters.length];
  String _color(int index) => _colors[index % _colors.length];
}

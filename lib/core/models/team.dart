class TeamPlayer {
  final String playerId;
  final String playerName;
  bool isReserve;
  bool isInTwoTeams;

  TeamPlayer({
    required this.playerId,
    required this.playerName,
    this.isReserve = false,
    this.isInTwoTeams = false,
  });

  Map<String, dynamic> toMap() => {
        'playerId': playerId,
        'playerName': playerName,
        'isReserve': isReserve ? 1 : 0,
        'isInTwoTeams': isInTwoTeams ? 1 : 0,
      };

  factory TeamPlayer.fromMap(Map<String, dynamic> map) => TeamPlayer(
        playerId: (map['playerId'] as String?) ?? '',
        playerName: (map['playerName'] as String?) ?? '',
        isReserve: (map['isReserve'] as int? ?? 0) == 1,
        isInTwoTeams: (map['isInTwoTeams'] as int? ?? 0) == 1,
      );
}

class Team {
  final String id;
  String name;
  List<TeamPlayer> players;
  int score;
  String? color;

  Team({
    required this.id,
    required this.name,
    required this.players,
    this.score = 0,
    this.color,
  });

  List<TeamPlayer> get activePlayers =>
      players.where((p) => !p.isReserve).toList();

  List<TeamPlayer> get reservePlayers =>
      players.where((p) => p.isReserve).toList();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'players': players.map((p) => p.toMap()).toList(),
        'score': score,
        'color': color,
      };

  factory Team.fromMap(Map<String, dynamic> map) => Team(
        id: (map['id'] as String?) ?? '',
        name: (map['name'] as String?) ?? 'Time',
        players: ((map['players'] as List?) ?? [])
            .map((p) => TeamPlayer.fromMap(p as Map<String, dynamic>))
            .toList(),
        score: (map['score'] as int?) ?? 0,
        color: map['color'] as String?,
      );
}

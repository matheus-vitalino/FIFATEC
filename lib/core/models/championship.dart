import 'team.dart';

enum ChampionshipMode { bracket, teamsOnly }
enum ChampionshipStatus { setup, inProgress, finished }

class BracketRound {
  final String id;
  final String name;
  final List<String> matchIds;
  bool isFinished;

  BracketRound({
    required this.id,
    required this.name,
    required this.matchIds,
    this.isFinished = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'matchIds': matchIds,
        'isFinished': isFinished ? 1 : 0,
      };

  factory BracketRound.fromMap(Map<String, dynamic> map) => BracketRound(
        id: (map['id'] as String?) ?? '',
        name: (map['name'] as String?) ?? 'Rodada',
        matchIds: ((map['matchIds'] as List?) ?? [])
            .map((e) => e.toString())
            .toList(),
        isFinished: (map['isFinished'] as int? ?? 0) == 1,
      );
}

class Championship {
  final String id;
  String name;
  List<Team> teams;
  List<String> matchIds;
  List<BracketRound> rounds;
  ChampionshipMode mode;
  ChampionshipStatus status;
  String? winnerId;
  String? winnerName;
  String? seasonId;
  String? winnerPhotoPath;
  DateTime createdAt;
  DateTime? finishedAt;
  bool balanceTeams;
  int teamSize;

  Championship({
    required this.id,
    required this.name,
    required this.teams,
    List<String>? matchIds,
    List<BracketRound>? rounds,
    this.mode = ChampionshipMode.bracket,
    this.status = ChampionshipStatus.setup,
    this.winnerId,
    this.winnerName,
    this.seasonId,
    this.winnerPhotoPath,
    DateTime? createdAt,
    this.finishedAt,
    this.balanceTeams = false,
    this.teamSize = 3,
  })  : matchIds = matchIds ?? [],
        rounds = rounds ?? [],
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'teams': teams.map((t) => t.toMap()).toList(),
        'matchIds': matchIds,
        'rounds': rounds.map((r) => r.toMap()).toList(),
        'mode': mode.index,
        'status': status.index,
        'winnerId': winnerId,
        'winnerName': winnerName,
        'seasonId': seasonId,
        'winnerPhotoPath': winnerPhotoPath,
        'createdAt': createdAt.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'balanceTeams': balanceTeams ? 1 : 0,
        'teamSize': teamSize,
      };

  factory Championship.fromMap(Map<String, dynamic> map) {
    final modeIdx = (map['mode'] as int?) ?? 0;
    final statusIdx = (map['status'] as int?) ?? 0;
    return Championship(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? 'Campeonato',
      teams: ((map['teams'] as List?) ?? [])
          .map((t) => Team.fromMap(t as Map<String, dynamic>))
          .toList(),
      matchIds: ((map['matchIds'] as List?) ?? [])
          .map((e) => e.toString())
          .toList(),
      rounds: ((map['rounds'] as List?) ?? [])
          .map((r) => BracketRound.fromMap(r as Map<String, dynamic>))
          .toList(),
      mode: modeIdx >= 0 && modeIdx < ChampionshipMode.values.length
          ? ChampionshipMode.values[modeIdx]
          : ChampionshipMode.bracket,
      status: statusIdx >= 0 && statusIdx < ChampionshipStatus.values.length
          ? ChampionshipStatus.values[statusIdx]
          : ChampionshipStatus.setup,
      winnerId: map['winnerId'] as String?,
      winnerName: map['winnerName'] as String?,
      seasonId: map['seasonId'] as String?,
      winnerPhotoPath: map['winnerPhotoPath'] as String?,
      createdAt: DateTime.tryParse(
              (map['createdAt'] as String?) ?? '') ??
          DateTime.now(),
      finishedAt: map['finishedAt'] != null
          ? DateTime.tryParse(map['finishedAt'] as String)
          : null,
      balanceTeams: (map['balanceTeams'] as int? ?? 0) == 1,
      teamSize: (map['teamSize'] as int?) ?? 3,
    );
  }
}

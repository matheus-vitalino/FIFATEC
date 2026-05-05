import 'team.dart';

class SubstitutionEvent {
  final String teamId;
  final String playerOutId;
  final String playerOutName;
  final String playerInId;
  final String playerInName;
  final int timeSeconds;

  SubstitutionEvent({
    required this.teamId,
    required this.playerOutId,
    required this.playerOutName,
    required this.playerInId,
    required this.playerInName,
    required this.timeSeconds,
  });

  Map<String, dynamic> toMap() => {
        'teamId': teamId,
        'playerOutId': playerOutId,
        'playerOutName': playerOutName,
        'playerInId': playerInId,
        'playerInName': playerInName,
        'timeSeconds': timeSeconds,
      };

  factory SubstitutionEvent.fromMap(Map<String, dynamic> map) => SubstitutionEvent(
        teamId: (map['teamId'] as String?) ?? '',
        playerOutId: (map['playerOutId'] as String?) ?? '',
        playerOutName: (map['playerOutName'] as String?) ?? '',
        playerInId: (map['playerInId'] as String?) ?? '',
        playerInName: (map['playerInName'] as String?) ?? '',
        timeSeconds: (map['timeSeconds'] as int?) ?? 0,
      );
}

enum MatchType { normal, semifinal, final_ }

class GoalEvent {
  final String playerId;
  final String playerName;
  final String teamId;
  final int timeSeconds;
  final DateTime timestamp;

  GoalEvent({
    required this.playerId,
    required this.playerName,
    required this.teamId,
    required this.timeSeconds,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'playerId': playerId,
        'playerName': playerName,
        'teamId': teamId,
        'timeSeconds': timeSeconds,
        'timestamp': timestamp.toIso8601String(),
      };

  factory GoalEvent.fromMap(Map<String, dynamic> map) => GoalEvent(
        playerId: (map['playerId'] as String?) ?? '',
        playerName: (map['playerName'] as String?) ?? '',
        teamId: (map['teamId'] as String?) ?? '',
        timeSeconds: (map['timeSeconds'] as int?) ?? 0,
        timestamp: DateTime.tryParse((map['timestamp'] as String?) ?? '') ?? DateTime.now(),
      );
}

enum MatchStatus { pending, inProgress, finished, cancelled }

class MatchModel {
  final String id;
  String championshipId;
  String? seasonId;
  Team teamA;
  Team teamB;
  List<GoalEvent> goals;
  List<SubstitutionEvent> substitutions;
  MatchType matchType;
  MatchStatus status;
  String? winnerId;
  bool isDraw;
  bool isPenalty;
  String? winnerPhotoPath;
  DateTime date;
  String? round;
  int durationSeconds;
  bool showGoalTime;

  MatchModel({
    required this.id,
    required this.championshipId,
    this.seasonId,
    required this.teamA,
    required this.teamB,
    List<GoalEvent>? goals,
    List<SubstitutionEvent>? substitutions,
    this.matchType = MatchType.normal,
    this.status = MatchStatus.pending,
    this.winnerId,
    this.isDraw = false,
    this.isPenalty = false,
    this.winnerPhotoPath,
    DateTime? date,
    this.round,
    this.durationSeconds = 300,
    this.showGoalTime = true,
  })  : goals = goals ?? [],
        substitutions = substitutions ?? [],
        date = date ?? DateTime.now();

  int get teamAScore => goals.where((g) => g.teamId == teamA.id).length;
  int get teamBScore => goals.where((g) => g.teamId == teamB.id).length;
  bool get isFinished => status == MatchStatus.finished;

  Map<String, dynamic> toMap() => {
        'id': id,
        'championshipId': championshipId,
        'seasonId': seasonId,
        'teamA': teamA.toMap(),
        'teamB': teamB.toMap(),
        'goals': goals.map((g) => g.toMap()).toList(),
        'substitutions': substitutions.map((s) => s.toMap()).toList(),
        'matchType': matchType.index,
        'status': status.index,
        'winnerId': winnerId,
        'isDraw': isDraw ? 1 : 0,
        'isPenalty': isPenalty ? 1 : 0,
        'winnerPhotoPath': winnerPhotoPath,
        'date': date.toIso8601String(),
        'round': round,
        'durationSeconds': durationSeconds,
        'showGoalTime': showGoalTime ? 1 : 0,
      };

  factory MatchModel.fromMap(Map<String, dynamic> map) {
    final statusIndex = (map['status'] as int?) ?? 0;
    return MatchModel(
      id: (map['id'] as String?) ?? '',
      championshipId: (map['championshipId'] as String?) ?? '',
      seasonId: map['seasonId'] as String?,
      teamA: Team.fromMap((map['teamA'] as Map<String, dynamic>?) ?? {}),
      teamB: Team.fromMap((map['teamB'] as Map<String, dynamic>?) ?? {}),
      goals: ((map['goals'] as List?) ?? []).map((g) => GoalEvent.fromMap(g as Map<String, dynamic>)).toList(),
      substitutions: ((map['substitutions'] as List?) ?? []).map((s) => SubstitutionEvent.fromMap(s as Map<String, dynamic>)).toList(),
      matchType: MatchType.values[(map['matchType'] as int? ?? 0).clamp(0, MatchType.values.length - 1)],
      status: statusIndex >= 0 && statusIndex < MatchStatus.values.length ? MatchStatus.values[statusIndex] : MatchStatus.pending,
      winnerId: map['winnerId'] as String?,
      isDraw: (map['isDraw'] as int? ?? 0) == 1,
      isPenalty: (map['isPenalty'] as int? ?? 0) == 1,
      winnerPhotoPath: map['winnerPhotoPath'] as String?,
      date: DateTime.tryParse((map['date'] as String?) ?? '') ?? DateTime.now(),
      round: map['round'] as String?,
      durationSeconds: (map['durationSeconds'] as int?) ?? 300,
      showGoalTime: (map['showGoalTime'] as int? ?? 1) == 1,
    );
  }
}

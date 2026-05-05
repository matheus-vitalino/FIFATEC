enum DuoRankingMode { titlesWins, sharedGoals }

class AppSettings {
  int teamSize;
  int matchDurationSeconds;
  int startDelaySeconds;
  int goalLimit;
  int finalGoalLimit;
  bool showGoalTime;
  bool balanceTeams;
  DuoRankingMode duoRankingMode;
  String? activeSeasonId;

  AppSettings({
    this.teamSize = 3,
    this.matchDurationSeconds = 300,
    this.startDelaySeconds = 3,
    this.goalLimit = 2,
    this.finalGoalLimit = 2,
    this.showGoalTime = true,
    this.balanceTeams = false,
    this.duoRankingMode = DuoRankingMode.sharedGoals,
    this.activeSeasonId,
  });

  Map<String, dynamic> toMap() => {
        'teamSize': teamSize,
        'matchDurationSeconds': matchDurationSeconds,
        'startDelaySeconds': startDelaySeconds,
        'goalLimit': goalLimit,
        'finalGoalLimit': finalGoalLimit,
        'showGoalTime': showGoalTime ? 1 : 0,
        'balanceTeams': balanceTeams ? 1 : 0,
        'duoRankingMode': duoRankingMode.name,
        'activeSeasonId': activeSeasonId,
      };

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    DuoRankingMode parseMode(dynamic raw) {
      final value = raw?.toString();
      for (final mode in DuoRankingMode.values) {
        if (mode.name == value) return mode;
      }
      return DuoRankingMode.sharedGoals;
    }

    return AppSettings(
      teamSize: (map['teamSize'] as int?) ?? 3,
      matchDurationSeconds: (map['matchDurationSeconds'] as int?) ?? 300,
      startDelaySeconds: (map['startDelaySeconds'] as int?) ?? 3,
      goalLimit: (map['goalLimit'] as int?) ?? 2,
      finalGoalLimit: (map['finalGoalLimit'] as int?) ?? 2,
      showGoalTime: (map['showGoalTime'] as int? ?? 1) == 1,
      balanceTeams: (map['balanceTeams'] as int? ?? 0) == 1,
      duoRankingMode: parseMode(map['duoRankingMode']),
      activeSeasonId: map['activeSeasonId'] as String?,
    );
  }

  AppSettings copyWith({
    int? teamSize,
    int? matchDurationSeconds,
    int? startDelaySeconds,
    int? goalLimit,
    int? finalGoalLimit,
    bool? showGoalTime,
    bool? balanceTeams,
    DuoRankingMode? duoRankingMode,
    String? activeSeasonId,
    bool clearActiveSeasonId = false,
  }) =>
      AppSettings(
        teamSize: teamSize ?? this.teamSize,
        matchDurationSeconds: matchDurationSeconds ?? this.matchDurationSeconds,
        startDelaySeconds: startDelaySeconds ?? this.startDelaySeconds,
        goalLimit: goalLimit ?? this.goalLimit,
        finalGoalLimit: finalGoalLimit ?? this.finalGoalLimit,
        showGoalTime: showGoalTime ?? this.showGoalTime,
        balanceTeams: balanceTeams ?? this.balanceTeams,
        duoRankingMode: duoRankingMode ?? this.duoRankingMode,
        activeSeasonId: clearActiveSeasonId ? null : (activeSeasonId ?? this.activeSeasonId),
      );
}

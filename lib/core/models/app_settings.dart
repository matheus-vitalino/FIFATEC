enum DuoRankingMode { titlesWins, sharedGoals }

class AppSettings {
  static const String defaultGoogleDriveFolderLink =
      'https://drive.google.com/drive/folders/1AdDLmxOESwRMMW3p7nNap8sc_BlYQMXe?usp=sharing';

  int teamSize;
  int matchDurationSeconds;
  int startDelaySeconds;
  int goalLimit;
  int finalGoalLimit;
  bool showGoalTime;
  bool balanceTeams;
  DuoRankingMode duoRankingMode;
  String? activeSeasonId;

  /// Pasta padrão usada para importar/exportar backups online.
  /// O usuário pode trocar isso na tela de opções.
  String googleDriveFolderLink;

  /// Quando preenchido, somente este e-mail pode exportar backup online.
  /// Deixe vazio para permitir exportação para qualquer conta que já tenha
  /// permissão de escrita na pasta do Drive.
  String googleDriveOwnerEmail;

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
    this.googleDriveFolderLink = defaultGoogleDriveFolderLink,
    this.googleDriveOwnerEmail = '',
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
        'googleDriveFolderLink': googleDriveFolderLink,
        'googleDriveOwnerEmail': googleDriveOwnerEmail,
      };

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    DuoRankingMode parseMode(dynamic raw) {
      final value = raw?.toString();
      for (final mode in DuoRankingMode.values) {
        if (mode.name == value) return mode;
      }
      return DuoRankingMode.sharedGoals;
    }

    String parseText(dynamic value, String fallback) {
      final text = value?.toString().trim();
      return text == null || text.isEmpty ? fallback : text;
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
      googleDriveFolderLink: parseText(
        map['googleDriveFolderLink'],
        defaultGoogleDriveFolderLink,
      ),
      googleDriveOwnerEmail: parseText(map['googleDriveOwnerEmail'], ''),
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
    String? googleDriveFolderLink,
    String? googleDriveOwnerEmail,
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
        googleDriveFolderLink: googleDriveFolderLink ?? this.googleDriveFolderLink,
        googleDriveOwnerEmail: googleDriveOwnerEmail ?? this.googleDriveOwnerEmail,
      );
}

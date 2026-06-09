class PlayerSeasonStats {
  final String seasonId;
  final String playerId;
  int matchesPlayed;
  int wins;
  int losses;
  int goals;
  int ownGoals;
  int assists;
  int vices;
  int finals;
  int titles;

  PlayerSeasonStats({
    required this.seasonId,
    required this.playerId,
    this.matchesPlayed = 0,
    this.wins = 0,
    this.losses = 0,
    this.goals = 0,
    this.ownGoals = 0,
    this.assists = 0,
    this.vices = 0,
    this.finals = 0,
    this.titles = 0,
  });

  Map<String, dynamic> toMap() => {
        'seasonId': seasonId,
        'playerId': playerId,
        'matchesPlayed': matchesPlayed,
        'wins': wins,
        'losses': losses,
        'goals': goals,
        'ownGoals': ownGoals,
        'assists': assists,
        'vices': vices,
        'finals': finals,
        'titles': titles,
      };

  factory PlayerSeasonStats.fromMap(Map<String, dynamic> map) => PlayerSeasonStats(
        seasonId: (map['seasonId'] as String?) ?? '',
        playerId: (map['playerId'] as String?) ?? '',
        matchesPlayed: (map['matchesPlayed'] as int?) ?? 0,
        wins: (map['wins'] as int?) ?? 0,
        losses: (map['losses'] as int?) ?? 0,
        goals: (map['goals'] as int?) ?? 0,
        ownGoals: (map['ownGoals'] as int?) ?? 0,
        assists: (map['assists'] as int?) ?? 0,
        vices: (map['vices'] as int?) ?? 0,
        finals: (map['finals'] as int?) ?? 0,
        titles: (map['titles'] as int?) ?? 0,
      );

  PlayerSeasonStats copyWith({
    int? matchesPlayed,
    int? wins,
    int? losses,
    int? goals,
    int? ownGoals,
    int? assists,
    int? vices,
    int? finals,
    int? titles,
  }) =>
      PlayerSeasonStats(
        seasonId: seasonId,
        playerId: playerId,
        matchesPlayed: matchesPlayed ?? this.matchesPlayed,
        wins: wins ?? this.wins,
        losses: losses ?? this.losses,
        goals: goals ?? this.goals,
        ownGoals: ownGoals ?? this.ownGoals,
        assists: assists ?? this.assists,
        vices: vices ?? this.vices,
        finals: finals ?? this.finals,
        titles: titles ?? this.titles,
      );
}

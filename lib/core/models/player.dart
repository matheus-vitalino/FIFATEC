class Player {
  final String id;
  String name;
  String? description;
  String? photoPath;
  int matchesPlayed;
  int wins;
  int losses;
  int goals;
  int assists;
  int vices;
  int finals;
  int titles;
  String? seasonId;
  DateTime createdAt;

  Player({
    required this.id,
    required this.name,
    this.description,
    this.photoPath,
    this.matchesPlayed = 0,
    this.wins = 0,
    this.losses = 0,
    this.goals = 0,
    this.assists = 0,
    this.vices = 0,
    this.finals = 0,
    this.titles = 0,
    this.seasonId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'photoPath': photoPath,
        'matchesPlayed': matchesPlayed,
        'wins': wins,
        'losses': losses,
        'goals': goals,
        'assists': assists,
        'vices': vices,
        'finals': finals,
        'titles': titles,
        'seasonId': seasonId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Player.fromMap(Map<String, dynamic> map) => Player(
        id: (map['id'] as String?) ?? '',
        name: (map['name'] as String?) ?? 'Jogador',
        description: map['description'] as String?,
        photoPath: map['photoPath'] as String?,
        matchesPlayed: (map['matchesPlayed'] as int?) ?? 0,
        wins: (map['wins'] as int?) ?? 0,
        losses: (map['losses'] as int?) ?? 0,
        goals: (map['goals'] as int?) ?? 0,
        assists: (map['assists'] as int?) ?? 0,
        vices: (map['vices'] as int?) ?? 0,
        finals: (map['finals'] as int?) ?? 0,
        titles: (map['titles'] as int?) ?? 0,
        seasonId: map['seasonId'] as String?,
        createdAt: DateTime.tryParse((map['createdAt'] as String?) ?? '') ?? DateTime.now(),
      );

  Player copyWith({
    String? name,
    String? description,
    String? photoPath,
    int? matchesPlayed,
    int? wins,
    int? losses,
    int? goals,
    int? assists,
    int? vices,
    int? finals,
    int? titles,
    String? seasonId,
  }) =>
      Player(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        photoPath: photoPath ?? this.photoPath,
        matchesPlayed: matchesPlayed ?? this.matchesPlayed,
        wins: wins ?? this.wins,
        losses: losses ?? this.losses,
        goals: goals ?? this.goals,
        assists: assists ?? this.assists,
        vices: vices ?? this.vices,
        finals: finals ?? this.finals,
        titles: titles ?? this.titles,
        seasonId: seasonId ?? this.seasonId,
        createdAt: createdAt,
      );

  Player resetForSeason({required String seasonId, String? newId}) => Player(
        id: newId ?? id,
        name: name,
        description: description,
        photoPath: photoPath,
        seasonId: seasonId,
      );
}

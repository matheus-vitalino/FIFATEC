class Season {
  final String id;
  String name;
  int year;
  bool isActive;
  DateTime startedAt;
  DateTime? finishedAt;
  String? goldenBallPlayerId;
  String? goldenBallPlayerName;
  double? goldenBallScore;

  Season({
    required this.id,
    required this.name,
    required this.year,
    this.isActive = true,
    DateTime? startedAt,
    this.finishedAt,
    this.goldenBallPlayerId,
    this.goldenBallPlayerName,
    this.goldenBallScore,
  }) : startedAt = startedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'year': year,
        'isActive': isActive ? 1 : 0,
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'goldenBallPlayerId': goldenBallPlayerId,
        'goldenBallPlayerName': goldenBallPlayerName,
        'goldenBallScore': goldenBallScore,
      };

  factory Season.fromMap(Map<String, dynamic> map) => Season(
        id: (map['id'] as String?) ?? '',
        name: (map['name'] as String?) ?? 'Temporada',
        year: (map['year'] as int?) ?? DateTime.now().year,
        isActive: (map['isActive'] as int? ?? 1) == 1,
        startedAt: DateTime.tryParse((map['startedAt'] as String?) ?? '') ?? DateTime.now(),
        finishedAt: map['finishedAt'] != null ? DateTime.tryParse(map['finishedAt'] as String) : null,
        goldenBallPlayerId: map['goldenBallPlayerId'] as String?,
        goldenBallPlayerName: map['goldenBallPlayerName'] as String?,
        goldenBallScore: (map['goldenBallScore'] as num?)?.toDouble(),
      );
}

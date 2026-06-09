import 'dart:math';

import 'package:uuid/uuid.dart';

import '../models/player.dart';
import '../models/team.dart';

class TeamDrawService {
  TeamDrawService({Random? random}) : _random = random ?? _safeRandom();

  final _uuid = const Uuid();
  final Random _random;

  static Random _safeRandom() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }

  static const _colors = [
    '#E53935', '#1E88E5', '#43A047', '#FB8C00',
    '#8E24AA', '#00ACC1', '#F4511E', '#6D4C41',
  ];

  static const _letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  /// Sorteio inteligente de times.
  ///
  /// Em vez de usar apenas shuffle(), ele gera várias possibilidades e escolhe
  /// a que menos repete jogadores que já caíram juntos em campeonatos anteriores.
  /// Quando balanceTeams estiver ativo, também tenta deixar a força dos times
  /// mais próxima sem deixar o sorteio previsível.
  List<Team> drawSmartTeams({
    required List<Player> players,
    required int teamSize,
    bool balanceTeams = false,
    List<List<String>> historyTeamGroups = const [],
    int attempts = 350,
  }) {
    if (players.isEmpty) return [];

    final safeTeamSize = max(1, teamSize);
    final teamCount = max(2, (players.length / safeTeamSize).ceil());
    final pairCounts = _buildPairCounts(historyTeamGroups);
    final signatureCounts = _buildSignatureCounts(historyTeamGroups);

    List<Team>? bestTeams;
    double bestScore = double.infinity;

    for (int i = 0; i < max(1, attempts); i++) {
      final targetSizes = _targetSizes(players.length, teamCount);
      final candidate = balanceTeams
          ? _buildBalancedCandidate(players, targetSizes, pairCounts)
          : _buildRandomCandidate(players, targetSizes);

      final score = _candidateScore(
        candidate,
        pairCounts,
        signatureCounts,
        playerPowerById: {for (final p in players) p.id: _playerPower(p)},
        balanceTeams: balanceTeams,
      );

      if (score < bestScore) {
        bestScore = score;
        bestTeams = candidate;
      }
    }

    return bestTeams ?? _buildRandomCandidate(players, _targetSizes(players.length, teamCount));
  }

  /// Gera confrontos de chaveamento simples.
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

  List<int> _targetSizes(int totalPlayers, int teamCount) {
    final base = totalPlayers ~/ teamCount;
    final remainder = totalPlayers % teamCount;
    final sizes = List.generate(
      teamCount,
      (i) => base + (i < remainder ? 1 : 0),
    );

    // Evita que o Time A sempre fique com a maior quantidade quando houver sobra.
    sizes.shuffle(_random);
    return sizes;
  }

  List<Team> _buildRandomCandidate(List<Player> players, List<int> targetSizes) {
    final shuffled = List<Player>.from(players)..shuffle(_random);
    final slots = List.generate(targetSizes.length, (_) => <Player>[]);

    int cursor = 0;
    for (int teamIndex = 0; teamIndex < targetSizes.length; teamIndex++) {
      for (int i = 0; i < targetSizes[teamIndex] && cursor < shuffled.length; i++) {
        slots[teamIndex].add(shuffled[cursor]);
        cursor++;
      }
    }

    return _toTeams(slots);
  }

  List<Team> _buildBalancedCandidate(
    List<Player> players,
    List<int> targetSizes,
    Map<String, int> pairCounts,
  ) {
    final salt = {for (final p in players) p.id: _random.nextDouble()};
    final ordered = List<Player>.from(players)
      ..sort((a, b) {
        final powerCompare = _playerPower(b).compareTo(_playerPower(a));
        if (powerCompare != 0) return powerCompare;
        return (salt[a.id] ?? 0).compareTo(salt[b.id] ?? 0);
      });

    final slots = List.generate(targetSizes.length, (_) => <Player>[]);
    final teamPowers = List<double>.filled(targetSizes.length, 0);

    for (final player in ordered) {
      final eligible = <int>[];
      for (int i = 0; i < targetSizes.length; i++) {
        if (slots[i].length < targetSizes[i]) eligible.add(i);
      }
      if (eligible.isEmpty) break;

      final pickSalt = {for (final index in eligible) index: _random.nextDouble()};
      double placementScore(int index) {
        return teamPowers[index] +
            (_historyPenaltyForAdding(player, slots[index], pairCounts) * 4.0) +
            (slots[index].length * 0.35) +
            (pickSalt[index] ?? 0);
      }

      eligible.sort((a, b) => placementScore(a).compareTo(placementScore(b)));

      // Escolhe entre os melhores candidatos, não sempre o primeiro.
      // Isso mantém o balanceamento, mas tira a sensação de sorteio robótico.
      final pickRange = min(2, eligible.length);
      final chosen = eligible[_random.nextInt(pickRange)];
      slots[chosen].add(player);
      teamPowers[chosen] += _playerPower(player);
    }

    return _toTeams(slots);
  }

  List<Team> _toTeams(List<List<Player>> slots) {
    return List.generate(slots.length, (i) {
      return Team(
        id: _uuid.v4(),
        name: 'Time ${_letter(i)}',
        color: _color(i),
        players: slots[i]
            .map((p) => TeamPlayer(playerId: p.id, playerName: p.name))
            .toList(),
      );
    });
  }

  double _candidateScore(
    List<Team> teams,
    Map<String, int> pairCounts,
    Map<String, int> signatureCounts, {
    required Map<String, double> playerPowerById,
    required bool balanceTeams,
  }) {
    double score = _random.nextDouble();
    final powers = <double>[];
    final sizes = <int>[];

    for (final team in teams) {
      final ids = team.activePlayers.map((p) => p.playerId).toList()..sort();
      final signature = _signature(ids);
      final repeatedExactTeam = signatureCounts[signature] ?? 0;
      score += repeatedExactTeam * 5000.0;

      for (int i = 0; i < ids.length - 1; i++) {
        for (int j = i + 1; j < ids.length; j++) {
          score += (pairCounts[_pairKey(ids[i], ids[j])] ?? 0) * 120.0;
        }
      }

      powers.add(team.activePlayers.fold<double>(
        0,
        (sum, tp) => sum + (playerPowerById[tp.playerId] ?? 0),
      ));
      sizes.add(ids.length);
    }

    if (sizes.isNotEmpty) {
      score += (_maxInt(sizes) - _minInt(sizes)) * 60.0;
    }

    if (balanceTeams && powers.isNotEmpty) {
      score += (_maxDouble(powers) - _minDouble(powers)) * 2.0;
    }

    return score;
  }

  int _historyPenaltyForAdding(
    Player player,
    List<Player> currentTeam,
    Map<String, int> pairCounts,
  ) {
    int penalty = 0;
    for (final teammate in currentTeam) {
      penalty += pairCounts[_pairKey(player.id, teammate.id)] ?? 0;
    }
    return penalty;
  }

  Map<String, int> _buildPairCounts(List<List<String>> historyTeamGroups) {
    final counts = <String, int>{};
    for (final group in historyTeamGroups) {
      final ids = group.where((id) => id.trim().isNotEmpty).toSet().toList()..sort();
      for (int i = 0; i < ids.length - 1; i++) {
        for (int j = i + 1; j < ids.length; j++) {
          final key = _pairKey(ids[i], ids[j]);
          counts[key] = (counts[key] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  Map<String, int> _buildSignatureCounts(List<List<String>> historyTeamGroups) {
    final counts = <String, int>{};
    for (final group in historyTeamGroups) {
      final ids = group.where((id) => id.trim().isNotEmpty).toSet().toList()..sort();
      if (ids.isEmpty) continue;
      final signature = _signature(ids);
      counts[signature] = (counts[signature] ?? 0) + 1;
    }
    return counts;
  }

  double _playerPower(Player p) {
    return (p.titles * 6.0) +
        (p.wins * 3.0) +
        (p.goals * 1.2) +
        (p.assists * 0.8) +
        (p.finals * 1.0);
  }

  String _pairKey(String a, String b) {
    return a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';
  }

  String _signature(List<String> ids) => ids.join('|');

  int _minInt(List<int> values) => values.reduce(min);
  int _maxInt(List<int> values) => values.reduce(max);
  double _minDouble(List<double> values) => values.reduce(min);
  double _maxDouble(List<double> values) => values.reduce(max);

  String _letter(int index) => _letters[index % _letters.length];
  String _color(int index) => _colors[index % _colors.length];
}

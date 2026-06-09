import 'package:uuid/uuid.dart';

import '../models/player.dart';
import '../models/season.dart';
import '../repositories/championship_repository.dart';
import '../repositories/match_repository.dart';
import '../repositories/player_repository.dart';
import '../repositories/settings_repository.dart';

class SeasonManager {
  SeasonManager._();
  static final SeasonManager instance = SeasonManager._();

  final _uuid = const Uuid();
  final SeasonRepository _seasonRepo = SeasonRepository();
  final SettingsRepository _settingsRepo = SettingsRepository();
  final PlayerRepository _playerRepo = PlayerRepository();
  final ChampionshipRepository _champRepo = ChampionshipRepository();
  final MatchRepository _matchRepo = MatchRepository();

  Future<List<Season>> getSeasons() => _seasonRepo.getAll();

  Future<Season?> getActiveSeason() => _seasonRepo.getActive();

  Future<Season> createNewSeason({String? name}) async {
    final year = DateTime.now().year;
    final desiredName = name ?? 'Temporada $year';

    // Resolve duplicatas: se já existe temporada com mesmo nome, adiciona índice
    final all = await _seasonRepo.getAll();
    final sameNames = all.where((s) => s.name == desiredName || s.name.startsWith('$desiredName.')).toList();
    String finalName = desiredName;
    if (sameNames.isNotEmpty) {
      // Encontra o maior índice existente
      int maxIdx = 0;
      for (final s in all) {
        if (s.name == desiredName) {
          if (maxIdx == 0) maxIdx = 1;
        } else {
          final regex = RegExp(r'^' + RegExp.escape(desiredName) + r'\.(\d+)$');
          final match = regex.firstMatch(s.name);
          if (match != null) {
            final idx = int.tryParse(match.group(1) ?? '0') ?? 0;
            if (idx > maxIdx) maxIdx = idx;
          }
        }
      }
      finalName = '$desiredName.${maxIdx + 1}';
    }

    final season = Season(
      id: _uuid.v4(),
      name: finalName,
      year: year,
      isActive: true,
    );

    await _seasonRepo.save(season);
    await _settingsRepo.setActiveSeason(season.id);
    await _playerRepo.ensureSeasonStatsForAllPlayers(season.id);

    return season;
  }

  Future<Season?> switchSeason(String seasonId) async {
    await _seasonRepo.setActiveSeason(seasonId);
    return _seasonRepo.getById(seasonId);
  }

  Future<void> deleteSeason(String seasonId) async {
    final champs = await _champRepo.getAll(seasonId: seasonId);
    for (final champ in champs) {
      final matches = await _matchRepo.getByChampionship(champ.id);
      for (final match in matches) {
        await _matchRepo.delete(match.id);
      }
      await _champRepo.delete(champ.id);
    }

    await _playerRepo.resetStatsBySeason(seasonId);
    await _seasonRepo.deleteSeason(seasonId);

    final remaining = await _seasonRepo.getAll();
    if (remaining.isNotEmpty) {
      await _seasonRepo.setActiveSeason(remaining.first.id);
    } else {
      await _settingsRepo.setActiveSeason(null);
    }
  }

  int comparePlayersBySeasonRanking(Player a, Player b) {
    final wins = b.wins.compareTo(a.wins);
    if (wins != 0) return wins;

    final goals = b.goals.compareTo(a.goals);
    if (goals != 0) return goals;

    final titles = b.titles.compareTo(a.titles);
    if (titles != 0) return titles;

    final assists = b.assists.compareTo(a.assists);
    if (assists != 0) return assists;

    final matches = b.matchesPlayed.compareTo(a.matchesPlayed);
    if (matches != 0) return matches;

    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  Future<void> saveSeason(Season season) => _seasonRepo.save(season);

  Future<Season?> finishSeason(String seasonId) async {
    final season = await _seasonRepo.getById(seasonId);
    if (season == null) return null;

    final players = await _playerRepo.getPlayersForSeason(season.id);
    if (players.isNotEmpty) {
      final ranking = [...players]..sort(comparePlayersBySeasonRanking);
      final winner = ranking.first;
      season.goldenBallPlayerId = winner.id;
      season.goldenBallPlayerName = winner.name;
      season.goldenBallScore = winner.wins.toDouble();
    } else {
      season.goldenBallPlayerId = null;
      season.goldenBallPlayerName = null;
      season.goldenBallScore = null;
    }

    season.finishedAt = DateTime.now();
    season.isActive = false;

    await _seasonRepo.save(season);

    // Se era a temporada ativa nas settings, limpa para não apontar para uma finalizada
    final settings = await _settingsRepo.get();
    if (settings.activeSeasonId == seasonId) {
      // Tenta ativar outra temporada em andamento, senão limpa
      final all = await _seasonRepo.getAll();
      final other = all.where((s) => s.id != seasonId && s.finishedAt == null).toList();
      if (other.isNotEmpty) {
        await _seasonRepo.setActiveSeason(other.first.id);
      } else {
        await _settingsRepo.setActiveSeason(null);
      }
    }

    return season;
  }

  Future<Season?> finishCurrentSeason() async {
    final season = await _seasonRepo.getActive();
    if (season == null) return null;
    return finishSeason(season.id);
  }
}

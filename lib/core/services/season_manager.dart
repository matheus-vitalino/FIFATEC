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
    final current = await _seasonRepo.getActive();
    if (current != null && current.finishedAt == null) {
      await finishSeason(current.id);
    }

    final sourcePlayers = current == null ? <Player>[] : await _playerRepo.getAll(seasonId: current.id);
    final year = DateTime.now().year;
    final season = Season(
      id: _uuid.v4(),
      name: name ?? 'Temporada $year',
      year: year,
      isActive: true,
    );
    await _seasonRepo.save(season);
    await _settingsRepo.setActiveSeason(season.id);

    for (final p in sourcePlayers) {
      await _playerRepo.save(p.resetForSeason(seasonId: season.id, newId: _uuid.v4()));
    }

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
    await _playerRepo.deleteBySeason(seasonId);
    await _seasonRepo.deleteSeason(seasonId);

    final remaining = await _seasonRepo.getAll();
    if (remaining.isNotEmpty) {
      await _seasonRepo.setActiveSeason(remaining.first.id);
    } else {
      await _settingsRepo.setActiveSeason(null);
    }
  }

  double scoreForPlayer(Player p) {
    final matches = p.matchesPlayed <= 0 ? 1 : p.matchesPlayed;
    final goalRate = p.goals / matches;
    final assistRate = p.assists / matches;
    final winRate = p.wins / matches;
    final titleRate = p.titles / matches;
    final finalRate = p.finals / matches;
    return (goalRate * 5.0) + (assistRate * 2.0) + (winRate * 1.2) + (titleRate * 2.4) + (finalRate * 0.8);
  }

  /// Salva uma temporada (p.ex. após renomear)
  Future<void> saveSeason(Season season) => _seasonRepo.save(season);

  Future<Season?> finishSeason(String seasonId) async {
    final season = await _seasonRepo.getById(seasonId);
    if (season == null) return null;
    final players = await _playerRepo.getAll(seasonId: season.id);
    if (players.isNotEmpty) {
      final ranking = [...players]..sort((a, b) => scoreForPlayer(b).compareTo(scoreForPlayer(a)));
      final winner = ranking.first;
      season.goldenBallPlayerId = winner.id;
      season.goldenBallPlayerName = winner.name;
      season.goldenBallScore = scoreForPlayer(winner);
    }
    season.isActive = false;
    season.finishedAt = DateTime.now();
    await _seasonRepo.save(season);
    if (seasonId == (await _settingsRepo.get()).activeSeasonId) {
      await _settingsRepo.setActiveSeason(season.id);
    }
    return season;
  }

  Future<Season?> finishCurrentSeason() async {
    final season = await _seasonRepo.getActive();
    if (season == null) return null;
    return finishSeason(season.id);
  }
}

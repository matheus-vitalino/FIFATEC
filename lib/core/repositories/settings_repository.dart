import '../database/database_helper.dart';
import '../models/app_settings.dart';
import '../models/season.dart';

class SettingsRepository {
  final DatabaseHelper _db = DatabaseHelper();

  Future<AppSettings> get() async {
    final row = await _db.getSettings();
    return row != null ? AppSettings.fromMap(row) : AppSettings();
  }

  Future<void> save(AppSettings settings) async {
    await _db.saveSettings(settings.toMap());
  }

  Future<void> setActiveSeason(String? seasonId) async {
    final settings = await get();
    await save(settings.copyWith(activeSeasonId: seasonId, clearActiveSeasonId: seasonId == null));
  }
}

class SeasonRepository {
  final DatabaseHelper _db = DatabaseHelper();
  final SettingsRepository _settingsRepo = SettingsRepository();

  Future<List<Season>> getAll() async {
    final rows = await _db.getAllSeasons();
    final seasons = rows.map(Season.fromMap).toList();
    seasons.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return seasons;
  }

  Future<Season?> getById(String id) async {
    try {
      return (await getAll()).firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<Season?> getActive() async {
    final settings = await _settingsRepo.get();
    if (settings.activeSeasonId != null) {
      final byId = await getById(settings.activeSeasonId!);
      if (byId != null) return byId;
    }
    final all = await getAll();
    try {
      return all.firstWhere((s) => s.isActive);
    } catch (_) {
      return all.isNotEmpty ? all.first : null;
    }
  }

  Future<void> save(Season season) async {
    await _db.saveSeason(season.id, season.toMap());
  }

  Future<Season> ensureCurrentSeason() async {
    final active = await getActive();
    if (active != null) return active;
    final year = DateTime.now().year;
    final season = Season(
      id: 'season_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Temporada $year',
      year: year,
      isActive: true,
    );
    await save(season);
    await _settingsRepo.setActiveSeason(season.id);
    return season;
  }

  Future<void> setActiveSeason(String seasonId) async {
    final seasons = await getAll();
    for (final s in seasons) {
      s.isActive = s.id == seasonId;
      await save(s);
    }
    await _settingsRepo.setActiveSeason(seasonId);
  }

  Future<void> deleteSeason(String id) async {
    await _db.deleteSeason(id);
  }
}

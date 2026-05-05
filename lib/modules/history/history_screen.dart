import 'package:flutter/material.dart';
import 'dart:io';
import '../../core/constants/app_colors.dart';
import '../../core/models/championship.dart';
import '../../core/models/match.dart';
import '../../core/models/season.dart';
import '../../core/repositories/championship_repository.dart';
import '../../core/repositories/match_repository.dart';
import '../../core/services/season_manager.dart';
import '../../core/utils/date_utils.dart';
import '../../shared/widgets/custom_app_bar.dart';
import '../../shared/widgets/full_screen_photo_view.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with SingleTickerProviderStateMixin {
  final _champRepo = ChampionshipRepository();
  final _matchRepo = MatchRepository();
  final _seasonManager = SeasonManager.instance;
  List<Championship> _champs = [];
  List<MatchModel> _matches = [];
  List<Season> _seasons = [];
  Season? _selectedSeason;
  bool _loading = true;
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _seasons = await _seasonManager.getSeasons();
    _selectedSeason = await _seasonManager.getActiveSeason();
    _selectedSeason ??= _seasons.isNotEmpty ? _seasons.first : null;
    _champs = _selectedSeason == null
        ? []
        : (await _champRepo.getAll(seasonId: _selectedSeason!.id)).where((c) => c.status == ChampionshipStatus.finished).toList()
          ..sort((a, b) => (b.finishedAt ?? b.createdAt).compareTo(a.finishedAt ?? a.createdAt));
    _matches = _selectedSeason == null
        ? []
        : (await _matchRepo.getAll(seasonId: _selectedSeason!.id)).where((m) => m.status == MatchStatus.finished).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _changeSeason(Season season) async {
    await _seasonManager.switchSeason(season.id);
    _selectedSeason = season;
    await _load();
  }

  Future<void> _deleteChampionship(Championship champ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Excluir campeonato?', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'O campeonato "${champ.name}" e todas as suas partidas serão apagados permanentemente.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir', style: TextStyle(color: AppColors.loss)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // Remove todas as partidas do campeonato
    for (final matchId in champ.matchIds) {
      await _matchRepo.delete(matchId);
    }
    await _champRepo.delete(champ.id);
    if (mounted) _load();
  }

  void _openWinnerPhoto(String path, String title) {
    if (!File(path).existsSync()) return;
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => FullScreenPhotoView(photoPath: path, title: title),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'Histórico',
        bottomHeight: 48,
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textHint,
          tabs: const [Tab(text: 'Campeonatos'), Tab(text: 'Partidas')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : Column(
              children: [
                _SeasonFilter(
                  seasons: _seasons,
                  selectedSeason: _selectedSeason,
                  onChanged: _changeSeason,
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [_buildChamps(), _buildMatches()],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildChamps() {
    if (_champs.isEmpty) {
      return const EmptyState(
        icon: Icons.emoji_events_outlined,
        title: 'Nenhum campeonato finalizado',
        subtitle: 'Finalize um campeonato para ver aqui',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _champs.length,
      itemBuilder: (_, i) {
        final c = _champs[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.accent.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.emoji_events_rounded, color: AppColors.accent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(c.name, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15))),
                  Text(AppDateUtils.formatDate(c.finishedAt ?? c.createdAt), style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 6),
              Text('Temporada: ${_selectedSeason?.name ?? ''}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              if (c.winnerName != null || (c.winnerPhotoPath != null && File(c.winnerPhotoPath!).existsSync())) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (c.winnerPhotoPath != null && File(c.winnerPhotoPath!).existsSync())
                      GestureDetector(
                        onTap: () => _openWinnerPhoto(c.winnerPhotoPath!, c.winnerName ?? c.name),
                        child: Hero(
                          tag: c.winnerPhotoPath!,
                          child: Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.accent.withOpacity(0.45), width: 2),
                              color: AppColors.surfaceLight,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.file(
                                File(c.winnerPhotoPath!),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _winnerPhotoPlaceholder(),
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.surfaceLight),
                        ),
                        child: _winnerPhotoPlaceholder(),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(color: AppColors.accent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.military_tech_rounded, color: AppColors.accent, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text("Campeão: ${c.winnerName ?? '—'}", style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  _info(Icons.group_rounded, '${c.teams.length} times'),
                  const SizedBox(width: 12),
                  _info(Icons.sports_soccer, '${c.matchIds.length} partidas'),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pushNamed(context, '/championship/detail', arguments: c.id),
                    child: const Row(
                      children: [
                        Text('Ver detalhes', style: TextStyle(color: AppColors.accent, fontSize: 12)),
                        Icon(Icons.chevron_right_rounded, color: AppColors.accent, size: 14),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.loss, size: 20),
                    tooltip: 'Excluir campeonato',
                    onPressed: () => _deleteChampionship(c),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _winnerPhotoPlaceholder() => const Icon(Icons.emoji_events_rounded, color: AppColors.textHint, size: 24);

  Widget _buildMatches() {
    if (_matches.isEmpty) {
      return const EmptyState(
        icon: Icons.sports_soccer_outlined,
        title: 'Nenhuma partida finalizada',
        subtitle: 'As partidas finalizadas aparecerão aqui',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _matches.length,
      itemBuilder: (_, i) {
        final m = _matches[i];
        final aScore = m.teamAScore;
        final bScore = m.teamBScore;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.surfaceLight),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(m.teamA.name, style: TextStyle(
                      color: m.winnerId == m.teamA.id ? AppColors.win : AppColors.textPrimary,
                      fontWeight: FontWeight.bold, fontSize: 14,
                    ), textAlign: TextAlign.center),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$aScore × $bScore', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 20)),
                  ),
                  Expanded(
                    child: Text(m.teamB.name, style: TextStyle(
                      color: m.winnerId == m.teamB.id ? AppColors.win : AppColors.textPrimary,
                      fontWeight: FontWeight.bold, fontSize: 14,
                    ), textAlign: TextAlign.center),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _info(Icons.calendar_today_rounded, AppDateUtils.formatDateTime(m.date)),
                  Row(
                    children: [
                      if (m.isDraw) _badge('Empate', AppColors.draw) else if (m.isPenalty) _badge('Pênaltis', AppColors.draw) else if (m.winnerId != null) Row(children: [
                        const Icon(Icons.emoji_events_rounded, size: 12, color: AppColors.accent),
                        const SizedBox(width: 4),
                        Text(m.winnerId == m.teamA.id ? m.teamA.name : m.teamB.name, style: const TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete_rounded, color: AppColors.loss, size: 18),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              backgroundColor: AppColors.card,
                              title: const Text('Excluir partida?', style: TextStyle(color: AppColors.textPrimary)),
                              content: const Text('A partida será apagada do histórico.', style: TextStyle(color: AppColors.textSecondary)),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Excluir', style: TextStyle(color: AppColors.loss))),
                              ],
                            ),
                          );
                          if (ok == true) {
                            final champ = await _champRepo.getById(m.championshipId);
                            if (champ != null) {
                              champ.matchIds.remove(m.id);
                              await _champRepo.save(champ);
                            }
                            await _matchRepo.delete(m.id);
                            if (mounted) _load();
                          }
                        },
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ],
              ),
              if (m.goals.isNotEmpty) ...[
                const Divider(color: AppColors.surfaceLight, height: 16),
                ...m.goals.map((g) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    children: [
                      const Icon(Icons.sports_soccer, size: 12, color: AppColors.goal),
                      const SizedBox(width: 6),
                      Text(g.playerName, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      if (m.showGoalTime) ...[
                        const SizedBox(width: 6),
                        Text(AppDateUtils.formatDuration(g.timeSeconds), style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
                      ],
                    ],
                  ),
                )),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _info(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textHint),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        ],
      );

  Widget _badge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
        child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
      );

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }
}

class _SeasonFilter extends StatelessWidget {
  final List<Season> seasons;
  final Season? selectedSeason;
  final ValueChanged<Season> onChanged;

  const _SeasonFilter({required this.seasons, required this.selectedSeason, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (seasons.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Nenhuma temporada disponível', style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: DropdownButtonFormField<String>(
        value: selectedSeason?.id,
        decoration: const InputDecoration(labelText: 'Temporada no histórico'),
        dropdownColor: AppColors.surface,
        items: seasons.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
        onChanged: (id) {
          if (id == null) return;
          onChanged(seasons.firstWhere((s) => s.id == id));
        },
      ),
    );
  }
}

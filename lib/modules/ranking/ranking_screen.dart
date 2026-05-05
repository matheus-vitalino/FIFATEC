import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/player.dart';
import '../../core/models/season.dart';
import '../../core/repositories/player_repository.dart';
import '../../core/services/season_manager.dart';
import '../../shared/widgets/custom_app_bar.dart';
import '../../shared/widgets/player_avatar.dart';

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> with SingleTickerProviderStateMixin {
  final _playerRepo = PlayerRepository();
  final _seasonManager = SeasonManager.instance;
  List<Player> _players = [];
  List<Season> _seasons = [];
  Season? _selectedSeason;
  bool _loading = true;
  bool _busy = false;
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _seasons = await _seasonManager.getSeasons();
    _selectedSeason = await _seasonManager.getActiveSeason();
    _selectedSeason ??= _seasons.isNotEmpty ? _seasons.first : null;
    _players = _selectedSeason == null ? [] : await _playerRepo.getAll(seasonId: _selectedSeason!.id);
    if (mounted) setState(() => _loading = false);
  }

  List<Player> get _byGoals => [..._players]..sort((a, b) => b.goals.compareTo(a.goals));
  List<Player> get _byWins => [..._players]..sort((a, b) => b.wins.compareTo(a.wins));
  List<Player> get _byTitles => [..._players]..sort((a, b) => b.titles.compareTo(a.titles));

  List<_Duo> get _bestDuos {
    final Map<String, _Duo> duos = {};
    for (int i = 0; i < _players.length - 1; i++) {
      for (int j = i + 1; j < _players.length; j++) {
        final key = '${_players[i].id}_${_players[j].id}';
        // Score = títulos combinados (base) + bônus de vitórias
        final score = (_players[i].titles + _players[j].titles) * 10
            + _players[i].wins + _players[j].wins;
        duos[key] = _Duo(_players[i], _players[j], score);
      }
    }
    final list = duos.values.toList()..sort((a, b) => b.score.compareTo(a.score));
    return list.where((d) => d.score > 0).take(10).toList();
  }

  List<_Trio> get _bestTrios {
    final Map<String, _Trio> trios = {};
    for (int i = 0; i < _players.length - 2; i++) {
      for (int j = i + 1; j < _players.length - 1; j++) {
        for (int k = j + 1; k < _players.length; k++) {
          final a = _players[i], b = _players[j], c = _players[k];
          final key = '${a.id}_${b.id}_${c.id}';
          final score = (a.titles + b.titles + c.titles) * 10
              + a.wins + b.wins + c.wins;
          trios[key] = _Trio(a, b, c, score);
        }
      }
    }
    final list = trios.values.toList()..sort((a, b) => b.score.compareTo(a.score));
    return list.where((t) => t.score > 0).take(10).toList();
  }

  Future<void> _selectSeason(Season season) async {
    setState(() => _busy = true);
    await _seasonManager.switchSeason(season.id);
    _selectedSeason = season;
    _players = await _playerRepo.getAll(seasonId: season.id);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _selectCurrentSeason() async {
    final active = await _seasonManager.getActiveSeason();
    if (active != null) await _selectSeason(active);
  }

  Future<void> _createSeason() async {
    setState(() => _busy = true);
    final season = await _seasonManager.createNewSeason();
    _selectedSeason = season;
    _seasons = await _seasonManager.getSeasons();
    _players = await _playerRepo.getAll(seasonId: season.id);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _finishSeason() async {
    if (_selectedSeason == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Finalizar temporada?', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Tem certeza que deseja finalizar a temporada "${_selectedSeason!.name}"?\n\nEssa ação não pode ser desfeita.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.loss),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final season = await _seasonManager.finishSeason(_selectedSeason!.id);
    if (season != null) {
      _selectedSeason = season;
      _seasons = await _seasonManager.getSeasons();
      _players = await _playerRepo.getAll(seasonId: season.id);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _deleteSeason() async {
    if (_selectedSeason == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Excluir temporada?', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Todos os dados desta temporada serão apagados.\n\n${_selectedSeason!.name}',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Excluir', style: TextStyle(color: AppColors.loss))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    await _seasonManager.deleteSeason(_selectedSeason!.id);
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _goPreviousSeason() async {
    if (_seasons.isEmpty || _selectedSeason == null) return;
    final idx = _seasons.indexWhere((s) => s.id == _selectedSeason!.id);
    if (idx < 0 || idx >= _seasons.length - 1) return;
    await _selectSeason(_seasons[idx + 1]);
  }

  Future<void> _renameSeason() async {
    if (_selectedSeason == null) return;
    final ctrl = TextEditingController(text: _selectedSeason!.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Renomear temporada', style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nome da temporada'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    _selectedSeason!.name = ctrl.text.trim();
    await _seasonManager.saveSeason(_selectedSeason!);
    _seasons = await _seasonManager.getSeasons();
    if (mounted) setState(() {});
  }

  String _seasonLabel(Season? s) {
    if (s == null) return 'Nenhuma temporada';
    final status = s.finishedAt != null ? 'Finalizada' : s.isActive ? 'Ativa' : 'Arquivada';
    return '${s.name} • $status';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'Temporada',
        bottomHeight: 48,
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textHint,
          tabs: const [Tab(text: 'Jogadores'), Tab(text: 'Duplas'), Tab(text: 'Trios'), Tab(text: 'Categorias')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : Column(
              children: [
                _SeasonPanel(
                  label: _seasonLabel(_selectedSeason),
                  seasons: _seasons,
                  selectedSeasonId: _selectedSeason?.id,
                  onSeasonSelected: _selectSeason,
                  onCurrentSeason: _selectCurrentSeason,
                  onCreateSeason: _busy ? null : _createSeason,
                  onRenameSeason: _busy ? null : _renameSeason,
                  onPreviousSeason: _busy ? null : _goPreviousSeason,
                  onDeleteSeason: _busy ? null : _deleteSeason,
                  onFinishSeason: _busy ? null : _finishSeason,
                ),
                if (_selectedSeason?.goldenBallPlayerName != null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.accent.withOpacity(0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.military_tech_rounded, color: AppColors.accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Bola de Ouro: ${_selectedSeason!.goldenBallPlayerName}',
                            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (_selectedSeason!.goldenBallScore != null)
                          Text(_selectedSeason!.goldenBallScore!.toStringAsFixed(2), style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
                      ],
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [_buildPlayerRanking(), _buildDuoRanking(), _buildTrioRanking(), _buildCategoryRanking()],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPlayerRanking() {
    final players = _byWins;
    if (players.isEmpty) {
      return const EmptyState(
        icon: Icons.leaderboard,
        title: 'Sem dados nesta temporada',
        subtitle: 'Crie uma temporada e jogue partidas para gerar o ranking',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: players.length,
      itemBuilder: (_, i) {
        final p = players[i];
        return _RankCard(
          position: i + 1,
          name: p.name,
          photoPath: p.photoPath,
          subtitle: '${p.wins} vitórias • ${p.goals} gols • ${p.assists} assistências',
          value: p.wins,
          valueLabel: 'V',
          index: i,
          onTap: () => Navigator.pushNamed(context, '/players/profile', arguments: p.id),
        );
      },
    );
  }

  Widget _buildDuoRanking() {
    final duos = _bestDuos;
    if (duos.isEmpty) {
      return const EmptyState(icon: Icons.people_rounded, title: 'Sem duplas', subtitle: 'Adicione mais jogadores');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: duos.length,
      itemBuilder: (_, i) => _DuoCard(duo: duos[i], position: i + 1, index: i),
    );
  }

  Widget _buildTrioRanking() {
    final trios = _bestTrios;
    if (trios.isEmpty) {
      return const EmptyState(
        icon: Icons.people_rounded,
        title: 'Sem dados de trios',
        subtitle: 'Jogue partidas para gerar o ranking de trios',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: trios.length,
      itemBuilder: (_, i) => _TrioCard(trio: trios[i], position: i + 1, index: i),
    );
  }

  Widget _buildCategoryRanking() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _CategorySection(title: '🥅 Artilheiros', color: AppColors.goal, players: _byGoals.take(5).toList(), valueLabel: (p) => '${p.goals} gols'),
        const SizedBox(height: 16),
        _CategorySection(title: '🏆 Títulos', color: AppColors.accent, players: _byTitles.take(5).toList(), valueLabel: (p) => '${p.titles} títulos'),
        const SizedBox(height: 16),
        _CategorySection(title: '💪 Mais Vitórias', color: AppColors.win, players: _byWins.take(5).toList(), valueLabel: (p) => '${p.wins} vitórias'),
      ],
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }
}

class _SeasonPanel extends StatelessWidget {
  final String label;
  final List<Season> seasons;
  final String? selectedSeasonId;
  final ValueChanged<Season> onSeasonSelected;
  final VoidCallback onCurrentSeason;
  final VoidCallback? onCreateSeason;
  final VoidCallback? onRenameSeason;
  final VoidCallback? onPreviousSeason;
  final VoidCallback? onDeleteSeason;
  final VoidCallback? onFinishSeason;

  const _SeasonPanel({
    required this.label,
    required this.seasons,
    required this.selectedSeasonId,
    required this.onSeasonSelected,
    required this.onCurrentSeason,
    this.onCreateSeason,
    this.onRenameSeason,
    this.onPreviousSeason,
    this.onDeleteSeason,
    this.onFinishSeason,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_note_rounded, color: AppColors.accent, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold))),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: selectedSeasonId,
            decoration: const InputDecoration(labelText: 'Selecionar temporada'),
            dropdownColor: AppColors.surface,
            items: seasons.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
            onChanged: (id) {
              if (id == null) return;
              final season = seasons.firstWhere((s) => s.id == id);
              onSeasonSelected(season);
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionChip(label: 'Temporada atual', icon: Icons.refresh_rounded, onTap: onCurrentSeason),
              _ActionChip(label: 'Renomear', icon: Icons.edit_rounded, onTap: onRenameSeason),
              _ActionChip(label: 'Nova temporada', icon: Icons.add_rounded, onTap: onCreateSeason),
              _ActionChip(label: 'Temporada anterior', icon: Icons.arrow_back_rounded, onTap: onPreviousSeason),
              _ActionChip(label: 'Excluir', icon: Icons.delete_rounded, onTap: onDeleteSeason, danger: true),
              _ActionChip(label: 'Finalizar', icon: Icons.flag_rounded, onTap: onFinishSeason),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool danger;

  const _ActionChip({required this.label, required this.icon, this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.loss : AppColors.accent;
    return ActionChip(
      label: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      avatar: Icon(icon, size: 16, color: color),
      backgroundColor: color.withOpacity(0.12),
      side: BorderSide(color: color.withOpacity(0.25)),
      onPressed: onTap,
    );
  }
}

class _Trio {
  final Player a, b, c;
  final int score;
  const _Trio(this.a, this.b, this.c, this.score);
}

class _TrioCard extends StatelessWidget {
  final _Trio trio;
  final int position, index;
  const _TrioCard({required this.trio, required this.position, required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('#$position', style: const TextStyle(
              color: AppColors.textHint, fontWeight: FontWeight.bold, fontSize: 13,
            ), textAlign: TextAlign.center),
          ),
          const SizedBox(width: 8),
          // Três avatares sobrepostos
          SizedBox(
            width: 80,
            height: 40,
            child: Stack(
              children: [
                PlayerAvatar(photoPath: trio.a.photoPath, name: trio.a.name, size: 38),
                Positioned(left: 22, child: PlayerAvatar(photoPath: trio.b.photoPath, name: trio.b.name, size: 38)),
                Positioned(left: 44, child: PlayerAvatar(photoPath: trio.c.photoPath, name: trio.c.name, size: 38)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${trio.a.name}, ${trio.b.name} & ${trio.c.name}',
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${trio.a.titles + trio.b.titles + trio.c.titles} títulos combinados',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Text('${trio.score}', style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 18)),
              const Text('pts', style: TextStyle(color: AppColors.textHint, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Duo {
  final Player a, b;
  final int score;
  const _Duo(this.a, this.b, this.score);
}

class _RankCard extends StatelessWidget {
  final int position;
  final String name;
  final String? photoPath;
  final String subtitle;
  final int value;
  final String valueLabel;
  final int index;
  final VoidCallback? onTap;

  const _RankCard({
    required this.position,
    required this.name,
    this.photoPath,
    required this.subtitle,
    required this.value,
    required this.valueLabel,
    required this.index,
    this.onTap,
  });

  Color get _medalColor {
    if (position == 1) return const Color(0xFFFFD700);
    if (position == 2) return const Color(0xFFC0C0C0);
    if (position == 3) return const Color(0xFFCD7F32);
    return AppColors.textHint;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: position <= 3 ? _medalColor.withOpacity(0.4) : AppColors.surfaceLight),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: position <= 3
                  ? Text(position == 1 ? '🥇' : position == 2 ? '🥈' : '🥉', style: const TextStyle(fontSize: 22), textAlign: TextAlign.center)
                  : Text('#$position', style: TextStyle(color: _medalColor, fontWeight: FontWeight.bold, fontSize: 14), textAlign: TextAlign.center),
            ),
            const SizedBox(width: 12),
            PlayerAvatar(photoPath: photoPath, name: name, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
              child: Column(
                children: [
                  Text('$value', style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 18)),
                  Text(valueLabel, style: const TextStyle(color: AppColors.textHint, fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ).animate().fadeIn(delay: Duration(milliseconds: index * 40), duration: 300.ms),
    );
  }
}


class _DuoCard extends StatelessWidget {
  final _Duo duo;
  final int position, index;

  const _DuoCard({required this.duo, required this.position, required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: position <= 3 ? AppColors.accent.withOpacity(0.35) : AppColors.surfaceLight),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '#$position',
              style: const TextStyle(
                color: AppColors.textHint,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 58,
            height: 40,
            child: Stack(
              children: [
                PlayerAvatar(photoPath: duo.a.photoPath, name: duo.a.name, size: 38),
                Positioned(
                  left: 20,
                  child: PlayerAvatar(photoPath: duo.b.photoPath, name: duo.b.name, size: 38),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${duo.a.name} & ${duo.b.name}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${duo.a.titles + duo.b.titles} títulos combinados',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Text(
                '${duo.score}',
                style: const TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const Text('pts', style: TextStyle(color: AppColors.textHint, fontSize: 10)),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: Duration(milliseconds: index * 40), duration: 300.ms);
  }
}

class _CategorySection extends StatelessWidget
 {
  final String title;
  final Color color;
  final List<Player> players;
  final String Function(Player) valueLabel;

  const _CategorySection({required this.title, required this.color, required this.players, required this.valueLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          if (players.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: Text('Sem dados', style: TextStyle(color: AppColors.textSecondary)),
            )
          else
            ...players.asMap().entries.map((entry) {
              final i = entry.key;
              final p = entry.value;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.surfaceLight.withOpacity(0.5)))),
                child: Row(
                  children: [
                    Text('${i + 1}', style: const TextStyle(color: AppColors.textHint, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(p.name, style: const TextStyle(color: AppColors.textPrimary))),
                    Text(valueLabel(p), style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
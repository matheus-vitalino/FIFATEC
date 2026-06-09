import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/player.dart';
import '../../core/repositories/player_repository.dart';
import '../../shared/widgets/custom_app_bar.dart';
import '../../shared/widgets/player_avatar.dart';

class PlayersScreen extends StatefulWidget {
  const PlayersScreen({super.key});

  @override
  State<PlayersScreen> createState() => _PlayersScreenState();
}

class _PlayersScreenState extends State<PlayersScreen> {
  final _repo = PlayerRepository();
  List<Player> _players = [];
  String _search = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _players = await _repo.getAll();
    setState(() => _loading = false);
  }

  List<Player> get _filtered => _players
      .where((p) => p.name.toLowerCase().contains(_search.toLowerCase()))
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'Jogadores',
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.accent),
            onPressed: () async {
              await Navigator.pushNamed(context, '/players/form');
              _load();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Buscar jogador...',
                prefixIcon: const Icon(Icons.search, color: AppColors.textHint),
                filled: true,
                fillColor: AppColors.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                : _filtered.isEmpty
                    ? EmptyState(
                        icon: Icons.person_outline,
                        title: _search.isEmpty ? 'Nenhum jogador' : 'Nenhum resultado',
                        subtitle: _search.isEmpty
                            ? 'Toque no + para adicionar jogadores'
                            : 'Tente outro nome',
                      )
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).padding.bottom + 80),
                        itemCount: _filtered.length,
                        itemBuilder: (context, i) {
                          final p = _filtered[i];
                          return _PlayerCard(
                            player: p,
                            index: i,
                            onTap: () async {
                              await Navigator.pushNamed(context, '/players/profile', arguments: p.id);
                              _load();
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.pushNamed(context, '/players/form');
          _load();
        },
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Novo Jogador'),
        backgroundColor: AppColors.primary,
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  final Player player;
  final int index;
  final VoidCallback onTap;

  const _PlayerCard({required this.player, required this.index, required this.onTap});

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
          border: Border.all(color: AppColors.surfaceLight),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            PlayerAvatar(photoPath: player.photoPath, name: player.name, size: 50, showBorder: true),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(player.name, style: const TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15,
                  )),
                  if (player.description != null && player.description!.isNotEmpty)
                    Text(player.description!, style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12,
                    ), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _mini(Icons.sports_soccer, '${player.goals}', AppColors.goal),
                      const SizedBox(width: 10),
                      _mini(Icons.emoji_events, '${player.titles}', AppColors.accent),
                      const SizedBox(width: 10),
                      _mini(Icons.sports_kabaddi, '${player.matchesPlayed}', AppColors.textHint),
                      if (player.ownGoals > 0) ...[
                        const SizedBox(width: 10),
                        _mini(Icons.warning_rounded, '${player.ownGoals}', AppColors.loss),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
          ],
        ),
      ),
    ).animate().fadeIn(delay: Duration(milliseconds: index * 40), duration: 300.ms);
  }

  Widget _mini(IconData icon, String value, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      );
}
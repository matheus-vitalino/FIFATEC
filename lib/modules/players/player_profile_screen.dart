import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/player.dart';
import '../../core/repositories/player_repository.dart';
import '../../core/services/image_service.dart';
import '../../shared/widgets/custom_app_bar.dart';
import '../../shared/widgets/player_avatar.dart';
import '../../shared/widgets/stat_card.dart';

class PlayerProfileScreen extends StatefulWidget {
  final String playerId;
  const PlayerProfileScreen({super.key, required this.playerId});

  @override
  State<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends State<PlayerProfileScreen> {
  final _repo = PlayerRepository();
  final _imgService = ImageService();
  Player? _player;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _player = await _repo.getById(widget.playerId);
    setState(() => _loading = false);
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Excluir jogador?', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Tem certeza que deseja excluir ${_player?.name}?',
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
    if (ok == true && _player != null) {
      await _imgService.deleteImage(_player!.photoPath);
      await _repo.delete(_player!.id);
      if (mounted) Navigator.pop(context);
    }
  }

  double get _winRate {
    if (_player == null || _player!.matchesPlayed == 0) return 0;
    return (_player!.wins / _player!.matchesPlayed) * 100;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'Perfil',
        actions: [
          if (_player != null) ...[
            IconButton(
              icon: const Icon(Icons.edit_rounded, color: AppColors.accent),
              onPressed: () async {
                await Navigator.pushNamed(context, '/players/edit', arguments: _player!.id);
                _load();
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_rounded, color: AppColors.loss),
              onPressed: _confirmDelete,
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : _player == null
              ? const EmptyState(icon: Icons.error, title: 'Não encontrado', subtitle: '')
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final p = _player!;
    return SingleChildScrollView(
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1A2634), Color(0xFF0F1923)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              children: [
                PlayerAvatar(photoPath: p.photoPath, name: p.name, size: 90, showBorder: true),
                const SizedBox(height: 16),
                Text(p.name, style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold,
                )),
                if (p.description != null && p.description!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(p.description!, style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 14,
                  ), textAlign: TextAlign.center),
                ],
                const SizedBox(height: 16),
                // Win rate bar
                Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Taxa de Vitória', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        Text('${_winRate.toStringAsFixed(1)}%', style: const TextStyle(
                          color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.bold,
                        )),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _winRate / 100,
                        backgroundColor: AppColors.surfaceLight,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.win),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'Estatísticas'),
                const SizedBox(height: 8),
                // Grid de stats
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.9,
                  children: [
                    StatCard(label: 'Partidas', value: '${p.matchesPlayed}',
                        icon: Icons.sports_kabaddi, color: AppColors.textSecondary),
                    StatCard(label: 'Vitórias', value: '${p.wins}',
                        icon: Icons.thumb_up_rounded, color: AppColors.win),
                    StatCard(label: 'Derrotas', value: '${p.losses}',
                        icon: Icons.thumb_down_rounded, color: AppColors.loss),
                    StatCard(label: 'Gols', value: '${p.goals}',
                        icon: Icons.sports_soccer, color: AppColors.goal),
                    StatCard(label: 'Títulos', value: '${p.titles}',
                        icon: Icons.emoji_events_rounded, color: AppColors.accent),
                    StatCard(label: 'Finais', value: '${p.finals}',
                        icon: Icons.star_rounded, color: AppColors.draw),
                  ],
                ),

                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.surfaceLight),
                  ),
                  child: Column(
                    children: [
                      StatRow(label: 'Vice-campeonatos', value: '${p.vices}',
                          icon: Icons.workspace_premium_rounded, valueColor: AppColors.textSecondary),
                      const Divider(color: AppColors.surfaceLight, height: 16),
                      StatRow(
                        label: 'Média de gols/partida',
                        value: p.matchesPlayed > 0
                            ? (p.goals / p.matchesPlayed).toStringAsFixed(2)
                            : '0.00',
                        icon: Icons.analytics_rounded,
                        valueColor: AppColors.accent,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
import 'dart:io';
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
        content: Text('Tem certeza que deseja excluir ${_player?.name}?',
            style: const TextStyle(color: AppColors.textSecondary)),
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

  void _openFullScreenPhoto() {
    if (_player?.photoPath == null) return;
    final path = _player!.photoPath!;
    if (!File(path).existsSync()) return;

    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _FullScreenPhoto(
        photoPath: path,
        playerName: _player!.name,
        heroTag: 'player_photo_${_player!.id}',
      ),
    ));
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
    final hasPhoto = p.photoPath != null && File(p.photoPath!).existsSync();

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 28),
        child: Column(
          children: [
          // ── Header com foto grande ──────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1A2634), Color(0xFF0F1923)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              children: [
                // Foto grande com toque para tela cheia
                GestureDetector(
                  onTap: hasPhoto ? _openFullScreenPhoto : null,
                  child: Hero(
                    tag: 'player_photo_${p.id}',
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.accent, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.accent.withOpacity(0.25),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: hasPhoto
                                ? Image.file(File(p.photoPath!), fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _avatarFallback(p))
                                : _avatarFallback(p),
                          ),
                        ),
                        if (hasPhoto)
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.background, width: 2),
                            ),
                            child: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 16),
                          ),
                      ],
                    ),
                  ),
                ),
                if (hasPhoto)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Toque para ver em tela cheia',
                        style: TextStyle(color: AppColors.textHint.withOpacity(0.7), fontSize: 11)),
                  ),
                const SizedBox(height: 14),
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
                // Win rate
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

          // ── Stats ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'Estatísticas'),
                const SizedBox(height: 8),
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
                    StatCard(label: 'Gols contra', value: '${p.ownGoals}',
                        icon: Icons.warning_rounded, color: AppColors.loss),
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
      ),
    );
  }

  Widget _avatarFallback(Player p) {
    return PlayerAvatar(photoPath: null, name: p.name, size: 120);
  }
}

// ── Tela cheia da foto ─────────────────────────────────────────────
class _FullScreenPhoto extends StatelessWidget {
  final String photoPath;
  final String playerName;
  final String heroTag;

  const _FullScreenPhoto({
    required this.photoPath,
    required this.playerName,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(playerName, style: const TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: Hero(
          tag: heroTag,
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 5.0,
            child: Image.file(
              File(photoPath),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 80),
            ),
          ),
        ),
      ),
    );
  }
}

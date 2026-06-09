import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/championship.dart';
import '../../core/repositories/championship_repository.dart';
import '../../core/services/season_manager.dart';
import '../../core/utils/date_utils.dart';
import '../../shared/widgets/custom_app_bar.dart';

class ChampionshipScreen extends StatefulWidget {
  const ChampionshipScreen({super.key});

  @override
  State<ChampionshipScreen> createState() => _ChampionshipScreenState();
}

class _ChampionshipScreenState extends State<ChampionshipScreen>
    with SingleTickerProviderStateMixin {
  final _repo = ChampionshipRepository();
  final _seasonManager = SeasonManager.instance;
  List<Championship> _all = [];
  bool _loading = true;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final season = await _seasonManager.getActiveSeason();
    _all = season == null ? [] : await _repo.getAll(seasonId: season.id);
    setState(() => _loading = false);
  }

  List<Championship> get _active =>
      _all.where((c) => c.status != ChampionshipStatus.finished).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<Championship> get _finished =>
      _all.where((c) => c.status == ChampionshipStatus.finished).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'Campeonatos',
        bottomHeight: 48,
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textHint,
          tabs: const [Tab(text: 'Em andamento'), Tab(text: 'Histórico')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildList(_active, isActive: true),
                _buildList(_finished, isActive: false),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.pushNamed(context, '/championship/new');
          _load();
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Novo Campeonato'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  Widget _buildList(List<Championship> list, {required bool isActive}) {
    if (list.isEmpty) {
      return EmptyState(
        icon: Icons.emoji_events_outlined,
        title: isActive ? 'Nenhum campeonato ativo' : 'Nenhum histórico',
        subtitle: isActive
            ? 'Toque em "Novo Campeonato" para começar'
            : 'Finalize um campeonato para ver aqui',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.accent,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 80),
        itemCount: list.length,
        itemBuilder: (_, i) => _ChampCard(
          championship: list[i],
          index: i,
          onTap: () async {
            await Navigator.pushNamed(
              context,
              '/championship/detail',
              arguments: list[i].id,
            );
            _load();
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }
}

class _ChampCard extends StatelessWidget {
  final Championship championship;
  final int index;
  final VoidCallback onTap;

  const _ChampCard({required this.championship, required this.index, required this.onTap});

  Color get _statusColor {
    switch (championship.status) {
      case ChampionshipStatus.setup:
        return AppColors.textHint;
      case ChampionshipStatus.inProgress:
        return AppColors.win;
      case ChampionshipStatus.finished:
        return AppColors.accent;
    }
  }

  String get _statusLabel {
    switch (championship.status) {
      case ChampionshipStatus.setup:
        return 'Configurando';
      case ChampionshipStatus.inProgress:
        return 'Em andamento';
      case ChampionshipStatus.finished:
        return 'Finalizado';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _statusColor.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.15),
                border: Border.all(color: AppColors.primary.withOpacity(0.4)),
              ),
              child: const Icon(Icons.emoji_events_rounded, color: AppColors.accent, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(championship.name, style: const TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15,
                  )),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.group_rounded, size: 13, color: AppColors.textHint),
                      const SizedBox(width: 4),
                      Text('${championship.teams.length} times', style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12,
                      )),
                      const SizedBox(width: 12),
                      Icon(Icons.calendar_today_rounded, size: 13, color: AppColors.textHint),
                      const SizedBox(width: 4),
                      Text(AppDateUtils.formatDate(championship.createdAt), style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12,
                      )),
                    ],
                  ),
                  if (championship.winnerName != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.military_tech_rounded, size: 13, color: AppColors.accent),
                        const SizedBox(width: 4),
                        Text(championship.winnerName!, style: const TextStyle(
                          color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600,
                        )),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_statusLabel, style: TextStyle(
                color: _statusColor, fontSize: 11, fontWeight: FontWeight.w600,
              )),
            ),
          ],
        ),
      ).animate().fadeIn(delay: Duration(milliseconds: index * 50), duration: 300.ms),
    );
  }
}
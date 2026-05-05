import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Expanded(child: _buildMenu(context)),
                    const SizedBox(height: 16),
                    _buildFooter(),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F1923), Color(0xFF1A2634)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.sports_soccer, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'FIFATEC',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    'Gerenciador de Futebol',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.3, end: 0);
  }

  Widget _buildMenu(BuildContext context) {
    final items = [
      _MenuItem(
        title: 'Jogadores',
        subtitle: 'Gerencie seus atletas',
        icon: Icons.person_rounded,
        gradient: const LinearGradient(colors: [Color(0xFF1565C0), Color(0xFF1976D2)]),
        route: '/players',
        delay: 0,
      ),
      _MenuItem(
        title: 'Campeonato',
        subtitle: 'Crie e gerencie torneios',
        icon: Icons.emoji_events_rounded,
        gradient: const LinearGradient(colors: [Color(0xFF1B5E20), Color(0xFF388E3C)]),
        route: '/championship',
        delay: 80,
      ),
      _MenuItem(
        title: 'Temporada',
        subtitle: 'Ranking, histórico e controle',
        icon: Icons.leaderboard_rounded,
        gradient: const LinearGradient(colors: [Color(0xFFE65100), Color(0xFFF57C00)]),
        route: '/season',
        delay: 160,
      ),
      _MenuItem(
        title: 'Histórico',
        subtitle: 'Partidas e campeonatos passados',
        icon: Icons.history_rounded,
        gradient: const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF7B1FA2)]),
        route: '/history',
        delay: 240,
      ),
      _MenuItem(
        title: 'Opções',
        subtitle: 'Configurações e backup',
        icon: Icons.settings_rounded,
        gradient: const LinearGradient(colors: [Color(0xFF37474F), Color(0xFF546E7A)]),
        route: '/options',
        delay: 320,
      ),
    ];

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _MenuCard(item: items[i]).animate()
          .fadeIn(delay: Duration(milliseconds: items[i].delay), duration: 400.ms)
          .slideX(begin: 0.2, end: 0),
    );
  }

  Widget _buildFooter() {
    return Text(
      'v1.0.0 • FIFATEC',
      style: TextStyle(color: AppColors.textHint, fontSize: 11),
    );
  }
}

class _MenuItem {
  final String title, subtitle, route;
  final IconData icon;
  final LinearGradient gradient;
  final int delay;

  const _MenuItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.route,
    required this.delay,
  });
}

class _MenuCard extends StatelessWidget {
  final _MenuItem item;
  const _MenuCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.pushNamed(context, item.route),
        child: Container(
          height: 76,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                item.gradient.colors.first.withOpacity(0.18),
                item.gradient.colors.last.withOpacity(0.08),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: item.gradient.colors.first.withOpacity(0.35),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: item.gradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(item.icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

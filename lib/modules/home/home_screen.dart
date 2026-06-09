import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/constants/app_colors.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Carrega a imagem antes de renderizar para evitar piscadas e baixa qualidade
    // no primeiro frame da tela inicial.
    precacheImage(const AssetImage('assets/images/logo.png'), context);
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _version = info.version);
  }

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
                    const SizedBox(height: 4),
                    Expanded(child: _buildMenu(context)),
                    _buildFooter(),
                    const SizedBox(height: 16),
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
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: const BoxDecoration(
        gradient: AppColors.backgroundGradient,
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.primary.withOpacity(0.35),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.14),
                  blurRadius: 10,
                  spreadRadius: -4,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Image.asset(
                'assets/images/logo.png',
                width: 64,
                height: 64,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                isAntiAlias: true,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) {
                  return const Icon(
                    Icons.sports_soccer_rounded,
                    color: AppColors.primary,
                    size: 34,
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [
                      AppColors.textPrimary,
                      AppColors.primary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(bounds),
                  blendMode: BlendMode.srcIn,
                  child: const Padding(
                    padding: EdgeInsets.only(top: 3, bottom: 2),
                    child: Text(
                      'FIFATEC',
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        height: 1.18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
                const Text(
                  'Gerenciador de Futebol',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.2, end: 0);
  }

  Widget _buildMenu(BuildContext context) {
    final items = [
      _MenuItem(
        title: 'Jogadores',
        subtitle: 'Gerencie seus atletas',
        icon: Icons.person_rounded,
        gradient: AppColors.primaryGradient,
        glowColor: AppColors.primary,
        iconColor: AppColors.background,
        route: '/players',
        delay: 0,
      ),
      _MenuItem(
        title: 'Campeonato',
        subtitle: 'Crie e gerencie torneios',
        icon: Icons.emoji_events_rounded,
        gradient: AppColors.primaryGradient,
        glowColor: AppColors.primary,
        iconColor: AppColors.background,
        route: '/championship',
        delay: 70,
      ),
      _MenuItem(
        title: 'Temporada',
        subtitle: 'Ranking, histórico e controle',
        icon: Icons.leaderboard_rounded,
        gradient: AppColors.primaryGradient,
        glowColor: AppColors.primary,
        iconColor: AppColors.background,
        route: '/season',
        delay: 140,
      ),
      _MenuItem(
        title: 'Histórico',
        subtitle: 'Partidas e campeonatos passados',
        icon: Icons.history_rounded,
        gradient: AppColors.primaryGradient,
        glowColor: AppColors.primary,
        iconColor: AppColors.background,
        route: '/history',
        delay: 210,
      ),
      _MenuItem(
        title: 'Opções',
        subtitle: 'Configurações e backup',
        icon: Icons.tune_rounded,
        gradient: AppColors.primaryGradient,
        glowColor: AppColors.primary,
        iconColor: AppColors.background,
        route: '/options',
        delay: 280,
      ),
    ];

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _MenuCard(item: items[i])
          .animate()
          .fadeIn(delay: Duration(milliseconds: items[i].delay), duration: 350.ms)
          .slideX(begin: 0.15, end: 0),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        _version.isEmpty ? 'FIFATEC' : 'v$_version  •  FIFATEC',
        style: const TextStyle(
          color: AppColors.textHint,
          fontSize: 11,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _MenuItem {
  final String title, subtitle, route;
  final IconData icon;
  final LinearGradient gradient;
  final Color glowColor;
  final Color iconColor;
  final int delay;

  const _MenuItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.glowColor,
    required this.iconColor,
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
        splashColor: item.glowColor.withOpacity(0.08),
        highlightColor: item.glowColor.withOpacity(0.05),
        onTap: () => Navigator.pushNamed(context, item.route),
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            gradient: AppColors.cardGradient,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: item.glowColor.withOpacity(0.18),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 10,
                spreadRadius: -6,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: item.gradient,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.08),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: item.glowColor.withOpacity(0.22),
                      blurRadius: 10,
                      spreadRadius: -3,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(item.icon, color: item.iconColor, size: 24),
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
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(right: 14),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: item.glowColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: item.glowColor,
                  size: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

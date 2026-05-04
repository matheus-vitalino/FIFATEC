import 'package:flutter/material.dart';
import 'core/constants/app_theme.dart';
import 'modules/home/home_screen.dart';
import 'modules/players/player_form_screen.dart';
import 'modules/players/player_profile_screen.dart';
import 'modules/players/players_screen.dart';
import 'modules/championship/championship_detail_screen.dart';
import 'modules/championship/championship_screen.dart';
import 'modules/championship/match_screen.dart';
import 'modules/championship/new_championship_screen.dart';
import 'modules/history/history_screen.dart';
import 'modules/options/options_screen.dart';
import 'modules/ranking/ranking_screen.dart';

class AppTiminho extends StatelessWidget {
  const AppTiminho({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AppTiminho',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      initialRoute: '/',
      routes: {
        '/': (_) => const HomeScreen(),
        '/players': (_) => const PlayersScreen(),
        '/players/form': (_) => const PlayerFormScreen(),
        '/championship': (_) => const ChampionshipScreen(),
        '/championship/new': (_) => const NewChampionshipScreen(),
        '/ranking': (_) => const RankingScreen(),
        '/season': (_) => const RankingScreen(),
        '/history': (_) => const HistoryScreen(),
        '/options': (_) => const OptionsScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/players/profile') {
          final playerId = settings.arguments as String;
          return MaterialPageRoute(
            builder: (_) => PlayerProfileScreen(playerId: playerId),
          );
        }
        if (settings.name == '/players/edit') {
          final playerId = settings.arguments as String;
          return MaterialPageRoute(
            builder: (_) => PlayerFormScreen(editPlayerId: playerId),
          );
        }
        if (settings.name == '/championship/detail') {
          final championshipId = settings.arguments as String;
          return MaterialPageRoute(
            builder: (_) => ChampionshipDetailScreen(championshipId: championshipId),
          );
        }
        if (settings.name == '/championship/match') {
          final args = settings.arguments as Map<String, String>;
          return MaterialPageRoute(
            builder: (_) => MatchScreen(
              matchId: args['matchId']!,
              championshipId: args['championshipId']!,
            ),
          );
        }
        return null;
      },
    );
  }
}

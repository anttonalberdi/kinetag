import 'package:flutter/material.dart';

import '../features/home/home_screen.dart';
import '../features/live/live_screen.dart';
import '../features/sessions/sessions_screen.dart';
import '../features/setup/setup_screen.dart';

/// Top-level destinations, in workflow order: Setup -> Record -> Replay.
enum AppDestination {
  home('Home', Icons.home_outlined, Icons.home),
  setup('Setup', Icons.settings_input_antenna_outlined,
      Icons.settings_input_antenna),
  live('Live', Icons.sensors_outlined, Icons.sensors),
  sessions('Sessions', Icons.folder_outlined, Icons.folder);

  const AppDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Application frame with adaptive navigation.
///
/// Uses a [NavigationRail] on wide windows and a bottom [NavigationBar] on
/// narrow ones. The breakpoint is deliberately in one place so the phone /
/// tablet / desktop layouts described in the roadmap can diverge later
/// without touching individual screens.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  /// Below this width the shell switches to a bottom navigation bar.
  static const double compactBreakpoint = 720;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppDestination _destination = AppDestination.home;

  void _select(AppDestination destination) =>
      setState(() => _destination = destination);

  Widget _screenFor(AppDestination destination) => switch (destination) {
        AppDestination.home => HomeScreen(onNavigate: _select),
        AppDestination.setup => const SetupScreen(),
        AppDestination.live => const LiveScreen(),
        AppDestination.sessions => const SessionsScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final isCompact =
        MediaQuery.sizeOf(context).width < AppShell.compactBreakpoint;
    final body = _screenFor(_destination);

    if (isCompact) {
      return Scaffold(
        body: SafeArea(child: body),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _destination.index,
          onDestinationSelected: (i) => _select(AppDestination.values[i]),
          destinations: [
            for (final d in AppDestination.values)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: _destination.index,
              onDestinationSelected: (i) => _select(AppDestination.values[i]),
              labelType: NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: _KinetagMark(),
              ),
              destinations: [
                for (final d in AppDestination.values)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _KinetagMark extends StatelessWidget {
  const _KinetagMark();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Kinetag',
      child: Icon(
        Icons.my_location,
        color: Theme.of(context).colorScheme.primary,
        size: 28,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which view of the open session the Sessions tab is showing.
///
/// Analysis is a set of pages rather than a dialog: a coach reads these
/// numbers next to the video, scrolls them, and wants to know where they are
/// — none of which a floating window over the court supports.
@immutable
sealed class SessionView {
  const SessionView();
}

/// The court, with the transport controls.
final class ReplayView extends SessionView {
  const ReplayView();
}

/// Session-wide and per-team figures.
final class TeamAnalysisView extends SessionView {
  const TeamAnalysisView();
}

/// One player's own page.
final class PlayerAnalysisView extends SessionView {
  final String tagId;

  const PlayerAnalysisView(this.tagId);
}

/// Navigation *within* an open session.
///
/// Deliberately not a `Navigator` route stack: the whole app keeps its
/// navigation rail visible and its screens flat (see [AppShell]), so a route
/// pushed here would cover the rail and make the system back gesture leave
/// the app from the middle of an analysis trail. The breadcrumbs carry the
/// position instead.
class SessionViewNavigator extends Notifier<SessionView> {
  @override
  SessionView build() => const ReplayView();

  void showReplay() => state = const ReplayView();

  void showTeamAnalysis() => state = const TeamAnalysisView();

  void showPlayer(String tagId) => state = PlayerAnalysisView(tagId);
}

final sessionViewProvider =
    NotifierProvider<SessionViewNavigator, SessionView>(
  SessionViewNavigator.new,
);

/// One step of a breadcrumb trail. A crumb with no [onTap] is the page the
/// reader is on.
@immutable
class Breadcrumb {
  final String label;
  final VoidCallback? onTap;

  const Breadcrumb(this.label, {this.onTap});
}

/// The trail back out of an analysis page.
///
/// Wrapped rather than laid out in a row: a long session name and a long
/// player name together are wider than a phone, and a trail that overflows
/// tells the reader nothing about where they are.
class AnalysisBreadcrumbs extends StatelessWidget {
  final List<Breadcrumb> crumbs;

  const AnalysisBreadcrumbs({super.key, required this.crumbs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < crumbs.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Icon(
                Icons.chevron_right,
                size: 16,
                color: theme.colorScheme.outline,
              ),
            ),
          if (crumbs[i].onTap == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Text(
                crumbs[i].label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            )
          else
            TextButton(
              onPressed: crumbs[i].onTap,
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: theme.textTheme.bodySmall,
              ),
              child: Text(crumbs[i].label),
            ),
        ],
      ],
    );
  }
}

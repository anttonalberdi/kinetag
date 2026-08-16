import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analytics/analytics_thresholds.dart';
import '../../core/duration_format.dart';
import '../../tracking/simulator/simulated_squad.dart';
import '../live/live_controller.dart';
import 'app_settings.dart';
import 'settings_controller.dart';

/// Capture and analysis settings.
///
/// Every control here changes how data is *captured* or *interpreted*, never
/// what a stored recording contains. That is why the analytics sliders take
/// effect immediately across sessions already recorded: the samples are the
/// single source of truth and the figures on top of them are recomputed, not
/// rewritten.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  /// Widest the settings column grows to before it stops filling the window.
  ///
  /// Sliders spanning a 27-inch display are hard to set precisely, and long
  /// explanatory lines are hard to read.
  static const double _maxContentWidth = 720;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    final isRecording = ref.watch(recordingInProgressProvider);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxContentWidth),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Settings', style: theme.textTheme.headlineSmall),
                ),
                TextButton.icon(
                  onPressed: settings.isDefault
                      ? null
                      : controller.resetToDefaults,
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Reset to defaults'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _SettingsSection(
              title: 'Capture',
              description: 'How position data is produced. Applies to the next '
                  'connection.',
              children: [
                _SettingSlider(
                  label: 'Capture rate',
                  valueLabel: '${settings.captureRateHz} Hz',
                  value: settings.captureRateHz.toDouble(),
                  min: AppSettings.minCaptureRateHz.toDouble(),
                  max: AppSettings.maxCaptureRateHz.toDouble(),
                  divisions:
                      AppSettings.maxCaptureRateHz - AppSettings.minCaptureRateHz,
                  enabled: !isRecording,
                  description: isRecording
                      ? 'Locked while recording: a rate that changed mid-capture '
                          'would corrupt every speed and distance derived from '
                          'the session.'
                      : 'Frames per second per tag. Higher rates resolve fast '
                          'changes of direction but produce proportionally more '
                          'samples to store.',
                  onChanged: (v) => controller.setCaptureRateHz(v.round()),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _SettingsSection(
              title: 'Line-up',
              description: 'How many players each side fields, and how often '
                  'they change. Applies to the next connection.',
              children: [
                _SettingSegments(
                  label: 'Players on court',
                  value: settings.fieldPlayersOnCourt,
                  enabled: !isRecording,
                  description: isRecording
                      ? 'Locked while recording: changing who is on court '
                          'restarts the simulation, which would cut the open '
                          'session in half.'
                      : 'A goalkeeper plus this many field players per side, '
                          'picked in roster order. Everyone the roster holds '
                          'beyond the line-up waits on the bench, half a metre '
                          'outside the sideline, and is still tracked there — '
                          'a substitute covers no ground, which is what makes '
                          'them tell apart in the analytics.',
                  onChanged: controller.setFieldPlayersOnCourt,
                ),
                _SettingSlider(
                  label: 'Substitution interval',
                  valueLabel: settings.substitutesRotate
                      ? formatElapsed(settings.substitutionInterval)
                      : 'Off',
                  value: settings.substitutionIntervalSeconds.toDouble(),
                  min: AppSettings.substitutionOffSeconds.toDouble(),
                  max: AppSettings.maxSubstitutionIntervalSeconds.toDouble(),
                  // One stop per 15 s, with "off" at the bottom of the scale.
                  divisions:
                      AppSettings.maxSubstitutionIntervalSeconds ~/
                          AppSettings.minSubstitutionIntervalSeconds,
                  enabled: !isRecording,
                  description: isRecording
                      ? 'Locked while recording: the rotation is part of the '
                          'simulation, and restarting it would cut the open '
                          'session in half.'
                      : 'How often each side swaps its longest-serving field '
                          'player for its longest-waiting substitute. The '
                          'player coming off walks to the bench first and only '
                          'then does the substitute step on, so a side is '
                          'never briefly seven strong. A side with nobody on '
                          'the bench has nothing to swap; at Off, whoever '
                          'starts plays the whole session.',
                  onChanged: (v) =>
                      controller.setSubstitutionIntervalSeconds(v.round()),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _SettingsSection(
              title: 'Noise rejection',
              description: 'How movement metrics separate real running from '
                  'positioning error. Changing these recomputes every '
                  'session’s figures — no stored data is altered.',
              children: [
                _SettingSlider(
                  label: 'Implausible speed threshold',
                  valueLabel:
                      '${settings.analytics.maxPlausibleSpeedMps.toStringAsFixed(1)} m/s',
                  value: settings.analytics.maxPlausibleSpeedMps,
                  min: AnalyticsThresholds.minSpeedCeilingMps,
                  max: AnalyticsThresholds.maxSpeedCeilingMps,
                  divisions: ((AnalyticsThresholds.maxSpeedCeilingMps -
                              AnalyticsThresholds.minSpeedCeilingMps) *
                          2)
                      .round(),
                  description: 'Steps implying more than this are discarded as '
                      'bad fixes. Elite sprinters peak near 12 m/s; a single '
                      'glitch and back would otherwise add tens of phantom '
                      'metres to a player’s distance.',
                  onChanged: controller.setMaxPlausibleSpeedMps,
                ),
                _SettingSlider(
                  label: 'Speed window',
                  valueLabel:
                      '${settings.analytics.speedWindow.inMilliseconds} ms',
                  value:
                      settings.analytics.speedWindow.inMilliseconds.toDouble(),
                  min: AnalyticsThresholds.minSpeedWindow.inMilliseconds
                      .toDouble(),
                  max: AnalyticsThresholds.maxSpeedWindow.inMilliseconds
                      .toDouble(),
                  divisions: 19,
                  description: 'Speeds are measured over at least this much '
                      'time. Shorter windows track sharp accelerations; longer '
                      'ones stop centimetre-scale position error from '
                      'dominating the result.',
                  onChanged: (v) => controller
                      .setSpeedWindow(Duration(milliseconds: v.round())),
                ),
                _SettingSlider(
                  label: 'Minimum confidence',
                  valueLabel:
                      settings.analytics.minConfidence.toStringAsFixed(2),
                  value: settings.analytics.minConfidence,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  description: 'Samples the positioning engine reports below '
                      'this quality are ignored entirely. Leave at 0 with the '
                      'simulator, where confidence is synthetic.',
                  onChanged: controller.setMinConfidence,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _SettingsSection(
              title: 'Receiver defaults',
              description: 'Used when a layout is generated in setup. Anchors '
                  'already placed are left where they are.',
              children: [
                _SettingSlider(
                  label: 'Mounting height',
                  valueLabel:
                      '${settings.receiverMountHeightMeters.toStringAsFixed(2)} m',
                  value: settings.receiverMountHeightMeters,
                  min: AppSettings.minMountHeightMeters,
                  max: AppSettings.maxMountHeightMeters,
                  divisions: 44,
                  description: 'Height above the floor. UWB ranging measures '
                      'true line-of-sight distance, so this genuinely affects '
                      'anchor geometry.',
                  onChanged: controller.setReceiverMountHeightMeters,
                ),
                _SettingSlider(
                  label: 'Clearance outside the court',
                  valueLabel:
                      '${settings.receiverMarginMeters.toStringAsFixed(2)} m',
                  value: settings.receiverMarginMeters,
                  min: AppSettings.minReceiverMarginMeters,
                  max: AppSettings.maxReceiverMarginMeters,
                  divisions: 20,
                  description: 'How far beyond the sidelines a generated '
                      'layout places anchors.',
                  onChanged: controller.setReceiverMarginMeters,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Settings apply for as long as the app is running; like the '
              'court layout, they are not yet stored between launches.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final String description;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.description,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              description,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// One labelled choice between the handball line-ups, with an explanation of
/// what picking one costs.
///
/// A segmented button rather than a slider: there are three answers, they are
/// named things a coach says out loud ("we're playing 1 + 4"), and none of
/// them is a point on a continuum.
class _SettingSegments extends StatelessWidget {
  final String label;
  final String description;
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const _SettingSegments({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  /// The line-ups on offer, labelled the way they are spoken.
  static String labelFor(int fieldPlayers) => '1 + $fieldPlayers';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = [
      for (var n = SimulatedSquad.minFieldPlayersOnCourt;
          n <= SimulatedSquad.maxFieldPlayersOnCourt;
          n++)
        n,
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: [
              for (final option in options)
                ButtonSegment<int>(
                  value: option,
                  label: Text(labelFor(option)),
                ),
            ],
            selected: {value},
            showSelectedIcon: false,
            onSelectionChanged:
                enabled ? (selection) => onChanged(selection.first) : null,
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// One labelled slider with its current value and an explanation of what
/// moving it costs.
class _SettingSlider extends StatelessWidget {
  final String label;
  final String valueLabel;
  final String description;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const _SettingSlider({
    required this.label,
    required this.valueLabel,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
              Text(
                valueLabel,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: enabled ? onChanged : null,
          ),
          Text(
            description,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

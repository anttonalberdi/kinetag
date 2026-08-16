import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/analytics/analytics_thresholds.dart';
import 'package:kinetag/src/analytics/session_metrics.dart';
import 'package:kinetag/src/app/provider_overrides.dart';
import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/features/settings/app_settings.dart';
import 'package:kinetag/src/features/settings/settings_controller.dart';
import 'package:kinetag/src/tracking/simulator/simulated_squad.dart';
import 'package:kinetag/src/tracking/tracking_providers.dart';

({ProviderContainer container, SettingsController controller})
    makeController() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return (
    container: container,
    controller: container.read(appSettingsProvider.notifier),
  );
}

AppSettings readState(ProviderContainer c) => c.read(appSettingsProvider);

/// A tag moving in a straight line at [speedMps], sampled at 20 Hz.
List<PositionSample> straightTrack({
  double speedMps = 5.0,
  double seconds = 2.0,
  double confidence = 0.9,
}) {
  const stepMicros = 50000;
  final steps = (seconds * 1e6 / stepMicros).round();
  return [
    for (var i = 0; i <= steps; i++)
      PositionSample(
        timestampMicros: i * stepMicros,
        tagId: 'tag-1',
        x: speedMps * (i * stepMicros / 1e6),
        y: 10,
        confidence: confidence,
      ),
  ];
}

void main() {
  group('defaults', () {
    test('match the values the analytics layer computes with', () {
      final settings = readState(makeController().container);

      expect(settings.isDefault, isTrue);
      expect(settings.analytics, AnalyticsThresholds.defaults);
      expect(settings.captureRateHz, 20);
      // 1 + 5 is PlayerRole.defaultLineup, so the default roster starts with
      // an empty bench.
      expect(settings.fieldPlayersOnCourt, 5);
    });
  });

  group('clamping', () {
    test('keeps the capture rate inside the supported range', () {
      final c = makeController();

      c.controller.setCaptureRateHz(0);
      expect(readState(c.container).captureRateHz, AppSettings.minCaptureRateHz);

      c.controller.setCaptureRateHz(10000);
      expect(readState(c.container).captureRateHz, AppSettings.maxCaptureRateHz);
    });

    test('keeps the speed window long enough to be meaningful', () {
      final c = makeController();

      c.controller.setSpeedWindow(Duration.zero);
      expect(readState(c.container).analytics.speedWindow,
          AnalyticsThresholds.minSpeedWindow);
    });

    test('keeps confidence a probability', () {
      final c = makeController();

      c.controller.setMinConfidence(-1);
      expect(readState(c.container).analytics.minConfidence, 0.0);

      c.controller.setMinConfidence(9);
      expect(readState(c.container).analytics.minConfidence, 1.0);
    });

    test('keeps the line-up to one the simulator can field', () {
      final c = makeController();

      c.controller.setFieldPlayersOnCourt(1);
      expect(readState(c.container).fieldPlayersOnCourt,
          SimulatedSquad.minFieldPlayersOnCourt);

      c.controller.setFieldPlayersOnCourt(30);
      expect(readState(c.container).fieldPlayersOnCourt,
          SimulatedSquad.maxFieldPlayersOnCourt);
    });

    test('keeps the mounting height above the floor', () {
      final c = makeController();

      c.controller.setReceiverMountHeightMeters(-5);
      expect(readState(c.container).receiverMountHeightMeters,
          AppSettings.minMountHeightMeters);
    });
  });

  test('reset restores every default', () {
    final c = makeController();
    c.controller.setCaptureRateHz(75);
    c.controller.setMaxPlausibleSpeedMps(20);

    c.controller.resetToDefaults();

    expect(readState(c.container), AppSettings.defaults);
  });

  group('capture rate reaches the tracking source', () {
    test('the source is built at the configured rate', () {
      final container = ProviderContainer(
        overrides: [
          trackingSampleRateProvider.overrideWith(
            (ref) =>
                ref.watch(appSettingsProvider.select((s) => s.captureRateHz)),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(appSettingsProvider.notifier).setCaptureRateHz(50);

      expect(container.read(trackingSampleRateProvider), 50);
    });
  });

  group('the line-up reaches the simulated squad', () {
    test('choosing 1 + 4 benches the players it leaves out', () {
      final container = ProviderContainer(overrides: kinetagProviderOverrides());
      addTearDown(container.dispose);

      // The default roster is two teams of six, all fielded at 1 + 5.
      expect(container.read(simulatedSquadProvider).benched, isEmpty);

      container.read(appSettingsProvider.notifier).setFieldPlayersOnCourt(4);
      final squad = container.read(simulatedSquadProvider);

      expect(squad.length, 12, reason: 'every tag is still simulated');
      expect(squad.onCourt, hasLength(10));
      expect(squad.benched, hasLength(2));
      for (final side in TeamSide.values) {
        expect(squad.forSide(side).where((p) => !p.isOnCourt).single.benchSeat,
            0);
      }
    });
  });

  group('thresholds change what the metrics say', () {
    test('a lower speed ceiling discards more steps', () {
      final track = straightTrack(speedMps: 8.0);

      final permissive = SessionMetrics.fromSamples(track).forTag('tag-1')!;
      final strict = SessionMetrics.fromSamples(
        track,
        thresholds: const AnalyticsThresholds(maxPlausibleSpeedMps: 5.0),
      ).forTag('tag-1')!;

      expect(permissive.discardedSteps, 0);
      expect(strict.discardedSteps, greaterThan(0));
      expect(strict.distanceMeters, lessThan(permissive.distanceMeters));
    });

    test('a longer speed window smooths the peak', () {
      // A brief spike inside a long window is averaged out; inside a short one
      // it survives. That trade-off is the whole point of the setting.
      final samples = [
        ...straightTrack(speedMps: 2.0, seconds: 1.0),
        for (var i = 1; i <= 4; i++)
          PositionSample(
            timestampMicros: 1000000 + i * 50000,
            tagId: 'tag-1',
            // 9 m/s burst.
            x: 2.0 + 0.45 * i,
            y: 10,
            confidence: 0.9,
          ),
      ];

      final sharp = SessionMetrics.fromSamples(
        samples,
        thresholds:
            const AnalyticsThresholds(speedWindow: Duration(milliseconds: 100)),
      ).forTag('tag-1')!;
      final smooth = SessionMetrics.fromSamples(
        samples,
        thresholds:
            const AnalyticsThresholds(speedWindow: Duration(milliseconds: 800)),
      ).forTag('tag-1')!;

      expect(sharp.maxSpeedMps, greaterThan(smooth.maxSpeedMps));
    });

    test('a confidence floor drops the samples below it', () {
      final samples = [
        ...straightTrack(seconds: 1.0, confidence: 0.9),
        ...[
          for (final s in straightTrack(seconds: 1.0, confidence: 0.2))
            PositionSample(
              timestampMicros: s.timestampMicros + 2000000,
              tagId: 'tag-2',
              x: s.x,
              y: s.y,
              confidence: s.confidence,
            ),
        ],
      ];

      final kept = SessionMetrics.fromSamples(samples);
      final filtered = SessionMetrics.fromSamples(
        samples,
        thresholds: const AnalyticsThresholds(minConfidence: 0.5),
      );

      expect(kept.byTagId.keys, containsAll(['tag-1', 'tag-2']));
      expect(filtered.byTagId.keys, ['tag-1']);
    });

    test('metrics carry the thresholds they were computed under', () {
      const thresholds = AnalyticsThresholds(maxPlausibleSpeedMps: 7.0);

      expect(
        SessionMetrics.fromSamples(straightTrack(), thresholds: thresholds)
            .thresholds,
        thresholds,
      );
    });
  });

  group('serialisation', () {
    test('round-trips every field', () {
      const settings = AppSettings(
        captureRateHz: 64,
        receiverMountHeightMeters: 3.1,
        receiverMarginMeters: 0.75,
        analytics: AnalyticsThresholds(
          maxPlausibleSpeedMps: 9.5,
          speedWindow: Duration(milliseconds: 350),
          minConfidence: 0.4,
        ),
      );

      expect(AppSettings.fromJson(settings.toJson()), settings);
    });

    test('falls back to defaults for anything missing', () {
      expect(AppSettings.fromJson(const {}), AppSettings.defaults);
    });
  });
}

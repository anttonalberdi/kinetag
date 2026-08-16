import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/features/sessions/replay_controller.dart';
import 'package:kinetag/src/storage/session_repository.dart';
import 'package:kinetag/src/storage/sqlite_session_repository.dart';
import 'package:kinetag/src/storage/storage_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/in_memory_repository.dart';
import '../support/session_fixtures.dart';

/// Storage that fails on read, standing in for a corrupt or missing database.
class _BrokenRepository extends SqliteSessionRepository {
  _BrokenRepository() : super(open: () => throw Exception('database missing'));
}

late ProviderContainer container;
late SessionRepository repository;

ReplayState get state => container.read(replayControllerProvider);
ReplayController get controller =>
    container.read(replayControllerProvider.notifier);

void main() {
  setUpAll(sqfliteFfiInit);

  setUp(() {
    repository = makeInMemoryRepository();
    container = ProviderContainer(
      overrides: [sessionRepositoryProvider.overrideWith((ref) => repository)],
    );
    container.read(replayControllerProvider);
  });

  tearDown(() async {
    container.dispose();
    await repository.close();
  });

  group('opening a session', () {
    test('loads its frames and shows the first, paused', () async {
      final session = await seedRecording(repository);

      await controller.open(session);

      expect(state.isLoading, isFalse);
      expect(state.frameCount, 10);
      expect(state.duration, const Duration(milliseconds: 900));
      expect(state.position, Duration.zero);
      expect(state.isPlaying, isFalse);
      expect(state.frame!.samples, hasLength(2));
      expect(state.frame!.sampleForTag('tag-0')!.x, 0);
    });

    test('a session with no samples is not playable', () async {
      final empty = Session(
        id: 'empty',
        name: 'Nothing recorded',
        createdAt: DateTime.utc(2026, 8, 16),
        court: Court.handball(),
        status: SessionStatus.completed,
      );
      await repository.saveSession(empty);

      await controller.open(empty);

      expect(state.hasRecording, isFalse);
      expect(state.duration, Duration.zero);
      expect(state.frame, isNull);
    });

    test('opening a second session replaces the first', () async {
      await controller.open(await seedRecording(repository, frameCount: 10));
      await controller.open(
        await seedRecording(repository, id: 'other', frameCount: 4),
      );

      expect(state.session!.id, 'other');
      expect(state.frameCount, 4);
    });

    test('reports a load failure instead of throwing', () async {
      final session = await seedRecording(repository);
      final broken = ProviderContainer(
        overrides: [
          sessionRepositoryProvider.overrideWith((ref) => _BrokenRepository()),
        ],
      );
      addTearDown(broken.dispose);

      await broken.read(replayControllerProvider.notifier).open(session);

      final state = broken.read(replayControllerProvider);
      expect(state.isLoading, isFalse);
      expect(state.errorMessage, contains('Could not load'));
      expect(state.frame, isNull);
    });
  });

  group('scrubbing', () {
    test('seeks forwards and backwards to the right frame', () async {
      await controller.open(await seedRecording(repository));

      controller.seek(const Duration(milliseconds: 700));
      expect(state.frame!.sampleForTag('tag-0')!.x, 7);
      expect(state.position, const Duration(milliseconds: 700));

      controller.seek(const Duration(milliseconds: 200));
      expect(state.frame!.sampleForTag('tag-0')!.x, 2);
      expect(state.position, const Duration(milliseconds: 200));
    });

    test('seeks by progress fraction for the timeline slider', () async {
      await controller.open(await seedRecording(repository));

      controller.seekToProgress(0.5);

      expect(state.position, const Duration(milliseconds: 450));
      expect(state.progress, closeTo(0.5, 1e-9));
    });

    test('progress is zero for an unplayable session', () async {
      expect(const ReplayState().progress, 0);
    });

    test('steps one frame at a time in both directions', () async {
      await controller.open(await seedRecording(repository));

      controller.step(forward: true);
      controller.step(forward: true);
      expect(state.frame!.sampleForTag('tag-0')!.x, 2);

      controller.step(forward: false);
      expect(state.frame!.sampleForTag('tag-0')!.x, 1);
    });

    test('stepping stops at the ends rather than running off', () async {
      await controller.open(await seedRecording(repository, frameCount: 3));

      controller.step(forward: false);
      expect(state.position, Duration.zero);

      for (var i = 0; i < 5; i++) {
        controller.step(forward: true);
      }
      expect(state.position, state.duration);
    });
  });

  group('transport', () {
    test('play and pause toggle', () async {
      await controller.open(await seedRecording(repository));

      controller.togglePlay();
      expect(state.isPlaying, isTrue);

      controller.togglePlay();
      expect(state.isPlaying, isFalse);
    });

    test('playback advances the playhead', () async {
      await controller.open(await seedRecording(repository));

      controller.play();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      controller.pause();

      expect(state.position, greaterThan(Duration.zero));
      expect(state.frame!.sampleForTag('tag-0')!.x, greaterThan(0));
    });

    test('speed selection is applied', () async {
      await controller.open(await seedRecording(repository));

      controller.setSpeed(4.0);

      expect(state.speed, 4.0);
    });

    test('transport calls are safe with nothing open', () {
      controller
        ..play()
        ..pause()
        ..seek(const Duration(seconds: 1))
        ..step(forward: true)
        ..setSpeed(2.0);

      expect(state.session, isNull);
      expect(state.isPlaying, isFalse);
    });

    test('closing releases the session', () async {
      await controller.open(await seedRecording(repository));

      await controller.close();

      expect(state.session, isNull);
      expect(state.frame, isNull);
      expect(state.frameCount, 0);
    });
  });
}

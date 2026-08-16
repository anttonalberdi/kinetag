import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/features/live/live_controller.dart';
import 'package:kinetag/src/features/setup/setup_state.dart';
import 'package:kinetag/src/storage/kinetag_database.dart';
import 'package:kinetag/src/storage/sqlite_session_repository.dart';
import 'package:kinetag/src/storage/storage_providers.dart';
import 'package:kinetag/src/tracking/tracking_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_tracking_source.dart';

/// Live view -> recording sink -> SQLite, with only the tracking source and
/// the database location faked. Everything between them is the wiring the
/// macOS app runs.
void main() {
  setUpAll(sqfliteFfiInit);

  late ProviderContainer container;
  late FakeTrackingSource source;
  late SqliteSessionRepository repository;

  setUp(() {
    source = FakeTrackingSource();
    repository = SqliteSessionRepository(
      open: () => databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: kinetagSchemaVersion,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, version) => migrate(db, 0, version),
          onUpgrade: migrate,
        ),
      ),
    );

    container = ProviderContainer(
      overrides: [
        trackingSourceProvider.overrideWith((ref) => source),
        sessionRepositoryProvider.overrideWith((ref) => repository),
      ],
    );
    container.read(liveControllerProvider);
  });

  tearDown(() async {
    container.dispose();
    await source.dispose();
    await repository.close();
  });

  test('a recorded session and its samples land in the database', () async {
    final controller = container.read(liveControllerProvider.notifier);
    await controller.start();
    await controller.startRecording();

    for (var i = 1; i <= 4; i++) {
      source.emitFrame(testFrame(timestampMicros: i * 50000, tagCount: 3));
    }
    await Future<void>.delayed(Duration.zero);

    final completed = await controller.stopRecording();

    expect(completed, isNotNull);
    expect(completed!.sampleCount, 12);
    expect(await repository.countSamples(completed.id), 12);

    final stored = await repository.findSession(completed.id);
    expect(stored!.status, SessionStatus.completed);
    expect(stored.sampleCount, 12);
    // The frozen setup came along: six receivers and the simulated squad.
    expect(stored.receivers, hasLength(6));
    expect(stored.players, hasLength(12));
    expect(stored.court.widthMeters, 40.0);

    final frames = await repository.framesForSession(completed.id);
    expect(frames, hasLength(4));
    expect(frames.first.samples, hasLength(3));
    expect(frames.map((f) => f.timestampMicros),
        [50000, 100000, 150000, 200000]);
  });

  test('the session list refreshes once a recording ends', () async {
    final controller = container.read(liveControllerProvider.notifier);
    expect(await container.read(sessionListProvider.future), isEmpty);

    await controller.startRecording();
    source.emitFrame(testFrame(timestampMicros: 50000));
    await Future<void>.delayed(Duration.zero);
    await controller.stopRecording();

    final sessions = await container.read(sessionListProvider.future);
    expect(sessions, hasLength(1));
    expect(sessions.single.status, SessionStatus.completed);
  });

  test('a moved receiver does not rewrite a stored recording', () async {
    // Decision 5, end to end: the snapshot must survive the round trip
    // through SQLite as well as the copy in memory.
    final controller = container.read(liveControllerProvider.notifier);
    final setup = container.read(setupControllerProvider.notifier);
    final receiverId = container.read(setupControllerProvider).receivers.first.id;

    await controller.startRecording();
    source.emitFrame(testFrame(timestampMicros: 50000));
    await Future<void>.delayed(Duration.zero);
    final completed = await controller.stopRecording();

    setup.moveReceiver(receiverId, x: 99, y: 99);

    final stored = await repository.findSession(completed!.id);
    final storedReceiver =
        stored!.receivers.firstWhere((r) => r.id == receiverId);
    expect(storedReceiver.x, isNot(99));
    expect(storedReceiver.y, isNot(99));
  });
}

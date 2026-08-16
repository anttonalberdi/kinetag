import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/storage/kinetag_database.dart';
import 'package:kinetag/src/storage/session_repository.dart';
import 'package:kinetag/src/storage/sqlite_session_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A repository backed by a private in-memory database.
///
/// Same schema and same SQL as the real thing — only the storage medium
/// differs, so migrations and queries are genuinely exercised.
SessionRepository makeRepository() {
  final repository = SqliteSessionRepository(
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
  addTearDown(repository.close);
  return repository;
}

Session makeSession({
  String id = 'session-1',
  String name = 'Morning training',
  SessionStatus status = SessionStatus.recording,
  int sampleCount = 0,
  DateTime? createdAt,
}) {
  final court = Court.handball();
  return Session(
    id: id,
    name: name,
    createdAt: createdAt ?? DateTime.utc(2026, 8, 16, 9),
    court: court,
    receivers: const [
      Receiver(id: 'rx-1', name: 'RX-01', x: -1.2, y: -1.2, z: 2.4),
      Receiver(id: 'rx-2', name: 'RX-02', x: 41.2, y: 21.2, z: 2.4),
    ],
    tags: const [Tag(id: 'tag-1', hardwareId: 'SIM-0001', name: 'Home #1')],
    players: const [
      Player(id: 'player-1', name: 'Home Pivot', number: 6, team: 'Home'),
    ],
    tagAssignments: const [
      TagAssignment(
        id: 'assign-1',
        playerId: 'player-1',
        tagId: 'tag-1',
        location: TagMountLocation.rightShoe,
      ),
    ],
    status: status,
    startedAt: DateTime.utc(2026, 8, 16, 9, 5),
    sampleCount: sampleCount,
  );
}

List<PositionSample> samplesAt(int timestampMicros, {int tags = 2}) => [
      for (var i = 0; i < tags; i++)
        PositionSample(
          timestampMicros: timestampMicros,
          tagId: 'tag-$i',
          x: 10.0 + i,
          y: 5.0 + i,
          confidence: 0.9,
        ),
    ];

void main() {
  setUpAll(sqfliteFfiInit);

  group('session metadata', () {
    test('round-trips a session with its frozen setup', () async {
      final repository = makeRepository();
      final session = makeSession();

      await repository.saveSession(session);
      final loaded = await repository.findSession(session.id);

      expect(loaded, isNotNull);
      expect(loaded!.name, session.name);
      expect(loaded.status, session.status);
      expect(loaded.createdAt, session.createdAt);
      expect(loaded.startedAt, session.startedAt);
      expect(loaded.court.widthMeters, 40.0);
      expect(loaded.receivers, session.receivers);
      expect(loaded.players, session.players);
      expect(loaded.tags, session.tags);
      expect(loaded.tagAssignments, session.tagAssignments);
      expect(loaded.positioningAlgorithmVersion, 'simulator-v1');
    });

    test('preserves microsecond precision on timestamps', () async {
      // Truncating to milliseconds here would silently disagree with the
      // sample timestamps the same session stores.
      final repository = makeRepository();
      final created = DateTime.fromMicrosecondsSinceEpoch(
        1786000000123456,
        isUtc: true,
      );

      await repository.saveSession(makeSession(createdAt: created));
      final loaded = await repository.findSession('session-1');

      expect(loaded!.createdAt.microsecondsSinceEpoch, 1786000000123456);
    });

    test('saving the same id updates rather than duplicates', () async {
      final repository = makeRepository();
      await repository.saveSession(makeSession());

      await repository.saveSession(
        makeSession(status: SessionStatus.completed, sampleCount: 42),
      );

      final all = await repository.listSessions();
      expect(all, hasLength(1));
      expect(all.single.status, SessionStatus.completed);
      expect(all.single.sampleCount, 42);
    });

    test('re-saving a session keeps its samples', () async {
      // Stopping a recording rewrites the session row with its final status
      // and count. If that were an INSERT OR REPLACE, SQLite would delete the
      // old row first and the ON DELETE CASCADE would take every sample with
      // it — the recording would end by erasing itself.
      final repository = makeRepository();
      await repository.saveSession(makeSession());
      await repository.appendSamples('session-1', samplesAt(1000, tags: 3));

      await repository.saveSession(
        makeSession(status: SessionStatus.completed, sampleCount: 3),
      );

      expect(await repository.countSamples('session-1'), 3);
      expect((await repository.findSession('session-1'))!.status,
          SessionStatus.completed);
    });

    test('lists sessions newest first', () async {
      final repository = makeRepository();
      await repository.saveSession(
        makeSession(id: 'older', createdAt: DateTime.utc(2026, 8, 1)),
      );
      await repository.saveSession(
        makeSession(id: 'newer', createdAt: DateTime.utc(2026, 8, 16)),
      );

      final sessions = await repository.listSessions();
      expect(sessions.map((s) => s.id), ['newer', 'older']);
    });

    test('returns null for an unknown session', () async {
      expect(await makeRepository().findSession('nope'), isNull);
    });

    test('listing does not read samples', () async {
      // Metadata and samples are separate tables precisely so that listing a
      // multi-hour recording stays cheap.
      final repository = makeRepository();
      await repository.saveSession(makeSession());
      await repository.appendSamples('session-1', samplesAt(1000));

      final sessions = await repository.listSessions();

      expect(sessions.single.sampleCount, 0,
          reason: 'the cached count is metadata, not a row scan');
    });
  });

  group('samples', () {
    test('append in batches and read back in time order', () async {
      final repository = makeRepository();
      await repository.saveSession(makeSession());

      await repository.appendSamples('session-1', [
        ...samplesAt(3000),
        ...samplesAt(1000),
        ...samplesAt(2000),
      ]);

      final samples = await repository.samplesForSession('session-1');
      expect(samples.map((s) => s.timestampMicros),
          [1000, 1000, 2000, 2000, 3000, 3000]);
      expect(await repository.countSamples('session-1'), 6);
    });

    test('survive a round trip exactly', () async {
      final repository = makeRepository();
      await repository.saveSession(makeSession());
      final original = PositionSample(
        timestampMicros: 1786000000123456,
        tagId: 'tag-7',
        x: 12.3456789,
        y: 7.6543211,
        confidence: 0.8125,
      );

      await repository.appendSamples('session-1', [original]);

      expect((await repository.samplesForSession('session-1')).single,
          original);
    });

    test('are queried by time range for scrubbing', () async {
      final repository = makeRepository();
      await repository.saveSession(makeSession());
      await repository.appendSamples('session-1', [
        for (var t = 1000; t <= 10000; t += 1000) ...samplesAt(t, tags: 1),
      ]);

      final window = await repository.samplesForSession(
        'session-1',
        fromMicros: 3000,
        toMicros: 5000,
      );

      expect(window.map((s) => s.timestampMicros), [3000, 4000, 5000]);
    });

    test('respect a row limit', () async {
      final repository = makeRepository();
      await repository.saveSession(makeSession());
      await repository.appendSamples('session-1', [
        for (var t = 1000; t <= 10000; t += 1000) ...samplesAt(t, tags: 1),
      ]);

      final limited =
          await repository.samplesForSession('session-1', limit: 3);

      expect(limited, hasLength(3));
      expect(limited.first.timestampMicros, 1000);
    });

    test('group into frames for the canvas', () async {
      final repository = makeRepository();
      await repository.saveSession(makeSession());
      await repository.appendSamples('session-1', [
        ...samplesAt(1000, tags: 3),
        ...samplesAt(2000, tags: 3),
      ]);

      final frames = await repository.framesForSession('session-1');

      expect(frames, hasLength(2));
      expect(frames.first.timestampMicros, 1000);
      expect(frames.first.samples, hasLength(3));
    });

    test('report the recorded time range', () async {
      final repository = makeRepository();
      await repository.saveSession(makeSession());
      await repository.appendSamples('session-1', [
        ...samplesAt(5000),
        ...samplesAt(90000),
      ]);

      expect(await repository.timeRange('session-1'),
          (firstMicros: 5000, lastMicros: 90000));
    });

    test('report no range for an empty recording', () async {
      final repository = makeRepository();
      await repository.saveSession(makeSession());
      expect(await repository.timeRange('session-1'), isNull);
    });

    test('appending an empty list is a no-op', () async {
      final repository = makeRepository();
      await repository.saveSession(makeSession());
      await repository.appendSamples('session-1', const []);
      expect(await repository.countSamples('session-1'), 0);
    });

    test('are kept apart between sessions', () async {
      final repository = makeRepository();
      await repository.saveSession(makeSession(id: 'a'));
      await repository.saveSession(makeSession(id: 'b'));

      await repository.appendSamples('a', samplesAt(1000, tags: 2));
      await repository.appendSamples('b', samplesAt(1000, tags: 5));

      expect(await repository.countSamples('a'), 2);
      expect(await repository.countSamples('b'), 5);
    });
  });

  group('deletion', () {
    test('removes a session and its samples', () async {
      final repository = makeRepository();
      await repository.saveSession(makeSession());
      await repository.appendSamples('session-1', samplesAt(1000));

      await repository.deleteSession('session-1');

      expect(await repository.findSession('session-1'), isNull);
      expect(await repository.countSamples('session-1'), 0);
    });

    test('leaves other sessions untouched', () async {
      final repository = makeRepository();
      await repository.saveSession(makeSession(id: 'a'));
      await repository.saveSession(makeSession(id: 'b'));
      await repository.appendSamples('b', samplesAt(1000));

      await repository.deleteSession('a');

      expect(await repository.findSession('b'), isNotNull);
      expect(await repository.countSamples('b'), 2);
    });
  });

  test('schema reserves a table for raw UWB measurements', () async {
    // Recording raw ranges later must not be a migration of captured data.
    final repository = makeRepository();
    await repository.saveSession(makeSession());

    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: kinetagSchemaVersion,
          onCreate: (db, version) => migrate(db, 0, version),
        ));
    addTearDown(db.close);

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    expect(
      tables.map((t) => t['name']),
      containsAll(['sessions', 'position_samples', 'raw_measurements']),
    );
  });

  test('the sample index covers session and time', () async {
    // Without this index replay scrubbing degrades to a full table scan.
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: kinetagSchemaVersion,
          onCreate: (db, version) => migrate(db, 0, version),
        ));
    addTearDown(db.close);

    final plan = await db.rawQuery(
      'EXPLAIN QUERY PLAN SELECT * FROM position_samples '
      'WHERE session_id = ? AND timestamp_micros >= ?',
      ['s', 0],
    );

    expect(
      plan.map((row) => row.values.join(' ')).join(' '),
      contains('idx_position_samples_session_time'),
    );
  });
}

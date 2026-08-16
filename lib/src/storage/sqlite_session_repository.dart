import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/domain.dart';
import 'kinetag_database.dart';
import 'session_repository.dart';

/// SQLite-backed [SessionRepository].
///
/// ## Why the setup snapshot is a JSON column
///
/// Court, receivers, tags, players and assignments are frozen at the moment
/// recording starts (decision 5) and are only ever read back whole, alongside
/// the session itself. Normalising them into five more tables would buy
/// queries nobody makes and cost a join on every list, while making it easy
/// to accidentally *share* a receiver row between the live setup and a
/// recording — precisely the corruption the by-value rule exists to prevent.
/// Everything the session list actually filters or sorts on (name, status,
/// times, sample count) lives in real columns.
class SqliteSessionRepository implements SessionRepository {
  final Future<Database> Function() _open;

  Future<Database>? _database;

  /// [open] is injectable so tests can point at an in-memory database.
  SqliteSessionRepository({Future<Database> Function()? open})
      : _open = open ?? openKinetagDatabase;

  /// Opens on first use and memoises, so the many small calls a screen makes
  /// share one connection.
  Future<Database> get _db => _database ??= _open();

  @override
  Future<void> saveSession(Session session) async {
    final db = await _db;
    final row = _sessionRow(session);

    // Update-then-insert rather than INSERT OR REPLACE. In SQLite, REPLACE
    // *deletes* the conflicting row before inserting the new one, which fires
    // `position_samples`' ON DELETE CASCADE — so stamping a session as
    // completed at the end of a recording would silently delete every sample
    // it had just written.
    await db.transaction((txn) async {
      final updated = await txn.update(
        'sessions',
        row,
        where: 'id = ?',
        whereArgs: [session.id],
      );
      if (updated == 0) await txn.insert('sessions', row);
    });
  }

  @override
  Future<List<Session>> listSessions() async {
    final db = await _db;
    final rows = await db.query('sessions', orderBy: 'created_at_micros DESC');
    return [for (final row in rows) _sessionFromRow(row)];
  }

  @override
  Future<Session?> findSession(String id) async {
    final db = await _db;
    final rows = await db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _sessionFromRow(rows.first);
  }

  @override
  Future<void> deleteSession(String id) async {
    final db = await _db;
    // Samples go with the session via ON DELETE CASCADE, but the delete is
    // issued explicitly as well so the behaviour does not depend on the
    // foreign-keys pragma having been applied to this connection.
    await db.transaction((txn) async {
      await txn.delete(
        'position_samples',
        where: 'session_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'raw_measurements',
        where: 'session_id = ?',
        whereArgs: [id],
      );
      await txn.delete('sessions', where: 'id = ?', whereArgs: [id]);
    });
  }

  @override
  Future<void> appendSamples(
    String sessionId,
    List<PositionSample> samples,
  ) async {
    if (samples.isEmpty) return;
    final db = await _db;

    // One transaction per batch. Inserting row by row outside a transaction
    // means one fsync per row, which at 30 tags x 100 Hz is 3000 disk syncs a
    // second and is the difference between a recording that keeps up and one
    // that does not.
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final sample in samples) {
        batch.insert('position_samples', {
          'session_id': sessionId,
          'timestamp_micros': sample.timestampMicros,
          'tag_id': sample.tagId,
          'x': sample.x,
          'y': sample.y,
          'confidence': sample.confidence,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<List<PositionSample>> samplesForSession(
    String sessionId, {
    int? fromMicros,
    int? toMicros,
    int? limit,
  }) async {
    final db = await _db;

    final where = StringBuffer('session_id = ?');
    final args = <Object?>[sessionId];
    if (fromMicros != null) {
      where.write(' AND timestamp_micros >= ?');
      args.add(fromMicros);
    }
    if (toMicros != null) {
      where.write(' AND timestamp_micros <= ?');
      args.add(toMicros);
    }

    final rows = await db.query(
      'position_samples',
      where: where.toString(),
      whereArgs: args,
      // Tag order within an instant keeps reads reproducible; the index
      // covers the leading columns, so this stays a range scan.
      orderBy: 'timestamp_micros ASC, tag_id ASC',
      limit: limit,
    );

    return [
      for (final row in rows)
        PositionSample(
          timestampMicros: row['timestamp_micros']! as int,
          tagId: row['tag_id']! as String,
          x: (row['x']! as num).toDouble(),
          y: (row['y']! as num).toDouble(),
          confidence: (row['confidence']! as num).toDouble(),
        ),
    ];
  }

  @override
  Future<List<PositionFrame>> framesForSession(
    String sessionId, {
    int? fromMicros,
    int? toMicros,
    int? limit,
  }) async {
    final samples = await samplesForSession(
      sessionId,
      fromMicros: fromMicros,
      toMicros: toMicros,
      limit: limit,
    );
    return PositionFrame.groupByTimestamp(samples);
  }

  @override
  Future<int> countSamples(String sessionId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM position_samples WHERE session_id = ?',
      [sessionId],
    );
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<({int firstMicros, int lastMicros})?> timeRange(
      String sessionId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT MIN(timestamp_micros) AS first, MAX(timestamp_micros) AS last '
      'FROM position_samples WHERE session_id = ?',
      [sessionId],
    );

    final first = rows.first['first'] as int?;
    final last = rows.first['last'] as int?;
    if (first == null || last == null) return null;
    return (firstMicros: first, lastMicros: last);
  }

  @override
  Future<void> close() async {
    final database = _database;
    _database = null;
    if (database != null) await (await database).close();
  }

  Map<String, Object?> _sessionRow(Session session) => {
        'id': session.id,
        'name': session.name,
        'created_at_micros': session.createdAt.toUtc().microsecondsSinceEpoch,
        'started_at_micros':
            session.startedAt?.toUtc().microsecondsSinceEpoch,
        'stopped_at_micros':
            session.stoppedAt?.toUtc().microsecondsSinceEpoch,
        'status': session.status.name,
        'sample_count': session.sampleCount,
        'positioning_algorithm_version': session.positioningAlgorithmVersion,
        'setup_json': jsonEncode({
          'court': session.court.toJson(),
          'receivers': [for (final r in session.receivers) r.toJson()],
          'tags': [for (final t in session.tags) t.toJson()],
          'players': [for (final p in session.players) p.toJson()],
          'tagAssignments': [
            for (final a in session.tagAssignments) a.toJson(),
          ],
        }),
      };

  Session _sessionFromRow(Map<String, Object?> row) {
    final setup = jsonDecode(row['setup_json']! as String) as Map<String, dynamic>;

    return Session(
      id: row['id']! as String,
      name: row['name']! as String,
      createdAt: _time(row['created_at_micros'])!,
      court: Court.fromJson(setup['court'] as Map<String, dynamic>),
      receivers: [
        for (final r in setup['receivers'] as List)
          Receiver.fromJson(r as Map<String, dynamic>),
      ],
      tags: [
        for (final t in setup['tags'] as List)
          Tag.fromJson(t as Map<String, dynamic>),
      ],
      players: [
        for (final p in setup['players'] as List)
          Player.fromJson(p as Map<String, dynamic>),
      ],
      tagAssignments: [
        for (final a in setup['tagAssignments'] as List)
          TagAssignment.fromJson(a as Map<String, dynamic>),
      ],
      status: SessionStatus.values.byName(row['status']! as String),
      startedAt: _time(row['started_at_micros']),
      stoppedAt: _time(row['stopped_at_micros']),
      sampleCount: (row['sample_count'] as num?)?.toInt() ?? 0,
      positioningAlgorithmVersion:
          row['positioning_algorithm_version']! as String,
    );
  }

  static DateTime? _time(Object? micros) => micros == null
      ? null
      : DateTime.fromMicrosecondsSinceEpoch(micros as int, isUtc: true);
}

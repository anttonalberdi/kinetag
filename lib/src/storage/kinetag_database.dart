import 'dart:io' show Platform;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

/// Schema version. Bump together with a branch in [migrate].
const int kinetagSchemaVersion = 1;

/// Opens (creating if needed) the Kinetag database.
///
/// ## Why two sqflite packages
///
/// `sqflite` is a plugin backed by the platform's own SQLite on iOS and
/// Android; on macOS, Windows and Linux there is no such plugin, so
/// `sqflite_common_ffi` binds SQLite through dart:ffi instead. Both expose the
/// identical [DatabaseFactory] API, so the split is confined to this one
/// function and nothing above it can tell which is in use.
Future<Database> openKinetagDatabase({String? path}) async {
  final factory = kinetagDatabaseFactory();
  final databasePath = path ?? await defaultDatabasePath();

  return factory.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(
      version: kinetagSchemaVersion,
      onConfigure: (db) async {
        // Required for the ON DELETE CASCADE that keeps samples from
        // outliving their session; SQLite leaves it off by default.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) => migrate(db, 0, version),
      onUpgrade: migrate,
    ),
  );
}

/// The factory appropriate to the current platform.
DatabaseFactory kinetagDatabaseFactory() {
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    ffi.sqfliteFfiInit();
    return ffi.databaseFactoryFfi;
  }
  return databaseFactory;
}

/// `<application support>/kinetag.db`.
///
/// Application support rather than documents: a recording database is
/// application state, not a user-facing file to be browsed or synced.
Future<String> defaultDatabasePath() async {
  final directory = await getApplicationSupportDirectory();
  return p.join(directory.path, 'kinetag.db');
}

/// Applies every migration between [from] and [to].
///
/// Written as a fall-through ladder so a database created at any earlier
/// version reaches the current one by the same code path a fresh install
/// takes.
Future<void> migrate(Database db, int from, int to) async {
  if (from < 1) await _createV1(db);
}

Future<void> _createV1(Database db) async {
  // Session metadata is split from samples deliberately. Listing sessions
  // must never read a multi-hour recording's rows, and replay must be able to
  // seek into samples without loading the metadata repeatedly.
  await db.execute('''
    CREATE TABLE sessions (
      id                            TEXT    PRIMARY KEY,
      name                          TEXT    NOT NULL,
      created_at_micros             INTEGER NOT NULL,
      started_at_micros             INTEGER,
      stopped_at_micros             INTEGER,
      status                        TEXT    NOT NULL,
      sample_count                  INTEGER NOT NULL DEFAULT 0,
      positioning_algorithm_version TEXT    NOT NULL,
      setup_json                    TEXT    NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE position_samples (
      session_id       TEXT    NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
      timestamp_micros INTEGER NOT NULL,
      tag_id           TEXT    NOT NULL,
      x                REAL    NOT NULL,
      y                REAL    NOT NULL,
      confidence       REAL    NOT NULL
    )
  ''');

  // The index that makes replay scrubbing cheap: seeking to a time is a
  // range scan on (session_id, timestamp_micros) instead of a table scan
  // over every sample ever recorded.
  await db.execute('''
    CREATE INDEX idx_position_samples_session_time
      ON position_samples (session_id, timestamp_micros)
  ''');

  // Reserved for raw UWB measurements — ranges, time differences, per-anchor
  // quality — so that a session can later be reprocessed with an improved
  // positioning algorithm and the result told apart via
  // `Session.positioningAlgorithmVersion`. Nothing writes to it yet; it
  // exists now so that adding hardware is not a migration of recorded data.
  await db.execute('''
    CREATE TABLE raw_measurements (
      id               INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id       TEXT    NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
      timestamp_micros INTEGER NOT NULL,
      tag_id           TEXT    NOT NULL,
      receiver_id      TEXT    NOT NULL,
      kind             TEXT    NOT NULL,
      value            REAL    NOT NULL,
      quality          REAL,
      payload_json     TEXT
    )
  ''');

  await db.execute('''
    CREATE INDEX idx_raw_measurements_session_time
      ON raw_measurements (session_id, timestamp_micros)
  ''');
}

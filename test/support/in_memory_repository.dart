import 'package:kinetag/src/storage/kinetag_database.dart';
import 'package:kinetag/src/storage/session_repository.dart';
import 'package:kinetag/src/storage/sqlite_session_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A real [SqliteSessionRepository] backed by an in-memory database.
///
/// Tests exercise the production SQL rather than a hand-written fake, so a
/// query or migration mistake fails here rather than on someone's laptop.
SessionRepository makeInMemoryRepository() => SqliteSessionRepository(
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

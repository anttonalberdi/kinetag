import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/domain.dart';
import 'session_repository.dart';
import 'sqlite_session_repository.dart';

/// The application's session store.
///
/// The database is opened lazily on first use inside the repository, so this
/// provider stays synchronous and no screen has to await a connection just to
/// build.
final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  final repository = SqliteSessionRepository();
  ref.onDispose(repository.close);
  return repository;
});

/// Recorded sessions, newest first.
///
/// Invalidate this after a recording finishes or a session is deleted to
/// refresh the browser.
final sessionListProvider = FutureProvider<List<Session>>(
  (ref) => ref.watch(sessionRepositoryProvider).listSessions(),
);

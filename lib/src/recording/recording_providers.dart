import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/storage_providers.dart';
import 'buffered_recording_sink.dart';
import 'recording_sink.dart';

/// The sink every recording is written through.
///
/// Batches into SQLite via [BufferedRecordingSink]. Tests override this with
/// `InMemoryRecordingSink`; nothing in the UI knows the difference.
final recordingSinkProvider = Provider<RecordingSink>((ref) {
  final sink = BufferedRecordingSink(
    repository: ref.watch(sessionRepositoryProvider),
  );
  ref.onDispose(sink.dispose);
  return sink;
});

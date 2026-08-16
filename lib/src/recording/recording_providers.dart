import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'recording_sink.dart';

/// The sink every recording is written through.
///
/// Phase 7 overrides this with the SQLite-backed implementation; nothing in
/// the UI needs to know which one is in place.
final recordingSinkProvider =
    Provider<RecordingSink>((ref) => InMemoryRecordingSink());

import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/storage/session_repository.dart';

/// A completed session with [frameCount] frames of [tagCount] tags, spaced
/// [stepMicros] apart.
Future<Session> seedRecording(
  SessionRepository repository, {
  String id = 'session-1',
  String name = 'Recorded session',
  int frameCount = 10,
  int tagCount = 2,
  int stepMicros = 100000,
  int firstMicros = 1786000000000000,
}) async {
  final players = [
    for (var i = 0; i < tagCount; i++)
      Player(
        id: 'player-$i',
        name: 'Player $i',
        number: i + 1,
        team: i.isEven ? 'Home' : 'Away',
      ),
  ];

  final session = Session(
    id: id,
    name: name,
    createdAt: DateTime.fromMicrosecondsSinceEpoch(firstMicros, isUtc: true),
    court: Court.handball(),
    receivers: const [
      Receiver(id: 'rx-1', name: 'RX-01', x: -1.2, y: -1.2, z: 2.4),
    ],
    tags: [
      for (var i = 0; i < tagCount; i++)
        Tag(id: 'tag-$i', hardwareId: 'SIM-000$i', name: 'Tag $i'),
    ],
    players: players,
    tagAssignments: [
      for (var i = 0; i < tagCount; i++)
        TagAssignment(id: 'a-$i', playerId: 'player-$i', tagId: 'tag-$i'),
    ],
    status: SessionStatus.completed,
    startedAt: DateTime.fromMicrosecondsSinceEpoch(firstMicros, isUtc: true),
    stoppedAt: DateTime.fromMicrosecondsSinceEpoch(
      firstMicros + frameCount * stepMicros,
      isUtc: true,
    ),
    sampleCount: frameCount * tagCount,
  );

  await repository.saveSession(session);
  await repository.appendSamples(session.id, [
    for (var f = 0; f < frameCount; f++)
      for (var t = 0; t < tagCount; t++)
        PositionSample(
          timestampMicros: firstMicros + f * stepMicros,
          tagId: 'tag-$t',
          x: f.toDouble() + t,
          y: 5.0 + t,
        ),
  ]);

  return session;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart'
    show LoggerLevel, getLoggingLevel, logger, setLoggingLevel;
import 'package:logging/logging.dart';

/// Régression : au démarrage, `main()` appelait `setLoggingLevel()` du SDK
/// LiveKit sans avoir activé le mode hiérarchique de `package:logging`, ce qui
/// levait une `UnsupportedError` avant `runApp()` (application bloquée).
void main() {
  setUp(() {
    hierarchicalLoggingEnabled = true;
    Logger.root.level = Level.FINEST;
  });

  test('setLoggingLevel fonctionne sur le logger non-root du SDK', () {
    expect(() => setLoggingLevel(LoggerLevel.kFINEST), returnsNormally);
    expect(getLoggingLevel(), Level.FINEST);
    expect(
      () => setLoggingLevel(LoggerLevel.kWARNING),
      returnsNormally,
      reason: 'le niveau doit rester modifiable après coup',
    );
    expect(getLoggingLevel(), Level.WARNING);
  });

  test('les logs du SDK remontent jusqu au listener du root logger', () {
    setLoggingLevel(LoggerLevel.kFINEST);

    final records = <LogRecord>[];
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(subscription.cancel);

    logger.fine('un message du SDK');

    expect(
      records.map((record) => record.message),
      contains('un message du SDK'),
    );
    expect(records.single.loggerName, 'livekit');
  });
}

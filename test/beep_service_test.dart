import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videolog_coach/core/beep_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('videolog/beep');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('le bip appelle le canal natif « beep »', () async {
    var called = '';
    messenger.setMockMethodCallHandler(channel, (call) async {
      called = call.method;
      return true;
    });
    await BeepService.beep();
    expect(called, 'beep');
  });

  test('canal absent : repli sur le son système, sans lever d\'erreur', () async {
    messenger.setMockMethodCallHandler(channel, null);
    await expectLater(BeepService.beep(), completes);
  });

  test('une erreur native est absorbée', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'KO');
    });
    await expectLater(BeepService.beep(), completes);
  });
}

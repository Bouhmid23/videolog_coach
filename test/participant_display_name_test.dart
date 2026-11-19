import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videolog_coach/presentation/widgets/no_video.dart';
import 'package:videolog_coach/presentation/widgets/participant_info.dart';
import 'package:videolog_coach/utils.dart';

void main() {
  group('baseUidForIdentity & isWebParticipantIdentity', () {
    test('extracts base UID from mobile, web and suffixed identities', () {
      expect(baseUidForIdentity('uid_abc123'), 'uid_abc123');
      expect(baseUidForIdentity('uid_abc123:web'), 'uid_abc123');
      expect(baseUidForIdentity('uid_abc123#1a2b'), 'uid_abc123');
      expect(baseUidForIdentity('  uid_abc123:web  '), 'uid_abc123');
    });

    test('detects web client identity suffix', () {
      expect(isWebParticipantIdentity('uid_abc123:web'), isTrue);
      expect(isWebParticipantIdentity('uid_abc123'), isFalse);
      expect(isWebParticipantIdentity('uid_abc123:mobile'), isFalse);
    });
  });

  group('displayNameFromIdentityAndName', () {
    test('prefers LiveKit participant.name over Firebase UID identity', () {
      expect(
        displayNameFromIdentityAndName(
          identity: 'firebaseUid987654321',
          name: 'Marc Martin',
        ),
        'Marc Martin',
      );
      expect(
        displayNameFromIdentityAndName(
          identity: 'firebaseUid987654321:web',
          name: 'Coach Dupont',
        ),
        'Coach Dupont',
      );
    });

    test('uses fallbackName when participant.name is empty or equals UID', () {
      expect(
        displayNameFromIdentityAndName(
          identity: 'firebaseUid987654321',
          name: '',
          fallbackName: 'Alice Moreau',
        ),
        'Alice Moreau',
      );
      expect(
        displayNameFromIdentityAndName(
          identity: 'firebaseUid987654321:web',
          name: 'firebaseUid987654321',
          fallbackName: 'Coach Bernard',
        ),
        'Coach Bernard',
      );
      expect(
        displayNameFromIdentityAndName(
          identity: 'firebaseUid987654321:web',
          name: 'firebaseUid987654321:web',
          fallbackName: 'Coach Bernard',
        ),
        'Coach Bernard',
      );
    });

    test('preserves colons inside human display names', () {
      expect(
        displayNameFromIdentityAndName(
          identity: 'firebaseUid987654321:web',
          name: 'Coach: Marc',
        ),
        'Coach: Marc',
      );
    });

    test('falls back cleanly to base UID without :web or #suffix', () {
      expect(
        displayNameFromIdentityAndName(
          identity: 'firebaseUid987654321:web',
          name: '',
        ),
        'firebaseUid987654321',
      );
      expect(
        displayNameFromIdentityAndName(
          identity: 'alice#1a2b',
          name: '',
        ),
        'alice',
      );
    });
  });

  group('ParticipantInfoWidget', () {
    testWidgets('renders resolved participant title badge without titleContent', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 180,
              child: ParticipantInfoWidget(
                title: 'Marc Martin',
              ),
            ),
          ),
        ),
      );

      expect(find.text('Marc Martin'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders both title badge and titleContent cleanly', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: ParticipantInfoWidget(
                title: 'Coach Dupont',
                titleContent: Text('142 bpm'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Coach Dupont'), findsOneWidget);
      expect(find.text('142 bpm'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('omits name badge when title is null or blank', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 180,
              child: ParticipantInfoWidget(title: '   '),
            ),
          ),
        ),
      );

      expect(find.byType(Text), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('NoVideoWidget', () {
    testWidgets('renders participant name when showLabel is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 240,
              height: 240,
              child: NoVideoWidget(
                participantName: 'Marc Martin',
                showLabel: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Marc Martin'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides participant name when showLabel is false or tiny box', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 180,
              height: 120,
              child: NoVideoWidget(
                participantName: 'Marc Martin',
                showLabel: false,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Marc Martin'), findsNothing);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 80,
              height: 70,
              child: NoVideoWidget(
                participantName: 'Marc Martin',
                showLabel: true,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Marc Martin'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

import 'package:flutter/material.dart';

import 'theme.dart';

extension LKExampleExt on BuildContext {
  //
  Future<bool?> showPublishDialog() => showDialog<bool>(
    context: this,
    builder: (ctx) => AlertDialog(
      title: const Text('Publier'),
      content: const Text('Voulez-vous activer votre caméra et votre microphone ?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Publier'),
        ),
      ],
    ),
  );

  Future<bool?> showPlayAudioManuallyDialog() => showDialog<bool>(
    context: this,
    builder: (ctx) => AlertDialog(
      title: const Text('Activer le son'),
      content: const Text('Vous devez activer manuellement la lecture audio sur iOS Safari.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Ignorer'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Activer'),
        ),
      ],
    ),
  );

  Future<bool?> showUnPublishDialog() => showDialog<bool>(
    context: this,
    builder: (ctx) => AlertDialog(
      title: const Text('Arrêter la publication'),
      content: const Text('Voulez-vous couper votre caméra et votre microphone ?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Couper'),
        ),
      ],
    ),
  );

  Future<void> showErrorDialog(dynamic exception) => showDialog<void>(
    context: this,
    builder: (ctx) => AlertDialog(
      title: const Text('Erreur'),
      content: Text(exception.toString()),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Fermer'),
        )
      ],
    ),
  );

  Future<bool?> showDisconnectDialog() => showDialog<bool>(
    context: this,
    builder: (ctx) => AlertDialog(
      title: const Text('Quitter la session'),
      content: const Text('Voulez-vous vraiment quitter la session en cours ?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: LKColors.danger,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Quitter'),
        ),
      ],
    ),
  );

  Future<bool?> showReconnectDialog() => showDialog<bool>(
    context: this,
    builder: (ctx) => AlertDialog(
      title: const Text('Reconnexion'),
      content: const Text('Cela va forcer une reconnexion à la session.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Reconnecter'),
        ),
      ],
    ),
  );

  Future<void> showReconnectSuccessDialog() => showDialog<void>(
    context: this,
    builder: (ctx) => AlertDialog(
      title: const Text('Reconnexion'),
      content: const Text('La reconnexion a réussi.'),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  Future<bool?> showSendDataDialog() => showDialog<bool>(
    context: this,
    builder: (ctx) => AlertDialog(
      title: const Text('Envoyer des données'),
      content: const Text('Cela enverra un message de test à tous les participants.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Envoyer'),
        ),
      ],
    ),
  );

  Future<bool?> showRecordingStatusChangedDialog(bool isActiveRecording) => showDialog<bool>(
    context: this,
    builder: (ctx) => AlertDialog(
      title: const Text('Enregistrement de la session'),
      content: Text(
        isActiveRecording
            ? 'L\'enregistrement de la session est actif.'
            : 'L\'enregistrement de la session est arrêté.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  Future<bool?> showSubscribePermissionDialog() => showDialog<bool>(
    context: this,
    builder: (ctx) => AlertDialog(
      title: const Text('Allow subscription'),
      content: const Text('Allow all participants to subscribe tracks published by local participant?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('NO'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('YES'),
        ),
      ],
    ),
  );

  Future<SimulateScenarioResult?> showSimulateScenarioDialog() => showDialog<SimulateScenarioResult>(
    context: this,
    builder: (ctx) => SimpleDialog(
      title: const Text('Simulate Scenario'),
      children: SimulateScenarioResult.values
          .map((e) => SimpleDialogOption(
        child: Text(e.name),
        onPressed: () => Navigator.pop(ctx, e),
      ))
          .toList(),
    ),
  );
}

enum SimulateScenarioResult {
  signalReconnect,
  fullReconnect,
  speakerUpdate,
  nodeFailure,
  migration,
  serverLeave,
  switchCandidate,
  e2eeKeyRatchet,
  participantName,
  participantMetadata,
  clear,
}
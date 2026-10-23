/// Rôle du participant dans une session de coaching.
///
/// - [trainee] : l'athlète — publie posture, télémétrie et utilise les lunettes.
/// - [coach] : l'observateur — regarde le flux, le squelette et la télémétrie.
enum UserRole {
  trainee('trainee', 'Trainee'),
  coach('coach', 'Coach');

  const UserRole(this.wire, this.label);

  /// Valeur transmise sur le réseau (`payload.role`).
  final String wire;

  /// Libellé d'affichage.
  final String label;

  bool get isCoach => this == UserRole.coach;
  bool get isTrainee => this == UserRole.trainee;

  static UserRole fromWire(String? value) => UserRole.values.firstWhere(
        (role) => role.wire == value,
        orElse: () => UserRole.trainee,
      );
}

import 'dart:ffi';
import 'dart:io';

/// Cède au processus [pid] le droit de passer au premier plan (Windows).
///
/// Windows empêche un processus en arrière-plan de prendre le premier plan :
/// sans cette autorisation, la fenêtre OMNIA déjà ouverte, qui reçoit un
/// fichier déposé sur l'icône, ne pourrait que faire clignoter son bouton dans
/// la barre des tâches. La seconde instance, que l'utilisateur vient de lancer,
/// détient ce droit et le transmet à la première avant de lui confier le
/// fichier.
///
/// Retourne `true` si Windows a accordé le droit ; `false` ailleurs que sous
/// Windows, et en cas de refus — ce n'est jamais bloquant.
bool allowForegroundWindow(int pid) {
  if (!Platform.isWindows) return false;
  try {
    final allow = DynamicLibrary.open('user32.dll')
        .lookupFunction<Int32 Function(Uint32), int Function(int)>('AllowSetForegroundWindow');
    return allow(pid) != 0;
  } on Object {
    return false;
  }
}

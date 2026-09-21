#include "my_application.h"

int main(int argc, char** argv) {
  // Sous Linux (notamment GNOME / Ubuntu), X11/XWayland permet le maintien
  // au premier plan (Always-on-Top / gtk_window_set_keep_above) ainsi que
  // le positionnement dynamique et le verrouillage de ratio du mini-lecteur,
  // qui sont restreints par le protocole Wayland pur.
  if (!g_getenv("GDK_BACKEND")) {
    g_setenv("GDK_BACKEND", "x11", FALSE);
  }

  // Définit le nom d'application pour GLib, GTK et les portails XDG (dialogues
  // de sélection de fichiers, notifications) afin d'afficher « OMNIA ».
  g_set_prgname("omnia");
  g_set_application_name("OMNIA");

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}

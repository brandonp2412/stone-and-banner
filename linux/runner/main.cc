#include "my_application.h"

int main(int argc, char** argv) {
  // Flutter 3.50's Linux compositor clips the shader fallback used for NVIDIA
  // to the lower-left quarter of the window. Use CPU rasterization on hosts
  // with the proprietary NVIDIA driver until that engine regression is fixed.
  // Keep explicit renderer choices available for diagnosis and future SDKs.
  if (g_file_test("/proc/driver/nvidia/version", G_FILE_TEST_EXISTS)) {
    g_setenv("FLUTTER_LINUX_RENDERER", "software", FALSE);
  }
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}

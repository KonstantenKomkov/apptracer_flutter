#include <apptracer_flutter_aurora/plugin.h>
#include "generated_plugin_registrant.h"

int main(int argc, char** argv) {
  ApptracerFlutterAuroraPrepareRunner(argc, argv);
  aurora::FlutterApp app(argc, argv);
  return app.exec();
}

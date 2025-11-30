import 'package:dart_frog/dart_frog.dart';
import 'dart:io';

import 'package:rda_disaster_management/kmz_processor.dart';

/// This entrypoint is called when the server starts.
Future<HttpServer> run(Handler handler, InternetAddress ip, int port) async {
  // MANDATORY: Call the initialization function to start the KML parsing
  // and the Cron job for Google Sheet data fetching.
  initializeTimer();

  // The rest of the server setup remains standard.
  final server = await serve(handler, ip, port);
  print('✅ Server running on http://${server.address.host}:${server.port}');
  return server;
}

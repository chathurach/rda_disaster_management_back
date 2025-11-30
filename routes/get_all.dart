import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as path;

// --- Configuration ---
const String _HIVE_BOX_NAME = 'incident_data_box';

/// Initializes Hive (must be done before opening a box).
void _ensureHiveInitialized() {
  // We use the same initialization path as the kmz_processor
  final hivePath = path.join(Directory.current.path, '.hive_db');
  Hive.init(hivePath);
}

/// Reads the entire incident dataset from the local Hive box.
Future<Map<String, dynamic>> _readDataFromHive() async {
  try {
    _ensureHiveInitialized();

    // Hive will open the box, or create it if it doesn't exist
    final box = await Hive.openBox(_HIVE_BOX_NAME);

    // Retrieve the data stored under the 'incidents' key
    // FIX: Explicitly cast the result of box.get() to the expected Map type.
    final storedData = box.get('incidents') as Map<dynamic, dynamic>?;

    await box.close(); // Close the box immediately after reading

    if (storedData == null || storedData.isEmpty) {
      return {
        'status': 'success',
        'data': [],
        'message':
            'No incident data found in Hive DB. Waiting for server update cycle.',
      };
    }

    // Since the Map keys are dynamic, we must ensure we handle the type safely
    // when accessing fields like 'data' and 'lastUpdated'.
    final data = storedData['data'] as List<dynamic>? ?? [];

    return {
      'status': 'success',
      'count': data.length,
      'data': data,
      'lastUpdated': storedData['lastUpdated'],
    };
  } on Exception catch (e) {
    print('HIVE READ ERROR: Failed to read from Hive: $e');
    return {
      'status': 'error',
      'data': [],
      'message': 'Error: Hive database failed to read data: $e',
    };
  } catch (e) {
    print('GENERIC READ ERROR: $e');
    return {
      'status': 'error',
      'data': [],
      'message': 'An unexpected error occurred during data retrieval.',
    };
  }
}

Future<Response> onRequest(RequestContext context) async {
  // CRITICAL CORS FIX: Handle the OPTIONS preflight request immediately.
  // The browser sends this before the actual GET request. By returning 200 OK
  // here, the routes/_middleware.dart will apply the necessary CORS headers,
  // allowing the browser to proceed with the GET request.
  if (context.request.method == HttpMethod.options) {
    return Response(statusCode: HttpStatus.ok);
  }

  // Only proceed with data fetching for the GET method.
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final result = await _readDataFromHive();

  if (result['status'] == 'error') {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: result,
    );
  }

  // Return the fetched data
  return Response.json(
    statusCode: HttpStatus.ok,
    body: result,
  );
}

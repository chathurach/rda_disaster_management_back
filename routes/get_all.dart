import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as path;

const String _HIVE_BOX_NAME = 'incident_data_box';

void _ensureHiveInitialized() {
  final hivePath = path.join(Directory.current.path, '.hive_db');
  Hive.init(hivePath);
}

Future<Map<String, dynamic>> _readDataFromHive() async {
  try {
    _ensureHiveInitialized();

    final box = await Hive.openBox(_HIVE_BOX_NAME);

    final storedData = box.get('incidents') as Map<dynamic, dynamic>?;

    await box.close();

    if (storedData == null || storedData.isEmpty) {
      return {
        'status': 'success',
        'data': [],
        'message':
            'No incident data found in Hive DB. Waiting for server update cycle.',
      };
    }

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
  if (context.request.method == HttpMethod.options) {
    return Response(statusCode: HttpStatus.ok);
  }

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

  return Response.json(
    statusCode: HttpStatus.ok,
    body: result,
  );
}

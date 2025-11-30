import 'dart:async'; // Required for Timer
import 'dart:convert';
import 'dart:io'; // Required for file system operations
import 'package:cron/cron.dart';
import 'package:dio/dio.dart' as dio;
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as path; // Required for path resolution
import 'package:rda_disaster_management/models/incident_model.dart';
import 'package:rda_disaster_management/models/processed_incedent_model.dart';

import 'kml_parser_service.dart';

// --- Configuration ---
const String _KML_FILE_PATH = 'assets/chainages.kml';
const String _HIVE_BOX_NAME = 'incident_data_box'; // Name for the Hive box
const Duration _UPDATE_INTERVAL = Duration(minutes: 15);

// CRON Schedule: Runs every 15 minutes.
const String _CRON_SCHEDULE = '*/10 * * * *';

// IMPORTANT: Google Sheet API Configuration
// Replace this with the Web App URL copied from Google Apps Script deployment.
const _googleSheetApiUrl =
    'https://script.google.com/macros/s/AKfycbypl0TLIj2nFkLaI06JWDUsgr65B_LS4-hwlqVby_gpnqAHMflPQrP3T72VznTDLQYwUA/exec';

// Initialize Dio client once
final _dio = dio.Dio();

// --- Global State ---
// This map will be populated once on startup and used for all subsequent lookups.
final ChainageLookupTable _chainageMap = _initializeChainageMap();

// --- Initialization and KML Processing ---

/// Initializes Hive, parses KML data once, and sets up the periodic data update process using cron.
void initializeTimer() {
  print('--- Data Initialization Started ---');
  try {
    // 1. Initialize Hive DB
    // Use a specific directory for the Hive files on the server
    final hivePath = path.join(Directory.current.path, '.hive_db');
    Hive.init(hivePath);
    print('INFO: Hive DB initialized at $hivePath.');

    // 2. Perform one-time KML parsing to build the chainage lookup map.
    _initializeKMLData();
    if (_chainageMap.isEmpty) {
      print(
          'FATAL WARNING: KML data failed to load/parse. Chainage lookups will fail.');
    } else {
      print('INFO: KML data successfully parsed and stored in memory.');
    }

    // 3. Perform the initial load and local database update on startup (Sheet check)
    _updateDatabaseWithLatestSheetData();

    // 4. Set up the periodic update using Cron
    final cron = Cron();
    cron.schedule(Schedule.parse(_CRON_SCHEDULE), () async {
      print(
          'INFO: Cron job triggered. Updating Hive DB with latest sheet data...');
      await _updateDatabaseWithLatestSheetData();
    });

    print(
        'INFO: Hive DB update cron job set to $_CRON_SCHEDULE (every 15 minutes).');
  } catch (e) {
    print('FATAL ERROR during Cron or Hive initialization: $e');
  }
}

/// Loads the KML file and populates the in-memory chainage lookup map (one-time operation).
void _initializeKMLData() {
  final kmlContent = _loadKMLContent();
  if (kmlContent.isEmpty) {
    print(
        'WARNING: KML content is empty or failed to load. Cannot build chainage map.');
    return;
  }

  final newChainageMap = buildChainageLookupTable(kmlContent);
  _chainageMap.clear();
  _chainageMap.addAll(newChainageMap);
}

/// Fetches the raw incident data from the Google Sheet API.
/// Returns List<dynamic> of raw incident records, or an empty list on failure.
Future<List<dynamic>> _fetchRawDataFromSheetAPI() async {
  try {
    print('INFO: Fetching raw data from Google Sheet API...');
    final response = await _dio.get(_googleSheetApiUrl);

    if (response.statusCode == 200) {
      final jsonResponse = response.data;

      if (jsonResponse is Map &&
          jsonResponse['status'] == 'success' &&
          jsonResponse['data'] is List) {
        print('SUCCESS: Data fetched successfully from Google Sheet.');
        return jsonResponse['data'] as List;
      } else {
        print(
            'WARNING: Sheet API response was successful but lacked expected data structure.');
        if (jsonResponse is Map && jsonResponse.containsKey('error')) {
          print('Sheet Script Error Details: ${jsonResponse['error']}');
        }
        return [];
      }
    } else {
      print('ERROR: Sheet API returned status code ${response.statusCode}.');
      return [];
    }
  } on dio.DioException catch (e) {
    print('DIO ERROR: Failed to fetch data from Sheet API: ${e.message}');
    return [];
  } catch (e) {
    print(
        'GENERIC FETCH ERROR: An unexpected error occurred during API call: $e');
    return [];
  }
}

/// Fetches sheet data, processes it using the in-memory KML map,
/// and updates the local Hive database.
Future<void> _updateDatabaseWithLatestSheetData() async {
  // Made async to await the fetch
  // 1. Fetch the raw incident data from the Google Sheet
  final rawData = await _fetchRawDataFromSheetAPI();

  if (rawData.isEmpty) {
    print(
        'WARNING: Skipping database update as raw data fetching failed or returned empty.');
    return;
  }

  // 2. Process the raw incident data (coordinate lookup)
  final processedData = processSheetData(rawData);

  // 3. Write the processed data to the local Hive box
  _writeProcessedDataToHive(processedData);
}

/// Helper function to load KML content from the file system.
String _loadKMLContent() {
  try {
    final file = File(path.join(Directory.current.path, _KML_FILE_PATH));
    if (!file.existsSync()) {
      print('ERROR: KML file not found at: ${file.path}');
      return '';
    }
    return file.readAsStringSync();
  } catch (e) {
    print('ERROR: Failed to load KML file: $e');
    return '';
  }
}

/// Writes the list of processed incident data to a local Hive box.
void _writeProcessedDataToHive(List<Map<String, dynamic>> data) async {
  print('INFO: Attempting to write ${data.length} incidents to Hive DB.');

  try {
    final box = await Hive.openBox(_HIVE_BOX_NAME);

    // Store the list of data under a single key for easy retrieval.
    await box.put('incidents', {
      'data': data,
      'lastUpdated': DateTime.now().toIso8601String(),
    });

    await box.close(); // Important to close the box when done writing
    print('SUCCESS: Successfully updated Hive box "$_HIVE_BOX_NAME".');
  } on HiveError catch (e) {
    print('HIVE ERROR: Failed to write data: $e');
  } catch (e) {
    print('GENERIC ERROR: Failed to write data: $e');
  }
}

// The original _initializeChainageMap is kept as a placeholder.
ChainageLookupTable _initializeChainageMap() {
  return {};
}

// --- LatLon and Processing Logic (UNCHANGED) ---

/// A simplified structure to represent a Lat/Lon pair.
class LatLon {
  final double latitude;
  final double longitude;

  LatLon(this.latitude, this.longitude);

  @override
  String toString() => '$latitude,$longitude';
}

/// Helper to parse chainage string (e.g., "95+000") into an integer (95)
/// based on whether it is the start (floor) or end (ceil) of an incident.
int _parseChainageToInt(String chainage, {required bool isToChainage}) {
  final parts = chainage.split('+');
  int kmKey = 0;
  int m = 0;

  if (parts.length == 2) {
    kmKey = int.tryParse(parts[0]) ?? 0;
    m = int.tryParse(parts[1]) ?? 0;
  } else {
    kmKey = int.tryParse(chainage) ?? 0;
  }

  int finalKey = kmKey;

  if (isToChainage && m > 0) {
    finalKey = kmKey + 1;
  } else if (!isToChainage && m > 0) {
    finalKey = kmKey;
  }

  if (finalKey == 0) {
    return 1;
  }

  return finalKey;
}

/// Finds the Lat/Lon coordinate for the given route and chainage by
/// looking it up in the pre-parsed KML data, adjusting for floor/ceil logic.
LatLon? _findLatLonForChainage(String routeNo, String chainageStr,
    {required bool isToChainage}) {
  if (routeNo.isEmpty || chainageStr.isEmpty) return null;

  final normalizedRouteNo = routeNo.replaceAll('-', '');

  if (_chainageMap.isEmpty) {
    return null;
  }

  final chainageKey =
      _parseChainageToInt(chainageStr, isToChainage: isToChainage);

  final routePoints = _chainageMap[normalizedRouteNo];

  if (routePoints != null && routePoints.containsKey(chainageKey)) {
    return routePoints[chainageKey];
  }

  return null;
}

/// Processes the raw sheet data, finds the Lat/Lon coordinates, and formats the output.
List<Map<String, dynamic>> processSheetData(List<dynamic> rawData) {
  final processedList = <Map<String, dynamic>>[];
  for (final item in rawData) {
    if (item is Map<String, dynamic>) {
      final incident = IncidentData.fromJson(item);

      if (incident.routeNo.isEmpty ||
          (incident.chainageFrom.isEmpty && incident.chainageTo.isEmpty)) {
        continue;
      }

      final latLonFrom = _findLatLonForChainage(
          incident.routeNo, incident.chainageFrom,
          isToChainage: false);
      final latLonTo = _findLatLonForChainage(
          incident.routeNo, incident.chainageTo,
          isToChainage: true);

      final processedData = ProcessedIncidentData(
        serialNo: incident.serialNo,
        routeNo: incident.routeNo,
        roadName: incident.roadName,
        chainageFrom: incident.chainageFrom,
        chainageTo: incident.chainageTo,
        latLongFrom: latLonFrom?.toString() ?? '',
        latLongTo: latLonTo?.toString() ?? '',
        reason: incident.reason,
        currentStatus: incident.currentStatus,
      );

      processedList.add(processedData.toJson());
    }
  }

  return processedList;
}

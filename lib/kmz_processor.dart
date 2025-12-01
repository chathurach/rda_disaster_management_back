import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cron/cron.dart';
import 'package:dio/dio.dart' as dio;
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as path;
import 'package:rda_disaster_management/models/incident_model.dart';
import 'package:rda_disaster_management/models/location_model.dart';
import 'package:rda_disaster_management/models/processed_incedent_model.dart';
import 'package:rda_disaster_management/models/road_segment_model.dart';
import 'package:rda_disaster_management/road_segment_kml_parser.dart';
import 'package:xml/xml.dart';

/// -------------------------
/// CONFIG
/// -------------------------
const String _CHAINAGE_KML_FILE = 'assets/chainages.kml';
const String _EE_DIVISION_KML_FILE = 'assets/ee_divisions.kml';
const String _HIVE_BOX_NAME = 'incident_data_box';
const String _CRON_SCHEDULE = '*/15 * * * *';
const String _A_CLASS_KML_FILE = 'assets/a_class.kml';
const String _B_CLASS_KML_FILE = 'assets/b_class.kml';
const String _E_CLASS_KML_FILE = 'assets/e_class.kml';

const String _GOOGLE_SHEET_API_URL =
    'https://script.google.com/macros/s/AKfycbypl0TLIj2nFkLaI06JWDUsgr65B_LS4-hwlqVby_gpnqAHMflPQrP3T72VznTDLQYwUA/exec';

final _dio = dio.Dio();

/// Chainage lookup table (routeNo -> kmKey -> LatLon)
typedef ChainageLookupTable = Map<String, Map<int, LatLon>>;
final ChainageLookupTable _chainageMap = {};

/// EE Divisions
class PolygonDivision {
  final String name;
  final List<LatLon> boundary;
  PolygonDivision(this.name, this.boundary);
}

typedef DivisionPolygonTable = List<PolygonDivision>;
late final DivisionPolygonTable _eeDivisions;
late final List<RoadSegment> _roadPolygons;

/// -------------------------
/// INITIALIZATION
/// -------------------------
void initializeTimer() {
  print('--- Data Initialization Started ---');

  try {
    final hivePath = path.join(Directory.current.path, '.hive_db');
    Hive.init(hivePath);
    print('INFO: Hive DB initialized at $hivePath.');

    _initializeKMLData();

    _updateDatabaseWithLatestSheetData();

    Cron().schedule(Schedule.parse(_CRON_SCHEDULE), () async {
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

/// -------------------------
/// KML DATA LOAD
/// -------------------------
void _initializeKMLData() {
  // --- Load chainage KML
  final chainageContent = _loadKMLContent(_CHAINAGE_KML_FILE);
  if (chainageContent.isNotEmpty) {
    final newChainageMap = buildChainageLookupTable(chainageContent);
    _chainageMap
      ..clear()
      ..addAll(newChainageMap);
    print('INFO: Chainage KML loaded. Routes: ${_chainageMap.length}');
  }

  // --- Load EE divisions KML
  final eeContent = _loadKMLContent(_EE_DIVISION_KML_FILE);
  _eeDivisions = loadEeDivisionPolygons(eeContent);
  print('INFO: EE Divisions loaded: ${_eeDivisions.length}');

  // --- Load Road polygon sections
  // --- Load Road class KMLs ---
  final aContent = _loadKMLContent(_A_CLASS_KML_FILE);
  final bContent = _loadKMLContent(_B_CLASS_KML_FILE);
  // final eContent = _loadKMLContent(_E_CLASS_KML_FILE);

  // Combine all road polygons into one list
  _roadPolygons = [
    ...loadRoadPolygonsFromKML(aContent, 'A'), // Add Road Class as context
    ...loadRoadPolygonsFromKML(bContent, 'B'),
    // ...loadRoadPolygonsFromKML(eContent, 'E'),
  ];
  print('INFO: Road Polygons loaded: ${_roadPolygons.length}');
}

String _loadKMLContent(String filePath) {
  try {
    final file = File(path.join(Directory.current.path, filePath));
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

List<LatLon> getRoadSectionCoordinates({
  required String roadName,
  required LatLon fromCoordinate,
  required LatLon toCoordinate,
  double proximityToleranceKm = 0.5, // 100 meters tolerance
}) {
  if (roadName.isEmpty || _roadPolygons.isEmpty) {
    print('Error: Road name is empty or _roadPolygons is not loaded.');
    return [];
  }

  final normalizedQueryName = _normalizeRoadName(roadName);

  // 1. Filter by Road Name (using segmentId/Link_ID for robust filtering)
  final candidateSegments = _roadPolygons.where((road) {
    // Check both the segmentId and the human-readable roadName for a match
    final normalizedSegmentId = _normalizeRoadName(road.segmentId);
    final normalizedRoadName = _normalizeRoadName(road.roadName);

    // Using contains is generally safer here for partial matches (e.g., "A-001" vs "A001-010")
    return normalizedSegmentId.contains(normalizedQueryName) ||
        normalizedRoadName.contains(normalizedQueryName);
  }).toList();

  if (candidateSegments.isEmpty) {
    print('WARNING: No road segments found for name: $roadName');
    return [];
  }

  // 2. Identify the BEST single RoadSegment (Geographic Matching)

  RoadSegment? bestSegmentMatch;
  double smallestDistance = double.infinity;

  // Find the segment whose boundary is closest to the 'from' coordinate
  for (final segment in candidateSegments) {
    double minDistanceToSegment = double.infinity;
    for (final boundaryPoint in segment.boundary) {
      final dist = _calculateDistanceKm(fromCoordinate, boundaryPoint);
      if (dist < minDistanceToSegment) {
        minDistanceToSegment = dist;
      }
    }

    if (minDistanceToSegment < smallestDistance) {
      smallestDistance = minDistanceToSegment;
      bestSegmentMatch = segment;
    }
  }

  if (bestSegmentMatch == null || smallestDistance > proximityToleranceKm) {
    print(
        'WARNING: Could not find a segment close enough to ${roadName} starting point.');
    return [];
  }

  final segmentBoundary = bestSegmentMatch.boundary;

  // 3. Find the Start and End Indices within the BEST segment's boundary array

  // Helper to find the index of the nearest boundary point
  int _findNearestIndex(LatLon point) {
    int nearestIndex = -1;
    double smallestDist = double.infinity;

    for (int i = 0; i < segmentBoundary.length; i++) {
      final dist = _calculateDistanceKm(point, segmentBoundary[i]);
      if (dist < smallestDist) {
        smallestDist = dist;
        nearestIndex = i;
      }
    }
    // We rely on the initial segment proximity check, so we don't re-check tolerance here
    return nearestIndex;
  }

  final startIndex = _findNearestIndex(fromCoordinate);
  final endIndex = _findNearestIndex(toCoordinate);

  if (startIndex == -1 || endIndex == -1) {
    print(
        'ERROR: Failed to map incident coordinates to boundary array indices.');
    return [];
  }

  // 4. Extract the ordered sub-array

  // Determine the correct range in the array
  final actualStart = min(startIndex, endIndex);
  final actualEnd = max(startIndex, endIndex);

  // Extract the raw section of the coordinates
  final sublist = segmentBoundary.sublist(actualStart, actualEnd + 1);

  // If the incident's "from" point appears later in the array than the "to" point,
  // the coordinates must be reversed to match the incident's flow direction.
  if (startIndex > endIndex) {
    return sublist.reversed.toList();
  }

  return sublist;
}

// NOTE: You might need to import this extension method if not available in Dart.
extension on Iterable<RoadSegment> {
  RoadSegment? firstWhereOrNull(bool Function(RoadSegment element) test) {
    for (var element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

String _normalizeRoadName(String name) {
  // Remove spaces, dashes, and convert to uppercase for robust matching
  return name.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
}

/// -------------------------
/// GEOSPATIAL HELPERS
/// -------------------------

// Helper function to calculate distance between two LatLon points in kilometers.
double _calculateDistanceKm(LatLon p1, LatLon p2) {
  const R = 6371; // Earth's radius in kilometers

  final lat1Rad = p1.latitude * (pi / 180);
  final lon1Rad = p1.longitude * (pi / 180);
  final lat2Rad = p2.latitude * (pi / 180);
  final lon2Rad = p2.longitude * (pi / 180);

  final dLat = lat2Rad - lat1Rad;
  final dLon = lon2Rad - lon1Rad;

  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2);

  final c = 2 * atan2(sqrt(a), sqrt(1 - a));

  return R * c; // Distance in km
}

/// -------------------------
/// GOOGLE SHEET FETCH
/// -------------------------
Future<List<dynamic>> _fetchRawDataFromSheetAPI() async {
  try {
    print('INFO: Fetching raw data from Google Sheet API...');
    final response = await _dio.get<dynamic>(_GOOGLE_SHEET_API_URL);

    if (response.statusCode == 200) {
      final jsonResponse = response.data;

      if (jsonResponse is Map &&
          jsonResponse['status'] == 'success' &&
          jsonResponse['data'] is List) {
        print('SUCCESS: Data fetched successfully from Google Sheet.');
        return jsonResponse['data'] as List;
      } else {
        print('WARNING: Sheet API response lacked expected data structure.');
        return [];
      }
    } else {
      print('ERROR: Sheet API returned status code ${response.statusCode}.');
      return [];
    }
  } on dio.DioException catch (e) {
    print('DIO ERROR: ${e.message}');
    return [];
  } catch (e) {
    print('GENERIC FETCH ERROR: $e');
    return [];
  }
}

/// -------------------------
/// PROCESS SHEET DATA
/// -------------------------
Future<void> _updateDatabaseWithLatestSheetData() async {
  final rawData = await _fetchRawDataFromSheetAPI();

  if (rawData.isEmpty) {
    print('WARNING: No data fetched. Skipping database update.');
    return;
  }

  final processedData = processSheetData(rawData);
  await _writeProcessedDataToHive(processedData);
}

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
        incident.routeNo,
        incident.chainageFrom,
        isToChainage: false,
      );
      final latLonTo = _findLatLonForChainage(
        incident.routeNo,
        incident.chainageTo,
        isToChainage: true,
      );

      // Find EE Division using 'from' coordinate (or fallback to 'to')
      String? eeDivision;
      if (latLonFrom != null) {
        eeDivision =
            getEeDivisionForPoint(latLonFrom.latitude, latLonFrom.longitude);
      } else if (latLonTo != null) {
        eeDivision =
            getEeDivisionForPoint(latLonTo.latitude, latLonTo.longitude);
      }

      //get the road section polygon
      List<LatLon> roadSection = [];
      if (latLonTo != null && latLonFrom != null) {
        final section = getRoadSectionCoordinates(
          roadName: incident.routeNo,
          fromCoordinate: latLonFrom,
          toCoordinate: latLonTo,
        );
        if (section != null) {
          roadSection.addAll(section);
        }
      }

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
        eeDivision: eeDivision ?? '',
        roadSection: roadSection
            .map(
              (coordinates) => {
                'lat': coordinates.latitude.toString(),
                'lon': coordinates.longitude.toString(),
              },
            )
            .toList(),
      );

      processedList.add(processedData.toJson());
    }
  }

  return processedList;
}

/// -------------------------
/// WRITE TO HIVE
/// -------------------------
Future<void> _writeProcessedDataToHive(List<Map<String, dynamic>> data) async {
  print('INFO: Writing ${data.length} incidents to Hive DB...');
  try {
    final box = await Hive.openBox(_HIVE_BOX_NAME);
    await box.put('incidents', {
      'data': data,
      'lastUpdated': DateTime.now().toIso8601String(),
    });
    await box.close();
    print('SUCCESS: Hive DB updated.');
  } catch (e) {
    print('ERROR: Failed to write Hive DB: $e');
  }
}

/// -------------------------
/// CHAINAGE HELPERS
/// -------------------------
int _parseChainageToInt(String chainage, {required bool isToChainage}) {
  final parts = chainage.split('+');
  var kmKey = 0;
  var m = 0;

  if (parts.length == 2) {
    kmKey = int.tryParse(parts[0]) ?? 0;
    m = int.tryParse(parts[1]) ?? 0;
  } else {
    kmKey = int.tryParse(chainage) ?? 0;
  }

  var finalKey = kmKey;

  if (isToChainage && m > 0) {
    finalKey = kmKey + 1;
  } else if (!isToChainage && m > 0) {
    finalKey = kmKey;
  }

  if (finalKey == 0) return 1;
  return finalKey;
}

LatLon? _findLatLonForChainage(
  String routeNo,
  String chainageStr, {
  required bool isToChainage,
}) {
  if (routeNo.isEmpty || chainageStr.isEmpty) return null;
  final normalizedRouteNo = routeNo.replaceAll('-', '');
  if (_chainageMap.isEmpty) return null;
  final chainageKey =
      _parseChainageToInt(chainageStr, isToChainage: isToChainage);
  final routePoints = _chainageMap[normalizedRouteNo];
  if (routePoints != null && routePoints.containsKey(chainageKey)) {
    return routePoints[chainageKey];
  }
  return null;
}

/// -------------------------
/// EE DIVISION POLYGON PARSER
/// -------------------------
DivisionPolygonTable loadEeDivisionPolygons(String kmlContent) {
  final divisions = <PolygonDivision>[];

  try {
    final document = XmlDocument.parse(kmlContent);
    final placemarks = document.findAllElements('Placemark');

    for (final placemark in placemarks) {
      final nameNode = placemark.findElements('name').firstOrNull;
      if (nameNode == null) continue;
      final divisionName = nameNode.text.trim();

      final coordsNode = placemark
          .findAllElements('coordinates')
          .firstOrNull
          ?.innerText
          .trim();
      if (coordsNode == null || coordsNode.isEmpty) continue;

      final boundaryPoints = <LatLon>[];
      final pairs = coordsNode.split(RegExp(r'\s+'));
      for (final pair in pairs) {
        final values = pair.split(',');
        if (values.length >= 2) {
          final lon = double.tryParse(values[0]);
          final lat = double.tryParse(values[1]);
          if (lat != null && lon != null) boundaryPoints.add(LatLon(lat, lon));
        }
      }

      if (boundaryPoints.isNotEmpty)
        divisions.add(PolygonDivision(divisionName, boundaryPoints));
    }
  } catch (e) {
    print('ERROR parsing EE KML: $e');
  }

  return divisions;
}

/// -------------------------
/// POINT-IN-POLYGON CHECK
/// -------------------------
bool pointInPolygon(LatLon point, List<LatLon> polygon) {
  bool inside = false;
  for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final xi = polygon[i].latitude, yi = polygon[i].longitude;
    final xj = polygon[j].latitude, yj = polygon[j].longitude;

    final intersects = ((yi > point.longitude) != (yj > point.longitude)) &&
        (point.latitude <
            (xj - xi) * (point.longitude - yi) / ((yj - yi) + 1e-10) + xi);

    if (intersects) inside = !inside;
  }
  return inside;
}

/// -------------------------
/// EE DIVISION LOOKUP
/// -------------------------
String? getEeDivisionForPoint(double lat, double lon) {
  final point = LatLon(lat, lon);
  for (final division in _eeDivisions) {
    if (pointInPolygon(point, division.boundary)) return division.name;
  }
  return null;
}

/// -------------------------
/// KML PARSER FOR CHAINAGES (existing)
/// -------------------------
Map<String, String> _extractAttributesFromDescriptionHtml(String htmlContent) {
  final attributes = <String, String>{};

  String? findValueFromStandardRow(String key) {
    final regex =
        RegExp('<td>$key</td>\\s*<td>([^<]+)</td>', caseSensitive: false);
    final match = regex.firstMatch(htmlContent);
    return match?.group(1)?.trim();
  }

  attributes['Route'] = findValueFromStandardRow('Route') ?? '';
  attributes['Chainage__'] = findValueFromStandardRow('Chainage__') ?? '';
  attributes['Latitude__'] = findValueFromStandardRow('Latitude__') ?? '';
  attributes['Longitude'] = findValueFromStandardRow('Longitude') ?? '';

  return attributes;
}

ChainageLookupTable buildChainageLookupTable(String kmlContent) {
  final lookupTable = <String, Map<int, LatLon>>{};
  try {
    final document = XmlDocument.parse(kmlContent);
    final placemarks = document.findAllElements('Placemark');
    for (final placemark in placemarks) {
      final descriptionNode = placemark.findElements('description').firstOrNull;
      if (descriptionNode != null) {
        final cdata = descriptionNode.firstChild?.text;
        if (cdata != null) {
          final attrs = _extractAttributesFromDescriptionHtml(cdata);
          final routeNo = attrs['Route'];
          final chainageStr = attrs['Chainage__'];
          final latStr = attrs['Latitude__'];
          final lonStr = attrs['Longitude'];
          final chainage = int.tryParse(chainageStr ?? '');
          final latitude = double.tryParse(latStr ?? '');
          final longitude = double.tryParse(lonStr ?? '');
          if (routeNo != null &&
              routeNo.isNotEmpty &&
              chainage != null &&
              latitude != null &&
              longitude != null) {
            final point = LatLon(latitude, longitude);
            lookupTable.putIfAbsent(routeNo, () => <int, LatLon>{});
            lookupTable[routeNo]![chainage] = point;
          }
        }
      }
    }
  } catch (e) {
    print('FATAL KML PARSER ERROR: $e');
  }
  return lookupTable;
}

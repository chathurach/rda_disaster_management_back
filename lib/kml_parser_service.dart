import 'package:xml/xml.dart';
import 'kmz_processor.dart'; // Import LatLon structure

/// Defines the final structure for a single chainage point extracted from KML.
class ChainagePoint {
  final String routeNo;
  final int chainage;
  final LatLon location;

  ChainagePoint({
    required this.routeNo,
    required this.chainage,
    required this.location,
  });
}

// Type definition for the final lookup table:
// { 'RouteNo' : { ChainageInt : LatLon } }
typedef ChainageLookupTable = Map<String, Map<int, LatLon>>;

/// Parses the HTML table content within a KML description tag to extract
/// Route, Chainage, Latitude, and Longitude.
Map<String, String> _extractAttributesFromDescriptionHtml(String htmlContent) {
  final attributes = <String, String>{};

  // Helper to find value based on preceding column header in the HTML table
  // This regex looks for <td>[Key]</td> followed by <td>[Value]</td> (ignoring the optional bgcolor row)
  String? _findValueFromStandardRow(String key) {
    // A more robust regex: look for <td>Key</td>\s*</td>? followed by <td>Value</td>
    // The structure appears to be: <tr><td>Key</td><td>Value</td></tr>
    final regex =
        RegExp('<td>$key</td>\\s*<td>([^<]+)</td>', caseSensitive: false);
    final match = regex.firstMatch(htmlContent);
    return match?.group(1)?.trim();
  }

  // Try to find attributes using the provided KML snippet structure
  attributes['Route'] = _findValueFromStandardRow('Route') ?? '';
  attributes['Chainage__'] = _findValueFromStandardRow('Chainage__') ?? '';
  attributes['Latitude__'] = _findValueFromStandardRow('Latitude__') ?? '';
  attributes['Longitude'] = _findValueFromStandardRow('Longitude') ?? '';

  return attributes;
}

/// Parses the KML content to build a lookup map for chainage points.
///
/// The KML is expected to contain <Placemark> elements where attributes
/// are stored in an HTML table within the CDATA description.
ChainageLookupTable buildChainageLookupTable(String kmlContent) {
  final lookupTable = <String, Map<int, LatLon>>{};

  try {
    final document = XmlDocument.parse(kmlContent);

    // Find all Placemarks (each is a chainage marker point)
    final placemarks = document.findAllElements('Placemark');

    if (placemarks.isEmpty) {
      print('DEBUG KML PARSER: No <Placemark> elements found in KML.');
      return {};
    }

    print('DEBUG KML PARSER: Found ${placemarks.length} Placemarks.');

    for (final placemark in placemarks) {
      final descriptionNode = placemark.findElements('description').firstOrNull;

      if (descriptionNode != null) {
        // 1. Extract the HTML content from the CDATA wrapper
        final cdata = descriptionNode.firstChild?.text;

        if (cdata != null) {
          // 2. Parse the HTML table attributes
          final attrs = _extractAttributesFromDescriptionHtml(cdata);

          final routeNo = attrs['Route'];
          final chainageStr = attrs['Chainage__'];
          final latStr = attrs['Latitude__'];
          final lonStr = attrs['Longitude'];

          // DEBUGGING OUTPUT ADDED HERE:
          print(
              'DEBUG KML PARSER: Extracted => Route: "$routeNo", Chainage: "$chainageStr", Lat: "$latStr", Lon: "$lonStr"');

          // 3. Validate and convert types
          final chainage = int.tryParse(chainageStr ?? '');
          final latitude = double.tryParse(latStr ?? '');
          final longitude = double.tryParse(lonStr ?? '');

          if (routeNo != null &&
              routeNo.isNotEmpty &&
              chainage != null &&
              latitude != null &&
              longitude != null) {
            final point = LatLon(latitude, longitude);

            // Initialize route entry if it doesn't exist
            lookupTable.putIfAbsent(routeNo, () => <int, LatLon>{});

            // Add the point to the lookup table
            lookupTable[routeNo]![chainage] = point;
          } else {
            print(
                'DEBUG KML PARSER: Validation failed for this Placemark. Check for missing/invalid data.');
          }
        }
      }
    }
  } catch (e) {
    print('FATAL KML PARSER ERROR: Could not parse XML/KML structure: $e');
    return {};
  }

  return lookupTable;
}

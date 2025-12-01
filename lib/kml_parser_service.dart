import 'package:rda_disaster_management/models/location_model.dart';
import 'package:xml/xml.dart';

///typedef for the chainage => location find
typedef ChainageLookupTable = Map<String, Map<int, LatLon>>;

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

///prepare the chainage lookup table
ChainageLookupTable buildChainageLookupTable(String kmlContent) {
  final lookupTable = <String, Map<int, LatLon>>{};

  try {
    final document = XmlDocument.parse(kmlContent);

    final placemarks = document.findAllElements('Placemark');

    if (placemarks.isEmpty) {
      print('DEBUG KML PARSER: No <Placemark> elements found in KML.');
      return {};
    }

    print('DEBUG KML PARSER: Found ${placemarks.length} Placemarks.');

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

          print(
              'DEBUG KML PARSER: Extracted => Route: "$routeNo", Chainage: "$chainageStr", Lat: "$latStr", Lon: "$lonStr"');

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

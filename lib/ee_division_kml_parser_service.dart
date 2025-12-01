import 'package:rda_disaster_management/models/ee_division_model.dart';
import 'package:rda_disaster_management/models/location_model.dart';
import 'package:xml/xml.dart';

///typedef for the EE divison polygon
typedef DivisionPolygonTable = List<EEDivisionPolygon>;

///load the kml file for the EE division from the assets
DivisionPolygonTable loadEeDivisionPolygons(String kmlContent) {
  final divisions = <EEDivisionPolygon>[];

  try {
    final document = XmlDocument.parse(kmlContent);

    final placemarks = document.findAllElements('Placemark');

    for (final placemark in placemarks) {
      final nameNode = placemark.findElements('name').firstOrNull;
      if (nameNode == null) continue;

      final divisionName = nameNode.value!.trim();

      // Find polygon coordinates
      final coordsNode = placemark
          .findAllElements('coordinates')
          .firstOrNull
          ?.innerText
          .trim();

      if (coordsNode == null || coordsNode.isEmpty) continue;

      // Parse "lon,lat,alt lon,lat,alt ..."
      final boundaryPoints = <LatLon>[];

      final pairs = coordsNode.split(RegExp(r'\s+'));
      for (final pair in pairs) {
        final values = pair.split(',');

        if (values.length >= 2) {
          final lon = double.tryParse(values[0]);
          final lat = double.tryParse(values[1]);

          if (lat != null && lon != null) {
            boundaryPoints.add(LatLon(lat, lon));
          }
        }
      }

      if (boundaryPoints.isNotEmpty) {
        divisions.add(EEDivisionPolygon(divisionName, boundaryPoints));
      }
    }
  } catch (e) {
    print("EE Division KML Parser Error: $e");
  }

  return divisions;
}

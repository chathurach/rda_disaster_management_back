import 'package:rda_disaster_management/models/location_model.dart';
import 'package:rda_disaster_management/models/road_segment_model.dart';
import 'package:xml/xml.dart';

/// -------------------------
/// ROAD POLYGON KML PARSER
/// -------------------------
List<RoadSegment> loadRoadPolygonsFromKML(
    String kmlContent, String assignedClass) {
  final segments = <RoadSegment>[];

  try {
    final document = XmlDocument.parse(kmlContent);
    final placemarks = document.findAllElements('Placemark');

    for (final placemark in placemarks) {
      String roadName = '';
      String segmentId = '';
      String startLoc = '';
      String endLoc = '';

      // 1. Extract Schema Data (using <ExtendedData> and <Data> tags)
      final extendedData = placemark.findElements('ExtendedData').firstOrNull;
      if (extendedData != null) {
        final dataFields = extendedData.findAllElements('SimpleData');

        for (final data in dataFields) {
          final name = data.getAttribute('name');
          final value = data.innerText.trim();

          if (name == 'TL_Nm_Tran') {
            roadName = value;
          } else if (name == 'TL_Lb_Addi') {
            segmentId = value;
          } else if (name == 'Start') {
            startLoc = value;
          } else if (name == 'End') {
            endLoc = value;
          }
          // Note: 'Class' field will match assignedClass but we extract others
          // print(value);
        }
      }

      // Check if we have essential data
      if (roadName.isEmpty || segmentId.isEmpty) continue;

      // 2. Extract Coordinates
      final coordsNode = placemark
          .findAllElements('coordinates')
          .firstOrNull
          ?.innerText
          .trim();

      if (coordsNode == null || coordsNode.isEmpty) continue;

      final boundaryPoints = <LatLon>[];
      // Coordinates are typically Lon,Lat,Altitude triples separated by spaces
      final pairs = coordsNode.split(RegExp(r'\s+'));
      for (final pair in pairs) {
        final values = pair.split(',');
        if (values.length >= 2) {
          final lon = double.tryParse(values[0]);
          final lat = double.tryParse(values[1]);
          if (lat != null && lon != null) boundaryPoints.add(LatLon(lat, lon));
        }
      }

      // 3. Create the Road Segment Object
      if (boundaryPoints.isNotEmpty) {
        segments.add(RoadSegment(
          roadName: roadName,
          roadClass: assignedClass, // Use the class passed into the function
          segmentId: segmentId,
          startLocation: startLoc,
          endLocation: endLoc,
          boundary: boundaryPoints,
        ));
      }
    }
  } catch (e) {
    print('ERROR parsing Road KML for $assignedClass class: $e');
  }

  return segments;
}

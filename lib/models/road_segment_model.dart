import 'package:rda_disaster_management/models/location_model.dart';

/// Represents a road segment polygon parsed from KML.
class RoadSegment {
  // The coordinates

  RoadSegment({
    required this.roadName,
    required this.roadClass,
    required this.segmentId,
    required this.startLocation,
    required this.endLocation,
    required this.boundary,
  });
  final String roadName; // Corresponds to TL_Nm_Tran
  final String roadClass; // Corresponds to Class
  final String segmentId; // Corresponds to Link_ID
  final String startLocation; // Corresponds to Start
  final String endLocation; // Corresponds to End
  final List<LatLon> boundary;
}

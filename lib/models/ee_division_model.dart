import 'package:rda_disaster_management/models/location_model.dart';

///polygon for the EE division
class EEDivisionPolygon {
  /// ordered list of polygon vertices
  EEDivisionPolygon(this.name, this.boundary);

  ///name of the EE division
  final String name;

  ///polygon of the EE division
  final List<LatLon> boundary;
}

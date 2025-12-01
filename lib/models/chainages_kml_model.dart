import 'package:rda_disaster_management/models/location_model.dart';

///class for chainage model
class ChainagePoint {
  ///main function for chainage model
  ChainagePoint({
    required this.routeNo,
    required this.chainage,
    required this.location,
  });

  ///oute number
  final String routeNo;

  ///chainage in the fomat of int
  final int chainage;

  ///location with lat and long
  final LatLon location;
}

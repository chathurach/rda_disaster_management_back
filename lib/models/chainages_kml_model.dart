import 'package:rda_disaster_management/kmz_processor.dart';

class ChainagePoint {
  ChainagePoint({
    required this.routeNo,
    required this.chainage,
    required this.location,
  });
  final String routeNo;
  final int chainage;
  final LatLon location;
}

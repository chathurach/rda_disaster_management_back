/// A model to represent the final, augmented incident data structure
/// after chainage-to-LatLon processing.
class ProcessedIncidentData {
  ProcessedIncidentData({
    required this.serialNo,
    required this.routeNo,
    required this.roadName,
    required this.chainageFrom,
    required this.chainageTo,
    required this.latLongFrom,
    required this.latLongTo,
    required this.reason,
    required this.currentStatus,
  });
  final int serialNo;
  final String routeNo;
  final String roadName;
  final String chainageFrom;
  final String chainageTo;
  final String latLongFrom;
  final String latLongTo;
  final String reason;
  final String currentStatus;

  /// Converts the object to the Map format expected by the API consumer.
  Map<String, dynamic> toJson() {
    return {
      'S. No': serialNo,
      'Route No.': routeNo,
      'Road Name': roadName,
      'Chainage From': chainageFrom,
      'Chainage To': chainageTo,
      'LatLong From': latLongFrom,
      'LatLong To': latLongTo,
      'Reason for impassability': reason,
      'Current Status': currentStatus,
    };
  }
}

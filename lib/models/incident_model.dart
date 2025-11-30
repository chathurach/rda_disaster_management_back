/// Represents the structure of a single incident record from the Google Sheet
/// before any processing (Chainage-to-LatLon lookup) has occurred.
class IncidentData {
  /// Constructor to parse the raw JSON Map from the Google Sheet.
  IncidentData.fromJson(Map<String, dynamic> json)
      : serialNo = _parseInt(json['S. No']), // Use the helper function
        routeNo = json['Route No.'].toString(),
        roadName = json['Road Name'].toString(),
        chainageFrom = json['From'].toString(),
        chainageTo = json['To'].toString(),
        reason = json['Reason for impassability'].toString(),
        currentStatus = json['Current Status'].toString();
  final int serialNo;
  final String routeNo;
  final String roadName;
  final String chainageFrom;
  final String chainageTo;
  final String reason;
  final String currentStatus;
}

/// Helper function to safely parse a dynamic value into an integer,
/// defaulting to 0 if parsing fails or the value is null.
int _parseInt(dynamic value) {
  if (value == null) {
    return 0;
  }

  if (value is int) {
    return value;
  }

  // Safely attempt to parse string representation, defaulting to 0 on failure
  return int.tryParse(value.toString()) ?? 0;
}

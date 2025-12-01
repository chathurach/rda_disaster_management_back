///Public class for convering to lat long
class LatLon {
  ///main class for lat long
  LatLon(this.latitude, this.longitude);

  ///latitude
  final double latitude;

  ///logitude
  final double longitude;

  @override
  String toString() => '$latitude,$longitude';
}

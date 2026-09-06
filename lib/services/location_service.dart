import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  static Future<Position?> getCurrentPosition() async {
    try {
      final permission = await Permission.location.request();
      
      if (permission != PermissionStatus.granted) {
        return null;
      }
      
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      return position;
    } catch (e) {
      return null;
    }
  }

  static Future<String?> getCityName(double lat, double lon) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lon);
      if (placemarks.isNotEmpty) {
        return placemarks.first.locality ?? placemarks.first.subAdministrativeArea;
      }
    } catch (e) {
      // ignore
    }
    return null;
  }

  static Future<bool> requestPermission() async {
    final status = await Permission.location.request();
    return status == PermissionStatus.granted;
  }
}

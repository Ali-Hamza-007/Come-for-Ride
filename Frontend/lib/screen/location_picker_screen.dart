// --- LOCATION PICKER ---
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class LocationPickerScreen extends StatefulWidget {
  final LatLng? initialLocation;
  const LocationPickerScreen({super.key, this.initialLocation});
  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late LatLng _currentCenter;
  String _status = "Tap map to pick location";
  @override
  void initState() {
    super.initState();
    _currentCenter = widget.initialLocation ?? const LatLng(31.5204, 74.3587);
  }

  // When user taps on map, fetch address and return to previous screen
  Future<void> _fetchAndReturnAddress(LatLng latlng) async {
    setState(() {
      _status = "Fetching address...";
      _currentCenter = latlng; // Move marker to where user clicked
    });
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=${latlng.latitude}&lon=${latlng.longitude}',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'ComeForRideApp/1.0', 'Accept-Language': 'en'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        String full = data['display_name'] ?? "Unknown";
        List<String> parts = full.split(',');
        String shortName = parts.length > 1
            ? "${parts[0]}, ${parts[1]}"
            : parts[0];
        if (mounted)
          Navigator.pop(context, {'address': shortName, 'location': latlng});
      }
    } catch (e) {
      if (mounted)
        Navigator.pop(context, {
          'address': "Custom Location",
          'location': latlng,
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(_status, style: const TextStyle(fontSize: 14)),
      ),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: _currentCenter,
          initialZoom: 13,
          onTap: (pos, latlng) => _fetchAndReturnAddress(latlng),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.hamza.rideshare',
            additionalOptions: const {
              'User-Agent': 'HamzaRideShare/1.0 (com.hamza.rideshare)',
            },
          ),
        ],
      ),
    );
  }
}

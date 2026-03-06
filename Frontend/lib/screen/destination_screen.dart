// --- DESTINATION SCREEN ---
import 'dart:async';
import 'dart:convert';
import 'package:come_for_ride/screen/offer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class DestinationScreen extends StatefulWidget {
  final String userName;
  final LatLng initial_centre;
  final String pickUpAddress;
  final LatLng pickUpLocation;
  final Function(String, String) onRideConfirmed;
  final VoidCallback onCancelComplete;

  const DestinationScreen({
    super.key,
    required this.pickUpAddress,
    required this.onCancelComplete,
    required this.userName,
    required this.pickUpLocation,
    required this.onRideConfirmed,
    required this.initial_centre,
  });

  @override
  State<DestinationScreen> createState() => _DestinationScreenState();
}

class _DestinationScreenState extends State<DestinationScreen> {
  LatLng? _destLocation;
  String _destAddress = "Tap map or search destination";
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  Timer? _debounce;

  String? _currentCity;
  String? _countryCode;
  bool _isSearching = false;
  bool _blockSearch = false;

  @override
  void initState() {
    super.initState();
    _fetchLocalAreaDetails();
  }

  // This function fetches the current city and country code based on the initial center coordinates using OpenStreetMap's Nominatim API.
  Future<void> _fetchLocalAreaDetails() async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=${widget.initial_centre.latitude}&lon=${widget.initial_centre.longitude}',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'HamzaRideShare/1.0 (com.hamza.rideshare)'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _countryCode = data['address']['country_code'];
          _currentCity =
              data['address']['city'] ??
              data['address']['town'] ??
              data['address']['village'];
        });
      }
    } catch (_) {}
  }

  // This function is called whenever the search input changes. It implements a debounce mechanism to avoid making API calls on every keystroke. If the query is empty, it clears the search results and resets the searching state.
  void _onSearchChanged(String query) {
    if (_blockSearch) return;
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _searchPlaces(query);
    });
  }

  // This function performs the actual search for places using the OpenStreetMap Nominatim API. It constructs the query, optionally appending the current city for better accuracy, and makes a GET request to the API. The results are then stored in the state to be displayed in the UI.
  Future<void> _searchPlaces(String query) async {
    if (query.length < 3 || _blockSearch) return;
    setState(() => _isSearching = true);
    try {
      String apiQuery = query;
      if (_currentCity != null &&
          !query.toLowerCase().contains(_currentCity!.toLowerCase())) {
        apiQuery = "$query, $_currentCity";
      }

      final url =
          'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(apiQuery)}&limit=10&countrycodes=${_countryCode ?? ""}';

      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'HamzaRideShare/1.0 (com.hamza.rideshare)'},
      );

      if (response.statusCode == 200 && !_blockSearch) {
        setState(() {
          _searchResults = json.decode(response.body);
          _isSearching = false;
        });
      }
    } catch (e) {
      setState(() => _isSearching = false);
    }
  }

  // This function takes the selected coordinates and performs a reverse geocoding lookup to get the human-readable address. It updates the destination address in the state and also updates the search field with this address. A short delay is used to prevent immediate new searches while the address is being set.
  Future<void> _getDestAddress(LatLng coords) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=${coords.latitude}&lon=${coords.longitude}',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'HamzaRideShare/1.0 (com.hamza.rideshare)'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _blockSearch = true;
          String full = data['display_name'] ?? "Unknown";
          List<String> parts = full.split(',');
          _destAddress = parts.length > 1
              ? "${parts[0]}, ${parts[1]}"
              : parts[0];
          _searchController.text = _destAddress;
          _searchResults = [];
        });
        Future.delayed(
          const Duration(milliseconds: 800),
          () => _blockSearch = false,
        );
      }
    } catch (e) {
      setState(() => _destAddress = "Location Selected");
    }
  }

  @override
  Widget build(BuildContext context) {
    bool showResultsPanel =
        _searchController.text.isNotEmpty &&
        !_isSearching &&
        _searchResults.isNotEmpty;
    bool showNoResults =
        _searchController.text.length >= 3 &&
        !_isSearching &&
        _searchResults.isEmpty &&
        !_blockSearch;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text(
          "Set Destination",
          style: TextStyle(color: Colors.black),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  child: Column(
                    children: [
                      _buildField(
                        Icons.my_location,
                        Colors.blue,
                        widget.pickUpAddress,
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            icon: Icon(Icons.search, color: Colors.red),
                            hintText: "Enter destination name...",
                            border: InputBorder.none,
                          ),
                          onChanged: _onSearchChanged,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: widget.initial_centre,
                      initialZoom: 14,
                      onTap: (tapPos, latLng) {
                        setState(() {
                          _destLocation = latLng;
                          _destAddress = "Loading...";
                          _searchResults = [];
                        });
                        FocusScope.of(context).unfocus();
                        _getDestAddress(latLng);
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.hamza.ride_app_unique_99',
                      ),

                      if (_destLocation != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _destLocation!,
                              width: 40,
                              height: 40,
                              child: const Icon(
                                Icons.location_on,
                                color: Colors.black,
                                size: 40,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: ElevatedButton(
                    onPressed: () {
                      // --- CRUCIAL CHECK ADDED HERE ---
                      if (_destLocation == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "Please select a destination location first!",
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => OfferScreen(
                            onCancelComplete: widget.onCancelComplete,
                            userName: widget.userName,
                            pickup: widget.pickUpAddress,
                            pickupLoc: widget.pickUpLocation,
                            destination: _destAddress,
                            destLoc: _destLocation!,
                            onFinalConfirm: widget.onRideConfirmed,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 55),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: const Text(
                      "Confirm Destination",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),

            if (showResultsPanel || showNoResults)
              Positioned(
                top: 115,
                left: 20,
                right: 20,
                child: Material(
                  elevation: 5,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 250),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: showNoResults
                        ? const ListTile(
                            title: Text(
                              "No locations found",
                              style: TextStyle(fontSize: 14),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _searchResults.length,
                            itemBuilder: (context, i) {
                              final place = _searchResults[i];
                              return ListTile(
                                title: Text(
                                  place['display_name'],
                                  style: const TextStyle(fontSize: 13),
                                ),
                                onTap: () {
                                  setState(() {
                                    _blockSearch = true;
                                    _destLocation = LatLng(
                                      double.parse(place['lat']),
                                      double.parse(place['lon']),
                                    );
                                    _destAddress = place['display_name'].split(
                                      ',',
                                    )[0];
                                    _searchController.text = _destAddress;
                                    _searchResults = [];
                                  });
                                  _mapController.move(_destLocation!, 15);
                                  FocusScope.of(context).unfocus();
                                  Future.delayed(
                                    const Duration(milliseconds: 800),
                                    () => _blockSearch = false,
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // This helper function builds a styled container for displaying the pickup and destination addresses. It takes an icon, a color, and the text to display, and returns a widget with consistent styling.
  Widget _buildField(IconData icon, Color color, String text) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.grey[100],
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 15),
        Expanded(
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );
}

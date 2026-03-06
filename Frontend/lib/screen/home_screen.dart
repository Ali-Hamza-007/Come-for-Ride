import 'dart:convert';

import 'package:come_for_ride/screen/account_screen.dart';
import 'package:come_for_ride/screen/destination_screen.dart';
import 'package:come_for_ride/screen/dilevery_booking_screen.dart';
import 'package:come_for_ride/screen/history_screen.dart';
import 'package:come_for_ride/screen/ride_app.dart';
import 'package:come_for_ride/screen/services_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

String hostAddress = dotenv.env['API_URL']!;
String port = dotenv.env['PORT']!;

class HomeScreen extends StatefulWidget {
  final int userId;
  final String email;
  final String userName;
  const HomeScreen({
    super.key,
    required this.userId,
    this.userName = "Guest",
    this.email = "default@example.com",
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  LatLng _selectedLocation = const LatLng(31.5926, 74.3095);
  String _addressName = "Fetching address...";
  int _currentNavIndex = 0;
  final MapController _mapController = MapController(); // Add this line
  List<RideHistory> historyItems = [];

  List<RideHistory> get topThreeHistory =>
      historyItems.length > 3 ? historyItems.sublist(0, 3) : historyItems;

  @override
  void initState() {
    super.initState();
    _checkPermissionAndGetLocation();
    _fetchHistoryFromDb();
  }

  // To get permission from user for fetching location or Turn on the location

  Future<void> _checkPermissionAndGetLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _addressName = "Please turn on GPS");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _addressName = "Location permission denied");
        return;
      }
    }

    try {
      Position position =
          await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 8),
          ).catchError((_) async {
            // Fallback: If GPS is slow, get the last known location instantly
            return await Geolocator.getLastKnownPosition() ??
                await Geolocator.getCurrentPosition(
                  desiredAccuracy: LocationAccuracy.low,
                );
          });

      setState(() {
        _selectedLocation = LatLng(position.latitude, position.longitude);
      });
      _mapController.move(_selectedLocation, 13.0);
      _getAddressName(_selectedLocation);
    } catch (e) {
      setState(() => _addressName = "Signal weak. Tap map manually.");
    }
  }

  // Fetch history from DB and update UI (Called in initState and after adding a new ride)
  Future<void> _fetchHistoryFromDb() async {
    try {
      final response = await http.get(
        Uri.parse("http://$hostAddress:$port/api/history/${widget.userId}"),
      );
      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        setState(() {
          // We clear the old list and build a fresh one from the DB
          historyItems = data.map((item) {
            return RideHistory(
              id: item['id'],
              destination: item['destination_address'] ?? "Unknown",
              pickup: item['pickup_address'] ?? "Unknown",
            );
          }).toList();
        });
      }
    } catch (e) {
      print("Error updating UI: $e");
    }
  }

  // Add a new ride to history in DB and then refresh the UI. Returns the new ride's ID for potential future use (like deletion).
  Future<int?> _addRideToHistory(String pickup, String dest) async {
    try {
      final response = await http.post(
        Uri.parse("http://$hostAddress:$port/api/history"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": widget.userId,
          "pickup": pickup,
          "destination": dest,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _fetchHistoryFromDb(); // One clean refresh
        return data['id'];
      }
    } catch (e) {
      print("Add history error: $e");
    }
    return null;
  }

  // Clear all history from DB & also from UI
  Future<void> _clearAllHistory() async {
    if (historyItems.isEmpty) return; // Safety check

    final previousItems = List<RideHistory>.from(historyItems);
    setState(() => historyItems.clear());

    try {
      final response = await http.delete(
        Uri.parse("http://$hostAddress:$port/api/history/all/${widget.userId}"),
      );

      if (response.statusCode != 200) {
        // If server fails, restore the items and show error
        setState(() => historyItems = previousItems);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to clear history on server")),
          );
        }
      }
    } catch (e) {
      setState(() => historyItems = previousItems);
      print("Network error: $e");
    }
  }

  // To delete a single item of History
  Future<void> _deleteOneHistory(int index) async {
    // Safety check to prevent RangeError
    if (index < 0 || index >= historyItems.length) return;

    final rideId = historyItems[index].id;

    if (rideId != null) {
      try {
        final response = await http.delete(
          Uri.parse("http://$hostAddress:$port/api/history/$rideId"),
        );

        if (response.statusCode == 200) {
          // Perform local state update
          setState(() {
            // Re-check index inside setState to be safe
            if (index < historyItems.length) {
              historyItems.removeAt(index);
            }
          });
        } else {
          print("Failed to delete from server: ${response.body}");
        }
      } catch (e) {
        print("Error deleting history item: $e");
      }
    }
  }

  // Getting Longitude and Latitude and then Converting the both for a single address name to show on screen
  Future<void> _getAddressName(LatLng coords) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=${coords.latitude}&lon=${coords.longitude}',
      );

      // Physical devices MUST send a User-Agent header or Nominatim blocks the request
      final response = await http
          .get(
            url,
            headers: {
              'User-Agent': 'ComeForRideApp/1.0 (contact@yourdomain.com)',
              'Accept-Language': 'en',
            },
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          String fullAddress = data['display_name'] ?? "Unknown Location";
          List<String> parts = fullAddress.split(',');
          // Takes the first two parts of the address for a cleaner look
          _addressName = parts.length > 1
              ? "${parts[0].trim()}, ${parts[1].trim()}"
              : parts[0];
        });
      } else {
        setState(() => _addressName = "Tap map to set address");
      }
    } catch (e) {
      print("Geocoding Error: $e");
      setState(() => _addressName = "Location Selected (Offline)");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              _buildHeader(),
              const SizedBox(height: 25),
              const Text(
                "Your current location",
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              Text(
                _addressName,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _buildMapSection(),
              const SizedBox(height: 20),
              _buildSearchBar(),
              const SizedBox(height: 30),
              const Text(
                "Our Services",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),
              _buildServiceRow(),
              const SizedBox(height: 30),
              _buildHistoryHeader(context),
              const SizedBox(height: 15),
              if (historyItems.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      "No recent history",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: topThreeHistory.length,
                  itemBuilder: (context, index) {
                    return _buildHistoryItem(
                      topThreeHistory[index].destination,
                      topThreeHistory[index].pickup,
                    );
                  },
                ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // Will buid Map on Screens
  Widget _buildMapSection() => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: SizedBox(
      height: 180,
      width: double.infinity,
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _selectedLocation,
          initialZoom: 18.0,
          onTap: (tapPosition, latLng) {
            setState(() {
              _selectedLocation = latLng;
              _addressName = "Loading...";
            });
            _getAddressName(latLng);
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.hamza.rideshare',
            additionalOptions: const {
              'User-Agent': 'HamzaRideShare/1.0 (com.hamza.rideshare)',
            },
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: _selectedLocation,
                width: 80,
                height: 80,
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
  );
  // To build three Services small boxes on HomeScreen
  Widget _buildServiceRow() => Row(
    children: [
      Expanded(child: _buildServiceCard("Trip", Icons.directions_car, "Trip")),
      const SizedBox(width: 10),
      Expanded(
        child: _buildServiceCard("Delivery", Icons.local_shipping, "Package"),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _buildServiceCard("Air", Icons.airplanemode_active, "Air"),
      ),
    ],
  );
  // History Related Stuff and Operation on it
  Widget _buildHistoryHeader(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      const Text(
        "History",
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HistoryScreen(
              allHistory: historyItems,
              onClearAll: _clearAllHistory,
              onDeleteOne: _deleteOneHistory,
            ),
          ),
        ),
        child: Text(
          "See All",
          style: TextStyle(
            color: Colors.blue[700],
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    ],
  );
  // To show History in the form of List
  Widget _buildHistoryItem(String title, String subtitle) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.history),
    ),
    title: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
    ),
    subtitle: Text(subtitle, maxLines: 1, style: const TextStyle(fontSize: 12)),
    trailing: const Icon(Icons.chevron_right, size: 20),
  );
  // To build header to be displayed on HomeScreen Containing Name of User
  Widget _buildHeader() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Hi, ${widget.userName}!",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            Text(
              "How are you doing today?",
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
      ),
      const CircleAvatar(
        radius: 25,
        backgroundColor: Colors.amber,
        child: Icon(Icons.person, color: Colors.white),
      ),
    ],
  );
  // build Search Field on HomeScreen and also navigate to DestinationScreen when user taps on it

  Widget _buildSearchBar() => GestureDetector(
    onTap: () {
      if (_addressName == "Fetching address..." ||
          _addressName == "Loading...") {
        // Inform the user and block navigation
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Fetching your current location, please wait..."),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
        return; // Stop here
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DestinationScreen(
            onCancelComplete: _fetchHistoryFromDb,
            userName: widget.userName, // Pass userName to
            initial_centre: _selectedLocation,
            pickUpAddress: _addressName,
            pickUpLocation: _selectedLocation,
            onRideConfirmed: _addRideToHistory,
          ),
        ),
      );
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      height: 55,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(15),
      ),
      child: const Row(
        children: [
          Icon(Icons.search, color: Colors.black54),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "Where to go today?",
              style: TextStyle(color: Colors.black54),
            ),
          ),
        ],
      ),
    ),
  );
  // To build three Services small boxes on HomeScreen
  Widget _buildServiceCard(String title, IconData icon, String type) =>
      GestureDetector(
        onTap: () {
          if (type == "Trip") {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DestinationScreen(
                  onCancelComplete: _fetchHistoryFromDb,
                  userName: widget.userName, // Pass userName to
                  initial_centre: _selectedLocation,
                  pickUpAddress: _addressName,
                  pickUpLocation: _selectedLocation,
                  onRideConfirmed: _addRideToHistory,
                ),
              ),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DeliveryBookingScreen(
                  onCancelComplete: _fetchHistoryFromDb,
                  currentAddress: _addressName,
                  currentLocation: _selectedLocation,
                  serviceType: type,
                  onConfirm: _addRideToHistory,
                ),
              ),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            children: [
              Icon(icon, size: 32, color: Colors.black87),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
  // Bottom bar containing Home , Services and Profile Icons
  Widget _buildBottomNav() => BottomNavigationBar(
    currentIndex: _currentNavIndex,
    onTap: (index) {
      if (index == 1) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ServicesScreen(
              onCancelComplete: _fetchHistoryFromDb,
              userName: widget.userName,
              currentAddress: _addressName,
              currentLocation: _selectedLocation,
              onRideConfirmed: _addRideToHistory,
            ),
          ),
        ).then((_) {
          // When we come BACK from Account, reset index to Home (0)
          setState(() => _currentNavIndex = 0);
        });
      } else {
        setState(() => _currentNavIndex = index);
      }
      if (index == 2) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                AccountScreen(userName: widget.userName, email: widget.email),
          ),
        ).then((_) {
          // When we come BACK from Account, reset index to Home (0)
          setState(() => _currentNavIndex = 0);
        });
      }
    },
    backgroundColor: Colors.white,
    selectedItemColor: Colors.black,
    unselectedItemColor: Colors.grey,
    type: BottomNavigationBarType.fixed,
    items: const [
      BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
      BottomNavigationBarItem(
        icon: Icon(Icons.map_outlined),
        label: 'Services',
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.person_outline),
        label: 'Account',
      ),
    ],
  );
}

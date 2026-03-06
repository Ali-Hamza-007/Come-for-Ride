// --- SERVICES SCREEN ---
import 'package:come_for_ride/screen/destination_screen.dart';
import 'package:come_for_ride/screen/dilevery_booking_screen.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class ServicesScreen extends StatelessWidget {
  final String userName;
  final String currentAddress;
  final LatLng currentLocation;
  final Function(String, String) onRideConfirmed;
  final VoidCallback onCancelComplete;

  const ServicesScreen({
    super.key,
    required this.currentAddress,
    required this.userName,
    required this.currentLocation,
    required this.onCancelComplete,
    required this.onRideConfirmed,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Our Services",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildServiceTile(
            context,
            "City Trip",
            "Comfortable rides within the city",
            Icons.directions_car,
            Colors.blue,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DestinationScreen(
                  onCancelComplete: onCancelComplete,
                  userName: userName,
                  initial_centre: currentLocation,
                  pickUpAddress: currentAddress,
                  pickUpLocation: currentLocation,
                  onRideConfirmed: onRideConfirmed,
                ),
              ),
            ),
          ),
          _buildServiceTile(
            context,
            "Package Delivery",
            "Fast and secure item delivery",
            Icons.local_shipping,
            Colors.orange,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DeliveryBookingScreen(
                  onCancelComplete: onCancelComplete,
                  currentAddress: currentAddress,
                  currentLocation: currentLocation,
                  serviceType: "Package",
                  onConfirm: onRideConfirmed,
                ),
              ),
            ),
          ),
          _buildServiceTile(
            context,
            "Air Delivery",
            "Premium drone delivery",
            Icons.airplanemode_active,
            Colors.purple,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DeliveryBookingScreen(
                  onCancelComplete: onCancelComplete,
                  currentAddress: currentAddress,
                  currentLocation: currentLocation,
                  serviceType: "Air",
                  onConfirm: onRideConfirmed,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  //Building the service option tiles
  Widget _buildServiceTile(
    BuildContext context,
    String title,
    String desc,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        ],
      ),
    ),
  );
}

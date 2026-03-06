// --- DELIVERY BOOKING SCREEN ---
import 'package:come_for_ride/screen/location_picker_screen.dart';
import 'package:come_for_ride/screen/offer_screen.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class DeliveryBookingScreen extends StatefulWidget {
  final String currentAddress;
  final LatLng currentLocation;
  final String serviceType;
  final Function(String, String) onConfirm;
  final VoidCallback onCancelComplete;

  const DeliveryBookingScreen({
    super.key,
    required this.currentAddress,
    required this.currentLocation,
    required this.serviceType,
    required this.onCancelComplete,
    required this.onConfirm,
  });

  @override
  State<DeliveryBookingScreen> createState() => _DeliveryBookingScreenState();
}

class _DeliveryBookingScreenState extends State<DeliveryBookingScreen> {
  String _destAddress = "Select Drop-off Point";
  LatLng? _destLocation;
  final TextEditingController _itemController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text("${widget.serviceType} Delivery"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildInputFrame(
                    Icons.my_location,
                    "Pickup",
                    widget.currentAddress,
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LocationPickerScreen(
                            initialLocation: widget
                                .currentLocation, // Pass current location as initial center
                          ),
                        ),
                      );
                      if (result != null) {
                        setState(() {
                          _destAddress = result['address'];
                          _destLocation = result['location'];
                        });
                      }
                    },
                    child: _buildInputFrame(
                      Icons.location_on,
                      "Drop-off",
                      _destAddress,
                      isAction: true,
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _itemController,
                    decoration: InputDecoration(
                      hintText: "What are you sending?",
                      prefixIcon: const Icon(Icons.inventory_2_outlined),
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(20),
              child: ElevatedButton(
                onPressed: () {
                  if (_destLocation == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Please select a drop-off point!"),
                      ),
                    );
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => OfferScreen(
                        onCancelComplete: widget.onCancelComplete,
                        userName: '',
                        pickup: widget.currentAddress,
                        pickupLoc: widget.currentLocation,
                        destination: "[${widget.serviceType}] $_destAddress",
                        destLoc: _destLocation!,
                        onFinalConfirm: widget.onConfirm,
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
                  "Confirm & View Offers",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  // Helper method to build input frames for pickup and drop-off

  Widget _buildInputFrame(
    IconData icon,
    String label,
    String val, {
    bool isAction = false,
  }) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.grey[100],
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(
      children: [
        Icon(icon, color: isAction ? Colors.red : Colors.blue),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
              Text(
                val,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

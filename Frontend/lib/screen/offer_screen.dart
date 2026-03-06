import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

String hostAddress = dotenv.env['API_URL']!;
String port = dotenv.env['PORT']!;

class OfferScreen extends StatefulWidget {
  final VoidCallback onCancelComplete;
  final String pickup;
  final LatLng pickupLoc;
  final String destination;
  final LatLng destLoc;
  final int? savedUserId;
  final Function(String, String) onFinalConfirm;
  final String userName;

  const OfferScreen({
    super.key,
    required this.pickup,
    required this.userName,
    required this.pickupLoc,
    required this.onCancelComplete,
    required this.destination,
    required this.destLoc,
    this.savedUserId,
    required this.onFinalConfirm,
  });

  @override
  State<OfferScreen> createState() => _OfferScreenState();
}

class _OfferScreenState extends State<OfferScreen> {
  double _confirmedFare = 0.0;
  bool _isDriverArrived = false;
  late IO.Socket socket;
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  // --- STATE VARIABLES ---
  List<dynamic> dynamicOffers = [];
  double _currentFare = 0.0;
  double _originalFare = 0.0;
  bool _isSearching = true;
  bool _isBooked = false;
  String? _declineMessage;
  bool _isWaitingForDriver = false; // Track negotiation status
  int? _lastInsertedRideId;
  int _selectedIndex = -1;
  String _selectedDriver = "Searching...";
  String _selectedCar = "Standard";
  String? selectedDriverSocketId;

  late Stream<int> _countdownStream;

  @override
  void initState() {
    super.initState();
    _calculateInitialFare();
    _initSocket();
    _initCountdown();
  }

  // Helper to scroll chat to bottom when a new message arrives
  void _scrollToBottom() {
    if (_chatScrollController.hasClients) {
      _chatScrollController.animateTo(
        _chatScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // Initialize a countdown stream for driver arrival estimation
  void _initCountdown() {
    _countdownStream = Stream<int>.periodic(
      const Duration(minutes: 1),
      (count) => 6 - count,
    ).take(7);
  }

  // Show a dialog when the ride is finished
  void _showRideFinishedDialog(String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 10),
            const Text("Trip Completed"),
          ],
        ),
        content: Text(msg),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            child: const Text("OK", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Initialize Socket.IO connection and event handlers
  void _initSocket() {
    socket = IO.io(
      'http://$hostAddress:$port',
      IO.OptionBuilder().setTransports(['websocket']).setQuery({
        'userId': widget.savedUserId,
      }).build(),
    );

    socket.onConnect((_) {
      socket.emit('request_ride', {
        'userId': widget.savedUserId,
        'pickup': {
          'lat': widget.pickupLoc.latitude,
          'lng': widget.pickupLoc.longitude,
        },
        'pickupAddress': widget.pickup,
        'destination': widget.destination,
        'initialFare': _currentFare,
      });
    });
    socket.on('fare_declined', (data) {
      if (mounted) {
        setState(() {
          _isWaitingForDriver = false;
          _currentFare = _confirmedFare;
          _declineMessage =
              "Driver declined the Rs. ${_currentFare.toInt()} offer";
        });

        // Clear the message after 3 seconds to return to normal state
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _declineMessage = null;
            });
          }
        });
      }
    });
    socket.on('driver_arrived', (data) {
      if (mounted) {
        setState(() {
          _isDriverArrived = true; // This will trigger the button disabling
        });

        // Show the Dialog Box instead of SnackBar
        showDialog(
          context: context,
          barrierDismissible: false, // Force user to acknowledge
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 10),
                Text("Driver Arrived"),
              ],
            ),
            content: Text(
              data['message'] ??
                  "Your driver is outside! Please meet them at the pickup point.",
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(backgroundColor: Colors.black),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "OK",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    });
    socket.on('ride_finished', (data) {
      if (mounted) {
        _showRideFinishedDialog(data['message']);
      }
    });

    socket.on('receive_chat_message', (data) {
      if (mounted) {
        if (data['senderSocketId'] == selectedDriverSocketId) {
          setState(() {
            _messages.add({
              "sender": data['senderName'],
              "text": data['message'],
              "isMe": false,
            });
          });
        }
        Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
      }
    });

    socket.on('offer_received', (data) {
      if (mounted) {
        setState(() {
          // FIX 1: Prevent duplicate tiles by updating existing driver data
          int existingIndex = dynamicOffers.indexWhere(
            (offer) => offer['driverSocketId'] == data['driverSocketId'],
          );

          if (existingIndex != -1) {
            dynamicOffers[existingIndex] = data;
          } else {
            dynamicOffers.add(data);
          }

          _isSearching = false;
          // FIX 2: Reset waiting status once driver responds
          _isWaitingForDriver = false;
          _declineMessage = null;
          if (selectedDriverSocketId == data['driverSocketId']) {
            double receivedPrice =
                double.tryParse(data['price'].toString()) ?? _currentFare;

            // Update BOTH so the UI stays in sync with the driver's latest word
            _confirmedFare = receivedPrice;
            _currentFare = receivedPrice;
            _isWaitingForDriver = false;
            _declineMessage = null;
          }
          if (_selectedIndex == -1 && dynamicOffers.isNotEmpty) {
            _selectedIndex = 0;
            _selectedDriver = dynamicOffers[0]['driverName'] ?? "Driver";
            _selectedCar = dynamicOffers[0]['carType'] ?? "Standard";
            selectedDriverSocketId = dynamicOffers[0]['driverSocketId'];
            _currentFare =
                double.tryParse(dynamicOffers[0]['price'].toString()) ??
                _currentFare;
            _confirmedFare = _currentFare;
          }
        });
      }
    });
  }

  // Handle driver selection from the list of offers
  void _selectDriver(int index) {
    setState(() {
      _selectedIndex = index;
      var selectedOffer = dynamicOffers[index];
      _selectedDriver = selectedOffer['driverName'] ?? "Driver";
      _selectedCar = selectedOffer['carType'] ?? "Standard";
      selectedDriverSocketId = selectedOffer['driverSocketId'];
      double selectedPrice =
          double.tryParse(selectedOffer['price'].toString()) ?? _originalFare;
      // FIX: Set the fare to THIS specific driver's offered price
      _currentFare = selectedPrice;
      _confirmedFare = selectedPrice;

      _isWaitingForDriver = false;
      _declineMessage = null;
    });
  }

  // Calculate initial fare based on distance and set both current and original fare
  void _calculateInitialFare() {
    double distance =
        Geolocator.distanceBetween(
          widget.pickupLoc.latitude,
          widget.pickupLoc.longitude,
          widget.destLoc.latitude,
          widget.destLoc.longitude,
        ) /
        1000;
    double calculated = (distance * 50).roundToDouble();
    if (calculated < 100) calculated = 150;
    setState(() {
      _currentFare = calculated;
      _originalFare = calculated;
      _confirmedFare = calculated;
    });
  }

  // Helper for fare updates to reduce redundancy
  void _emitFareUpdate(double newFare) {
    if (selectedDriverSocketId == null) return;
    setState(() {
      _currentFare = newFare;
      _declineMessage = null;
      _isWaitingForDriver = true;
    });

    socket.emit('update_fare', {
      'driverSocketId': selectedDriverSocketId,
      'newFare': newFare,
      'passengerName': widget.userName,
      'pickup': widget.pickup,
      'destination': widget.destination,
    });
  }

  // Handle price decrease with a check against the economy floor
  void _handlePriceDecrease() {
    double economyFloor = _originalFare * 0.8;
    double proposed = _currentFare - 10;
    if (proposed >= economyFloor) {
      _emitFareUpdate(proposed);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Reached minimum Economy fare")),
      );
    }
  }

  // Handle sending chat messages to the driver
  void _sendMessage() {
    if (_messageController.text.isNotEmpty && selectedDriverSocketId != null) {
      final msg = _messageController.text;
      socket.emit('send_chat_message', {
        'receiverSocketId': selectedDriverSocketId,
        'message': msg,
        'senderName': widget.userName,
      });
      setState(() {
        _messages.add({"sender": "Me", "text": msg, "isMe": true});
      });
      _messageController.clear();
      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    }
  }

  // Placeholder for call functionality
  void _makePhoneCall() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("Facility of Call is coming soon!")));
  }

  @override
  void dispose() {
    socket.off('receive_chat_message');
    socket.off('offer_received');
    socket.disconnect();
    socket.dispose();
    _messageController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: widget.pickupLoc,
                initialZoom: 14.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.hamza.rideshare',
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [widget.pickupLoc, widget.destLoc],
                      color: Colors.black,
                      strokeWidth: 4.0,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: widget.pickupLoc,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.black,
                        size: 35,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              top: 50,
              left: 20,
              child: CircleAvatar(
                backgroundColor: Colors.white,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
                ),
                child: _isBooked ? _buildArrivalUI() : _buildSelectionUI(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // UI for offer selection, price negotiation, and booking confirmation
  Widget _buildSelectionUI() {
    String statusText = "Select an offer";
    Color statusColor = Colors.black;

    if (_declineMessage != null) {
      statusText = _declineMessage!;
      statusColor = Colors.red;
    } else if (_isWaitingForDriver) {
      statusText = "Driver is viewing your request...";
      statusColor = Colors.orange[800]!;
    } else if (_isSearching) {
      statusText = "Searching for nearby drivers...";
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 15),
        Text(
          statusText,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: statusColor,
          ),
        ),
        if (_isSearching || _isWaitingForDriver)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 10),
            child: LinearProgressIndicator(
              color: Colors.black,
              backgroundColor: Colors.white,
            ),
          ),
        SizedBox(
          height: 200,
          child: dynamicOffers.isEmpty
              ? const Center(child: Text("Waiting for driver bids..."))
              : ListView.builder(
                  itemCount: dynamicOffers.length,
                  itemBuilder: (context, index) {
                    final offer = dynamicOffers[index];
                    String arrivalDetails = "Nearby";
                    double? dLat = double.tryParse(offer['lat'].toString());
                    double? dLng = double.tryParse(offer['lng'].toString());

                    if (dLat != null && dLng != null && dLat != 0.0) {
                      double dist =
                          Geolocator.distanceBetween(
                            dLat,
                            dLng,
                            widget.pickupLoc.latitude,
                            widget.pickupLoc.longitude,
                          ) /
                          1000;
                      int minutes = ((dist / 20) * 60).round();
                      if (minutes < 1) minutes = 1;
                      arrivalDetails =
                          "${dist.toStringAsFixed(1)} km ($minutes min away)";
                    }

                    return _buildOfferTile(
                      index,
                      offer['carType'] ?? "Standard",
                      offer['driverName'] ?? "Driver",
                      "${offer['price']}",
                      arrivalDetails,
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _btn(
                    "- Rs. 10",
                    _isWaitingForDriver ? () {} : _handlePriceDecrease,
                    false,
                  ),
                  Text(
                    "Rs. ${_currentFare.toInt()}",
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  _btn(
                    "+ Rs. 10",
                    _isWaitingForDriver
                        ? () {}
                        : () => _emitFareUpdate(_currentFare + 10),
                    true,
                  ),
                ],
              ),
              const SizedBox(height: 15),
              ElevatedButton(
                onPressed: (_selectedIndex == -1 || _isWaitingForDriver)
                    ? null
                    : () async {
                        // FIX: Notify the backend that this driver is selected
                        // This triggers the 'you_are_selected' event on the Driver's side
                        socket.emit('passenger_confirmed_selection', {
                          'selectedDriverSocketId': selectedDriverSocketId,
                          'passengerName': widget.userName,
                          'pickup': widget.pickup,
                          'destination': widget.destination,
                        });

                        final id = await widget.onFinalConfirm(
                          widget.pickup,
                          widget.destination,
                        );

                        setState(() {
                          _lastInsertedRideId = id;
                          _isBooked =
                              true; // Switches UI to _buildArrivalUI (which has the chat)
                        });
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: (_selectedIndex == -1 || _isWaitingForDriver)
                      ? Colors.grey
                      : Colors.black,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "Confirm Booking",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // UI for driver arrival status, chat interface, and trip details during the ride
  Widget _buildArrivalUI() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StreamBuilder<int>(
                      stream: _countdownStream,
                      initialData: 6,
                      builder: (context, snapshot) {
                        int mins = (snapshot.data ?? 6) < 0
                            ? 0
                            : snapshot.data!;
                        return Text(
                          (_isDriverArrived || mins == 0)
                              ? "Driver has arrived!"
                              : "$mins mins till arrival",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                    Text(
                      "KVA924NB • Toyota Corolla",
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
                const Row(
                  children: [
                    Text(
                      "5.0",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Icon(Icons.star, color: Colors.amber, size: 20),
                  ],
                ),
              ],
            ),
            const Divider(height: 20),
            Text(
              _selectedDriver,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Container(
              height: 120,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _messages.isEmpty
                  ? const Center(
                      child: Text(
                        "No messages yet",
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    )
                  : ListView.builder(
                      controller: _chatScrollController,
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final m = _messages[index];
                        return Align(
                          alignment: m['isMe']
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: m['isMe']
                                  ? Colors.blue.withOpacity(0.1)
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              m['text'],
                              style: TextStyle(
                                color: m['isMe'] ? Colors.blue : Colors.black,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: "Message...",
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.send, color: Colors.blue),
                        onPressed: _sendMessage,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _makePhoneCall,
                  child: const CircleAvatar(
                    backgroundColor: Color(0xFFF2F2F2),
                    child: Icon(Icons.phone, color: Colors.black),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            _buildLocationRow(
              Icons.radio_button_off,
              Colors.blue,
              "Pickup",
              widget.pickup,
            ),
            const SizedBox(height: 10),
            _buildLocationRow(
              Icons.radio_button_off,
              Colors.green,
              "Destination",
              widget.destination,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isDriverArrived
                  ? null
                  : () {
                      _handleCancel(); // Your existing cancel function
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: _isDriverArrived ? Colors.grey : Colors.black,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                "Cancel Trip",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Handle trip cancellation, notify backend, delete history, and navigate back to home
  Future<void> _handleCancel() async {
    socket.emit('cancel_ride', {
      'driverSocketId': selectedDriverSocketId,
      'passengerName': widget.userName,
    });
    if (_lastInsertedRideId != null) {
      try {
        await http.delete(
          Uri.parse(
            "http://$hostAddress:$port/api/history/$_lastInsertedRideId",
          ),
        );
        widget.onCancelComplete();
      } catch (e) {
        debugPrint("Error deleting history: $e");
      }
    }
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // Build Offer Tiles for each driver offer in the list
  Widget _buildOfferTile(
    int index,
    String car,
    String driver,
    String price,
    String time,
  ) {
    bool isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => _selectDriver(index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isSelected ? Colors.black : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.directions_car, size: 30),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    car,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "$driver • $time",
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              "Rs. $price",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  // Helper widget to display pickup and destination details with icons
  Widget _buildLocationRow(
    IconData icon,
    Color color,
    String label,
    String val,
  ) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                val,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                label,
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  //  Build a styled button with the given label and callback
  Widget _btn(String label, VoidCallback onTap, bool isDark) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.grey[200],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Opacity(
        opacity: _isWaitingForDriver ? 0.4 : 1.0,
        child: Text(
          label,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    ),
  );
}

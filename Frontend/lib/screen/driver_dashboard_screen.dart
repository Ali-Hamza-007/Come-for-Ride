import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import 'package:come_for_ride/screen/auth_screen.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

String hostAddress = dotenv.env['API_URL']!;
String port = dotenv.env['PORT']!;

class DriverDashboard extends StatefulWidget {
  final int? userId;
  final String? userName;
  const DriverDashboard({super.key, this.userId, this.userName});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  double _lastKnownLat = 0.0;
  double _lastKnownLng = 0.0;
  bool _isConfirmedByPassenger = false;
  late IO.Socket socket;
  StreamSubscription<Position>? _positionStream;
  List<Map<String, dynamic>> _messages = [];
  String? _currentPassengerSocketId;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController =
      ScrollController(); // Added for chat scrolling

  bool _isRideAccepted = false;
  dynamic currentNegotiatingFare;

  @override
  void initState() {
    super.initState();
    _initDriverSocket();
  }

  // --- CORE FUNCTIONALITY METHODS ---

  void _notifyArrival() {
    socket.emit('driver_arrived', {
      'passengerSocketId': _currentPassengerSocketId,
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Arrival notification sent!")));
  }

  void _finishTrip() {
    socket.emit('ride_finished', {
      'passengerSocketId': _currentPassengerSocketId,
    });
    setState(() {
      _isRideAccepted = false;
      _isConfirmedByPassenger = false;
      _currentPassengerSocketId = null;
      _messages.clear();
    });
  }

  void _updateFareByDriver(Map data, double adjustment) {
    double currentAmount =
        double.tryParse(
          (currentNegotiatingFare ?? data['newFare'] ?? data['initialFare'])
              .toString(),
        ) ??
        0.0;
    double newAmount = currentAmount + adjustment;

    setState(() {
      currentNegotiatingFare = newAmount;
    });

    socket.emit('driver_update_fare', {
      'passengerSocketId': data['passengerSocketId'],
      'newFare': newAmount,
      'driverName': widget.userName,
      'carType': 'Toyota Corolla',
      'lat': _lastKnownLat,
      'lng': _lastKnownLng,
      'pickup': data['pickup'],
      'destination': data['destination'],
    });
  }

  void _initDriverSocket() {
    socket = IO.io(
      'http://$hostAddress:$port',
      IO.OptionBuilder().setTransports(['websocket']).setQuery({
        'userId': widget.userId,
      }).build(),
    );

    socket.onConnect((_) {
      debugPrint("Driver connected to socket: ${socket.id}");
      _startLocationStreaming();
    });

    // Clear previous listeners to avoid duplicate triggers
    socket.off('ride_request_received');
    socket.off('ride_request_closed');
    socket.off('ride_cancelled');
    socket.off('receive_chat_message');
    socket.off('fare_updated');
    socket.off('you_are_selected');

    //  Listen for new requests
    socket.on('ride_request_received', (data) {
      if (!_isRideAccepted && !_isConfirmedByPassenger) {
        _showRideRequestDialog(data);
      }
    });

    // Listen for when the request is closed
    socket.on('ride_request_closed', (data) {
      if (mounted) {
        if (data['selectedDriverSocketId'] != socket.id) {
          if (Navigator.canPop(context)) {
            Navigator.of(
              context,
              rootNavigator: true,
            ).popUntil((route) => route.isFirst);
          }
          setState(() {
            _isRideAccepted = false;
            _isConfirmedByPassenger = false;
            _currentPassengerSocketId = null;
            _messages.clear();
          });
        }
      }
    });

    // Passenger confirmed THIS driver
    socket.on('you_are_selected', (data) {
      debugPrint("YOU ARE SELECTED event received!");
      if (mounted) {
        // Close any open dialogs safely
        if (Navigator.of(context).canPop()) {
          Navigator.of(
            context,
            rootNavigator: true,
          ).popUntil((route) => route.isFirst);
        }

        setState(() {
          _isConfirmedByPassenger = true;
          _isRideAccepted = true;
          _currentPassengerSocketId = data['passengerSocketId'];
        });
      }
    });

    // Handle Incoming Messages (FIXED: Ensure state updates correctly)
    socket.on('receive_chat_message', (data) {
      debugPrint("Received message: ${data['message']}");
      if (mounted) {
        setState(() {
          _messages.add({
            "sender": data['senderName'] ?? "Passenger",
            "text": data['message'],
            "isMe": false,
          });
        });
        _scrollToBottom();
      }
    });

    // Handle Ride Cancellation
    socket.on('ride_cancelled', (data) {
      if (mounted) {
        setState(() {
          _currentPassengerSocketId = null;
          _messages.clear();
          _isRideAccepted = false;
          _isConfirmedByPassenger = false;
        });
        _showCancellationDialog(data['message']);
      }
    });

    //  Handle Fare Updates
    socket.on('fare_updated', (data) {
      if (mounted && !_isConfirmedByPassenger) {
        setState(() {
          currentNegotiatingFare = data['newFare'];
        });
        data['pickupAddress'] = data['pickupAddress'] ?? data['pickup'];
        _showNewOfferDialog(data);
      }
    });
  }

  // This method ensures that whenever a new message is added to the chat, the ListView scrolls down to show the latest message. It uses a post-frame callback to ensure that the scroll happens after the UI has updated with the new message.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // This method starts streaming the driver's location to the server at regular intervals, ensuring that the passenger can see the driver's real-time location on the map. It also handles permission requests for location access.
  void _startLocationStreaming() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen((Position position) {
          _lastKnownLat = position.latitude;
          _lastKnownLng = position.longitude;
          socket.emit('driver_location_update', {
            'driverId': widget.userId ?? 0,
            'name': widget.userName ?? "Driver",
            'lat': _lastKnownLat,
            'lng': _lastKnownLng,
          });
        });
  }

  // This method sends a chat message to the passenger. It checks if there is an active passenger connection and if the message input is not empty before emitting the message to the server. After sending, it updates the local chat history and scrolls to the bottom of the chat window.
  void _sendMessage() {
    if (_currentPassengerSocketId != null &&
        _messageController.text.isNotEmpty) {
      final text = _messageController.text;
      socket.emit('send_chat_message', {
        'receiverSocketId': _currentPassengerSocketId,
        'message': text,
        'senderName': widget.userName ?? "Driver",
      });

      setState(() {
        _messages.add({"sender": "Me", "text": text, "isMe": true});
      });
      _messageController.clear();
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(
          "Driver Dashboard",
          style: GoogleFonts.poppins(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _handleLogout(),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            color: Colors.black,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.circle,
                  color: _isConfirmedByPassenger
                      ? Colors.greenAccent
                      : Colors.orange,
                  size: 12,
                ),
                const SizedBox(width: 8),
                Text(
                  _isConfirmedByPassenger
                      ? "ON TRIP"
                      : (_isRideAccepted ? "WAITING FOR PASSENGER" : "ONLINE"),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.amber,
                    child: Icon(Icons.person, size: 50, color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Hello, ${widget.userName ?? 'Driver'}!",
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStatCard("Earnings", "Rs. 0"),
                      _buildStatCard("Trips", "0"),
                      _buildStatCard("Rating", "5.0 ★"),
                    ],
                  ),
                  const SizedBox(height: 30),
                  if (_isConfirmedByPassenger) ...[
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _notifyArrival,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                            ),
                            child: const Text(
                              "I have Arrived",
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _finishTrip,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                            child: const Text(
                              "Finish Trip",
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Live Chat",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildChatWindow(),
                  ] else ...[
                    const SizedBox(height: 50),
                    const Opacity(
                      opacity: 0.5,
                      child: Icon(Icons.radar, size: 100, color: Colors.black),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _isRideAccepted
                          ? "Waiting for passenger to pick you..."
                          : "Scanning for nearby requests...",
                      style: const TextStyle(
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // This method builds the chat window UI, which includes a scrollable list of messages and an input field for sending new messages
  Widget _buildChatWindow() {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(10),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                bool isMe = _messages[index]['isMe'] == true;
                return Align(
                  alignment: isMe
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.black : Colors.grey[200],
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      _messages[index]['text'],
                      style: TextStyle(
                        color: isMe ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: "Message...",
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blue),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // This method handles the logout process by clearing stored preferences, disconnecting the socket, and navigating back to the authentication screen

  void _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    socket.disconnect();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const AuthScreen()),
        (route) => false,
      );
    }
  }

  void _showCancellationDialog(String? msg) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Trip Cancelled"),
        content: Text(msg ?? "The passenger cancelled the request"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _acceptRide(dynamic data) {
    setState(() {
      _isRideAccepted = true;
      _isConfirmedByPassenger = false;
      _currentPassengerSocketId = data['passengerSocketId'];
    });

    socket.emit('send_offer', {
      'passengerSocketId': data['passengerSocketId'],
      'driverName': widget.userName ?? "Driver",
      'driverId': widget.userId,
      'price': data['newFare'] ?? data['initialFare'],
      'carType': 'Standard',
      'pickup': data['pickupAddress'] ?? data['pickup'],
      'destination': data['destination'],
    });

    // Safely close the dialog
    if (Navigator.of(context).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  // This method shows the initial ride request dialog with the ability for the driver to adjust the fare before accepting
  void _showRideRequestDialog(dynamic data) {
    // Local variable to track the negotiating fare within the dialog
    double localFare =
        double.tryParse((data['newFare'] ?? data['initialFare']).toString()) ??
        0.0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          // Allows the dialog to update internally
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("New Ride Request"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.person),
                    title: Text(data['passengerName'] ?? "Passenger"),
                    subtitle: Text(
                      "${data['pickupAddress'] ?? data['pickup'] ?? 'Unknown'} ➔ ${data['destination'] ?? 'Unknown'}",
                    ),
                  ),
                  const Divider(),
                  const Text(
                    "Adjust Fare Offer:",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.remove_circle,
                          color: Colors.red,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            if (localFare > 50) localFare -= 10;
                          });
                        },
                      ),
                      Text(
                        "Rs. ${localFare.toInt()}",
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.green),
                        onPressed: () {
                          setDialogState(() {
                            localFare += 10;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    socket.emit('decline_fare', {
                      'passengerSocketId': data['passengerSocketId'],
                    });
                    Navigator.pop(context);
                  },
                  child: const Text(
                    "Ignore",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                  ),
                  onPressed: () {
                    // Update the data object with the new fare before accepting
                    data['newFare'] = localFare;
                    data['pickup'] = data['pickupAddress'] ?? data['pickup'];
                    _acceptRide(data);

                    // Navigator.pop(context);
                  },
                  child: const Text(
                    "Accept & Send",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // This method can be called to refresh the offer dialog with new fare details when the passenger updates the fare
  void _showNewOfferDialog(dynamic data) {
    // If a dialog is already open, close it first to avoid stacking
    if (Navigator.canPop(context)) Navigator.pop(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildOfferUI(data, "Updated Fare Request"),
    );
  }

  // This method builds a small card widget to display stats like earnings, trips, and ratings
  Widget _buildStatCard(String label, String value) {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // This method builds the offer dialog UI, which can be reused for both new offers and fare updates
  Widget _buildOfferUI(dynamic data, String title) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.stars, color: Colors.amber, size: 50),
            Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.location_on, color: Colors.green),
              title: const Text("Pickup"),
              subtitle: Text(
                data['pickup'] ?? data['pickupAddress'] ?? "Unknown",
              ),
            ),
            ListTile(
              leading: const Icon(Icons.location_on, color: Colors.red),
              title: const Text("Destination"),
              subtitle: Text(data['destination'] ?? "Unknown"),
            ),
            Text(
              "Fare: Rs. ${data['newFare'] ?? data['initialFare']}",
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.blueAccent,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      socket.emit('decline_fare', {
                        'passengerSocketId':
                            data['passengerSocketId'], // Ensure you have the passenger's ID
                      });
                      Navigator.pop(context); // To close the request dialog
                    },
                    child: const Text("Ignore"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      data['pickup'] = data['pickup'] ?? data['pickupAddress'];
                      _acceptRide(data);
                    },
                    child: const Text("Accept"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    socket.dispose();
    super.dispose();
  }
}

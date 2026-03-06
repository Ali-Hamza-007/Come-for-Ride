import 'package:come_for_ride/screen/auth_screen.dart';
import 'package:come_for_ride/screen/driver_dashboard_screen.dart';
import 'package:come_for_ride/screen/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RideHistory {
  final int? id;
  final String destination;
  final String pickup;

  RideHistory({this.id, required this.destination, required this.pickup});
}

class RideApp extends StatelessWidget {
  final bool isLoggedIn;
  final int? savedUserId;
  final String? savedUserName;
  final String? savedEmail;
  final String? savedRole;

  const RideApp({
    super.key,
    required this.isLoggedIn,
    this.savedUserId,
    this.savedUserName,
    this.savedEmail,
    this.savedRole,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(textTheme: GoogleFonts.openSansTextTheme()),
      home: isLoggedIn
          ? (savedRole == 'driver'
                ? const DriverDashboard()
                : HomeScreen(
                    userId: savedUserId!,
                    userName: savedUserName!,
                    email: savedEmail!,
                  ))
          : const AuthScreen(),
    );
  }
}

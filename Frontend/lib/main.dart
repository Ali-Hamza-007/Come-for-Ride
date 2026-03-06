import 'package:come_for_ride/screen/ride_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- MAIN FUNCTION ---
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: "assets/.env");
  print(dotenv.env['API_URL']);
  final prefs = await SharedPreferences.getInstance();
  final bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

  runApp(
    RideApp(
      isLoggedIn: isLoggedIn,
      savedUserId: prefs.getInt('userId'),
      savedUserName: prefs.getString('userName'),
      savedEmail: prefs.getString('email'),
      savedRole: prefs.getString('role'),
    ),
  );
}

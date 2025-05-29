import 'package:flutter/material.dart';
import 'home_screen.dart'; // Make sure the HomeScreen is properly imported
import 'user_screen.dart'; // Import the UserScreen widget

void main() {
  runApp(BarricadeApp());
}

class BarricadeApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Barricade Alert',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.orange,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => HomeScreen(), // HomeScreen route
        '/user': (context) => UserScreen(), // UserScreen route
      },
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:vibration/vibration.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:capstone/home_screen.dart';

const String baseUrl = 'http://13.202.203.209:5001';

class UserScreen extends StatefulWidget {
  @override
  _UserScreenState createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen> {
  LocationData? _currentLocation;
  Location location = Location();
  MapController mapController = MapController();
  List<LatLng> _barricadePins = [];
  IO.Socket? socket;

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _hasAlertedRecently = false;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _getLocation();
    _initSocket();
  }

  void _initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _notificationsPlugin.initialize(initializationSettings);
  }

  void _initSocket() {
    socket = IO.io(baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });

    socket!.onConnect((_) {
      print('Socket connected');
    });

    socket!.on('new_barricade', (data) async {
      final double lat = data['latitude'];
      final double lng = data['longitude'];

      final newPin = LatLng(lat, lng);
      if (!_barricadePins.any((pin) => pin.latitude == lat && pin.longitude == lng)) {
        setState(() {
          _barricadePins.add(newPin);
        });

        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(duration: 300);
        }
      }
    });

    socket!.onDisconnect((_) => print('Socket disconnected'));
  }

  void _getLocation() async {
    bool serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) serviceEnabled = await location.requestService();

    PermissionStatus permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
    }

    if (!serviceEnabled || permissionGranted != PermissionStatus.granted) return;

    _currentLocation = await location.getLocation();
    setState(() {});
    await _fetchBarricades();

    location.onLocationChanged.listen((LocationData currentLocation) {
      _currentLocation = currentLocation;
      _checkProximityToBarricades();
    });
  }

  Future<void> _fetchBarricades() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/barricades'));
      if (response.statusCode == 200) {
        final List<dynamic> pins = jsonDecode(response.body);
        setState(() {
          _barricadePins = pins.map((pin) => LatLng(pin['latitude'], pin['longitude'])).toList();
        });
      }
    } catch (e) {
      print("Error fetching pins: $e");
    }
  }

  void _checkProximityToBarricades() async {
    if (_currentLocation == null) return;

    for (LatLng barricade in _barricadePins) {
      double distance = Distance().as(
        LengthUnit.Meter,
        LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
        barricade,
      );

      if (distance <= 100 && !_hasAlertedRecently) {
        _triggerAlert();
        break;
      }
    }
  }

  void _triggerAlert() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      'barricade_channel',
      'Barricade Alerts',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );

    const NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);

    await _notificationsPlugin.show(
      0,
      'Barricade Nearby!',
      'You are within 100 meters of a barricade. Drive cautiously.',
      platformChannelSpecifics,
    );

    await _audioPlayer.play(AssetSource('alert.mp3'));

    _hasAlertedRecently = true;
    Future.delayed(Duration(seconds: 30), () {
      _hasAlertedRecently = false;
    });
  }

  void _recenterMap() {
    if (_currentLocation != null) {
      mapController.move(
        LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
        13.0,
      );
    }
  }

  void _navigateToHomeScreen() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => HomeScreen()), // Navigate to HomeScreen
    );
  }

  @override
  void dispose() {
    socket?.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _currentLocation == null
          ? Center(child: CircularProgressIndicator())
          : Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              center: LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
              zoom: 13.0,
            ),
            children: [
              TileLayer(
                urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                subdomains: ['a', 'b', 'c'],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    width: 20.0,
                    height: 20.0,
                    point: LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  ..._barricadePins.map(
                        (latLng) => Marker(
                      width: 40.0,
                      height: 40.0,
                      point: latLng,
                      child: Icon(
                        Icons.warning,
                        color: Colors.red,
                        size: 35.0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton(
              onPressed: _recenterMap,
              heroTag: "recenter",
              mini: true,
              child: Icon(Icons.center_focus_strong),
            ),
          ),
          Positioned(
            bottom: 80,
            right: 20,
            child: FloatingActionButton(
              onPressed: _navigateToHomeScreen, // Navigate to HomeScreen
              heroTag: "home",
              mini: true,
              child: Icon(Icons.home),
            ),
          ),
        ],
      ),
    );
  }
}

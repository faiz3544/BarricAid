import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:vibration/vibration.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart' as perm;
import 'package:device_info_plus/device_info_plus.dart';
import 'detection_result_screen.dart';

const String baseUrl = 'http://13.202.203.209:5001';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  File? _image;
  final picker = ImagePicker();
  bool _isLoading = false;
  LocationData? _currentLocation;
  Location location = Location();
  MapController mapController = MapController();
  List<Map<String, dynamic>> _barricadePins = [];
  bool _isSharingLocation = false;
  String? _nickname;
  List<Map<String, dynamic>> _sharedUsers = [];// latLng + address
  IO.Socket? socket;

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _hasAlertedRecently = false;

  @override
  void initState() {
    super.initState();
    _requestNotificationPermission();
    _initNotifications();
    _getLocation();
    _initSocket();
  }

  void _requestNotificationPermission() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        final permissionStatus = await perm.Permission.notification.status;
        if (!permissionStatus.isGranted) {
          await perm.Permission.notification.request();
        }
      }
    }
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
      final String? address = data['address'];

      setState(() {
        _barricadePins.add({'latLng': LatLng(lat, lng), 'address': address});
      });

      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(duration: 300);
      }
    });
    

    socket!.onDisconnect((_) => print('Socket disconnected'));
  }

  Future<void> _getImage(ImageSource source) async {
    final pickedFile = await picker.pickImage(source: source);

    if (pickedFile != null && _currentLocation != null) {
      setState(() {
        _image = File(pickedFile.path);
        _isLoading = true;
      });

      final uri = Uri.parse('$baseUrl/barricades');
      final request = http.MultipartRequest('POST', uri)
        ..fields['latitude'] = _currentLocation!.latitude.toString()
        ..fields['longitude'] = _currentLocation!.longitude.toString()
        ..files.add(await http.MultipartFile.fromPath('image', pickedFile.path));

      try {
        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);

        setState(() => _isLoading = false);

        if (response.statusCode == 201) {
          final responseData = json.decode(response.body);
          bool barricadeDetected = false;

          if (responseData['detection'].isNotEmpty) {
            barricadeDetected = true;
            final double lat = _currentLocation!.latitude!;
            final double lng = _currentLocation!.longitude!;
            final String? address = responseData['address'];

            setState(() {
              _barricadePins.add({'latLng': LatLng(lat, lng), 'address': address});
            });
          }

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DetectionResultScreen(
                image: _image!,
                detected: barricadeDetected,
              ),
            ),
          );
        } else {
          print("Failed to upload image. Status: ${response.statusCode}");
        }
      } catch (e) {
        print("Error uploading image: $e");
        setState(() => _isLoading = false);
      }
    }
  }

  void _getLocation() async {
    bool serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) serviceEnabled = await location.requestService();

    PermissionStatus permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
    }

    if (!serviceEnabled || permissionGranted != PermissionStatus.granted) return;

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 29) {
        final bgStatus = await perm.Permission.locationAlways.status;
        if (!bgStatus.isGranted) {
          await perm.Permission.locationAlways.request();
        }
      }
    }

    _currentLocation = await location.getLocation();
    setState(() {});
    await _fetchBarricades();

    location.onLocationChanged.listen((LocationData currentLocation) {
      _currentLocation = currentLocation;
      _checkProximityToBarricades();
    });
  }

  void _checkProximityToBarricades() async {
    if (_currentLocation == null) return;

    for (var pin in _barricadePins) {
      LatLng barricade = pin['latLng'];
      double distance = Distance().as(
        LengthUnit.Meter,
        LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
        barricade,
      );

      if (distance <= 100 && !_hasAlertedRecently) {
        _triggerAlertWithAddress(pin['address']);
        break;
      }
    }
  }

  void _triggerAlertWithAddress(String? address) async {
    final String message = address != null
        ? 'Barricade nearby at $address. Drive cautiously.'
        : 'You are within 100 meters of a barricade. Drive cautiously.';

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'barricade_channel',
      'Barricade Alerts',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      sound: RawResourceAndroidNotificationSound('alert'),
      playSound: true,
    );

    const NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      0,
      'Barricade Nearby!',
      message,
      platformChannelSpecifics,
    );

    await _audioPlayer.play(AssetSource('alert.mp3'));

    _hasAlertedRecently = true;
    Future.delayed(Duration(seconds: 15), () {
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

  void _dropPin(LatLng latLng) async {
    setState(() {
      _barricadePins.add({'latLng': latLng, 'address': null});
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Dropped barricade pin at: ${latLng.latitude}, ${latLng.longitude}")),
    );

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/barricades'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'latitude': latLng.latitude,
          'longitude': latLng.longitude,
        }),
      );
      if (response.statusCode != 201) {
        print("Failed to save pin");
      }
    } catch (e) {
      print("Error saving pin: $e");
    }
  }

  Future<void> _fetchBarricades() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/barricades'));
      if (response.statusCode == 200) {
        final List<dynamic> pins = jsonDecode(response.body);
        setState(() {
          _barricadePins = pins.map<Map<String, dynamic>>((pin) {
            return {
              'latLng': LatLng(pin['latitude'], pin['longitude']),
              'address': pin['address'],
            };
          }).toList();
        });
      }
    } catch (e) {
      print("Error fetching pins: $e");
    }
  }

  void _clearBarricades() async {
    setState(() {
      _barricadePins.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("All barricades removed")),
    );

    try {
      final response = await http.delete(Uri.parse('$baseUrl/barricades'));
      if (response.statusCode != 200) {
        print("Failed to delete pins on server");
      }
    } catch (e) {
      print("Error deleting pins: $e");
    }
  }

  @override
  void dispose() {
    socket?.dispose();
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
              onTap: (tapPosition, latLng) => _dropPin(latLng),
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
                  ..._barricadePins.map((pin) => Marker(
                    width: 40.0,
                    height: 40.0,
                    point: pin['latLng'],
                    child: Icon(
                      Icons.warning,
                      color: Colors.red,
                      size: 35.0,
                    ),
                  )),
                ],
              ),
            ],
          ),
          if (_isLoading) Center(child: CircularProgressIndicator()),
          Positioned(
            bottom: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton(
                  onPressed: _recenterMap,
                  heroTag: "recenter",
                  mini: true,
                  child: Icon(Icons.center_focus_strong),
                ),
                SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () => _getImage(ImageSource.camera),
                  icon: Icon(Icons.camera_alt),
                  label: Text("Camera"),
                ),
                SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () => _getImage(ImageSource.gallery),
                  icon: Icon(Icons.photo_library),
                  label: Text("Gallery"),
                ),
                SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _clearBarricades,
                  icon: Icon(Icons.delete_forever),
                  label: Text("Clear Pins"),
                ),
                SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _fetchBarricades,
                  icon: Icon(Icons.refresh),
                  label: Text("Refresh Pins"),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 20,
            left: 20,
            child: FloatingActionButton(
              mini: true,
              heroTag: "toggleRole",
              onPressed: () {
                Navigator.pushReplacementNamed(context, '/user');
              },
              child: Icon(Icons.sync_alt),
            ),
          ),
        ],
      ),
    );
  }
}

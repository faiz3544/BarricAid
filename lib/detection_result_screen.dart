import 'dart:io';
import 'package:flutter/material.dart';

class DetectionResultScreen extends StatelessWidget {
  final File image;
  final bool detected;

  DetectionResultScreen({required this.image, required this.detected});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Detection Result'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Image.file(image),
            SizedBox(height: 20),
            Text(
              detected ? '🚧 Barricade Detected!' : '✅ No Barricade Found',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: detected ? Colors.red : Colors.green,
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Back"),
            ),
          ],
        ),
      ),
    );
  }
}

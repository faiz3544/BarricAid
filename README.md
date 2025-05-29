# 🚧 BarricAid – Real-Time Barricade Detection & Alert System

BarricAid is an intelligent Flutter-based mobile application that detects road barricades and alerts users in real time, ensuring safer and more informed driving experiences. It integrates on-device location tracking, machine learning–powered barricade detection, and real-time push alerts.

## 📱 Features

- Real-time GPS tracking
- Upload images to detect barricades using YOLOv11
- Live barricade map view
- Background location monitoring
- Notifications, vibration, and audio alerts when near barricades
- Developer view with image upload and pin management
- Admin API integration and local Flask server

## 🧠 Machine Learning Backend (YOLOv11)

The app uses a custom-trained **YOLOv11** object detection model to identify barricades from images uploaded via the app. Detected barricades are then geotagged and shared across devices.

## 🔧 Flask Backend & AWS Integration

A dedicated **Flask server** handles backend operations and is hosted on an **AWS EC2 instance**.

### Key Components:
- `Flask` for image handling and prediction routing
- `Flask-SocketIO` for broadcasting real-time barricade pin data
- `geopy` for reverse geocoding GPS coordinates into street names
- Hosted on **AWS EC2 (Ubuntu)** with port forwarding for public access

### Architecture:


### Flask Backend Files:
Folder: `/flask_backend/`
- `app.py`: Main Flask server logic
- `model.pt`: YOLOv11 barricade detection model
- `requirements.txt`: Backend dependencies
- `barricades.json`: Stores pin data

---

## 🖼️ Screenshots

<p align="center">
  <img src="assets/screenshots/BarricAid.jpg" width="200" />
  <img src="assets/screenshots/BarricAid2.jpg" width="200" />
  <img src="assets/screenshots/BarricAid3.jpg" width="200" />
</p>

### 🎞️ Demo
<p align="center">
  <img src="assets/screenshots/BarricadeGIF.gif" width="200" />
</p>

---

## 🧪 Tech Stack

- Flutter (Frontend)
- Flask (Backend)
- YOLOv11 (Barricade Detection)
- Socket.IO (Real-Time Communication)
- AWS EC2 (Deployment)
- SQLite (Local Storage)
- geopy (Reverse Geocoding)



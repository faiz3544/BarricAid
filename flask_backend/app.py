from flask import Flask, request, jsonify
from flask_cors import CORS
from flask_socketio import SocketIO
from ultralytics import YOLO
from PIL import Image
from geopy.geocoders import Nominatim
import io

app = Flask(__name__)
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*")

barricades = []

# ✅ Load YOLOv11 model
model = YOLO('best.pt')  # Update if needed

# ✅ Setup reverse geocoding
geolocator = Nominatim(user_agent="barricade-detector")

def get_address(latitude, longitude):
    try:
        location = geolocator.reverse((latitude, longitude), language='en')
        return location.address if location else "Unknown Address"
    except Exception as e:
        print("Geocoding error:", e)
        return "Unknown Address"

# ✅ Run inference
def run_inference(image_bytes):
    img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    results = model.predict(img, imgsz=640, conf=0.5)

    predictions = []
    for result in results:
        boxes = result.boxes
        for box in boxes:
            cls_id = int(box.cls[0])
            confidence = float(box.conf[0])
            xyxy = box.xyxy[0].tolist()
            predictions.append({
                'class_id': cls_id,
                'confidence': confidence,
                'bbox': xyxy
            })
    return predictions

# ✅ Routes
@app.route('/barricades', methods=['GET'])
def get_barricades():
    return jsonify(barricades)

@app.route('/barricades', methods=['POST'])
def add_barricade():
    try:
        # Handle both form-data and raw JSON
        if request.is_json:
            data = request.get_json()
            latitude = float(data.get('latitude'))
            longitude = float(data.get('longitude'))
            address = data.get('address') or get_address(latitude, longitude)
            detection_results = []  # No detection for manual pins
        else:
            data = request.form
            latitude = float(data.get('latitude'))
            longitude = float(data.get('longitude'))
            if 'image' not in request.files:
                return jsonify({'error': 'Image is required'}), 400
            image_bytes = request.files['image'].read()
            detection_results = run_inference(image_bytes)

            if not detection_results:
                return jsonify({
                    'message': 'No barricade detected. Pin not added.',
                    'detection': []
                }), 200

            address = get_address(latitude, longitude)

        new_pin = {
            'latitude': latitude,
            'longitude': longitude,
            'address': address,
            'detection': detection_results
        }

        barricades.append(new_pin)
        socketio.emit('new_barricade', new_pin)

        return jsonify({
            'message': 'Barricade added successfully',
            'address': address,
            'detection': detection_results
        }), 201

    except Exception as e:
        print("POST /barricades error:", e)
        return jsonify({'error': 'Invalid input or internal error'}), 500

@app.route('/barricades', methods=['DELETE'])
def delete_barricades():
    barricades.clear()
    socketio.emit('clear_barricades')
    return jsonify({'message': 'All barricades removed'}), 200

@app.route('/barricades/<float:latitude>/<float:longitude>', methods=['DELETE'])
def delete_barricade(latitude, longitude):
    global barricades
    barricades = [pin for pin in barricades if pin['latitude'] != latitude or pin['longitude'] != longitude]
    socketio.emit('remove_barricade', {'latitude': latitude, 'longitude': longitude})
    return jsonify({'message': 'Barricade removed'}), 200

@socketio.on('connect')
def handle_connect():
    print('Client connected')

@socketio.on('disconnect')
def handle_disconnect():
    print('Client disconnected')

if __name__ == '__main__':
    socketio.run(app, host='0.0.0.0', port=5001)
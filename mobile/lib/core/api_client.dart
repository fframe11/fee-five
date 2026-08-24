import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  final String baseUrl;
  String? _authToken;

  ApiClient({this.baseUrl = 'http://127.0.0.1:8000'});

  void setToken(String token) {
    _authToken = token;
  }

  Map<String, String> _headers() {
    final headers = {
      'Content-Type': 'application/json',
    };
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  // 1. Auth: User registration
  Future<Map<String, dynamic>> register(String email, String password) async {
    final url = Uri.parse('$baseUrl/api/auth/register');
    final response = await http.post(
      url,
      headers: _headers(),
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('การลงทะเบียนล้มเหลว: ${response.body}');
    }
  }

  // 2. Auth: Token retrieval / Login
  Future<String> login(String username, String password) async {
    final url = Uri.parse('$baseUrl/api/auth/token');
    
    // OAuth2 password flow expects x-www-form-urlencoded body mapping
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'username': username,
        'password': password,
      },
    );
    if (response.statusCode == 200) {
      final payload = jsonDecode(response.body);
      final token = payload['access_token'] as String;
      setToken(token);
      return token;
    } else {
      throw Exception('การเข้าสู่ระบบล้มเหลว: ${response.body}');
    }
  }

  // 3. User: Update Preferences
  Future<Map<String, dynamic>> updatePreferences(Map<String, dynamic> preferences) async {
    final url = Uri.parse('$baseUrl/api/users/me/preferences');
    final response = await http.put(
      url,
      headers: _headers(),
      body: jsonEncode(preferences),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('ไม่สามารถบันทึกการตั้งค่าความช่วยเหลือ: ${response.body}');
    }
  }

  // 4. Barriers: Proximity query filtering active obstructions
  Future<List<dynamic>> queryBarriers(double lat, double lng, double radiusMeters) async {
    final url = Uri.parse('$baseUrl/api/barriers/proximity?lat=$lat&lng=$lng&radius=$radiusMeters');
    final response = await http.get(
      url,
      headers: _headers(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    } else {
      throw Exception('ไม่สามารถดึงข้อมูลสิ่งกีดขวาง: ${response.body}');
    }
  }

  // 5. Emergency: SOS incident reporting
  Future<Map<String, dynamic>> reportEmergencySOS({
    required double lat,
    required double lng,
    required String sosType,
    required double confidence,
  }) async {
    final url = Uri.parse('$baseUrl/api/emergency/sos');
    final response = await http.post(
      url,
      headers: _headers(),
      body: jsonEncode({
        'latitude': lat,
        'longitude': lng,
        'sos_type': sosType,
        'confidence': confidence,
      }),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('ไม่สามารถส่งสัญญาณฉุกเฉิน: ${response.body}');
    }
  }

  // 6. Vision: Analyze image via Groq LPU Vision API proxy in backend
  Future<String> analyzeVisionImage(String base64Image, {String? prompt}) async {
    final url = Uri.parse('$baseUrl/api/v1/vision/analyze');
    final response = await http.post(
      url,
      headers: _headers(),
      body: jsonEncode({
        'image_base64': base64Image,
        'prompt': prompt,
      }),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['description'] ?? 'ไม่พบข้อมูลคำอธิบายภาพ';
    } else {
      throw Exception('ไม่สามารถประมวลผลรูปภาพ: ${response.body}');
    }
  }

  // 7. Transit: Calculate transit route using GTFS/GTFS-RT
  Future<Map<String, dynamic>> queryTransitRoute(double originLat, double originLng, double destLat, double destLng) async {
    final url = Uri.parse('$baseUrl/api/v1/navigation/transit-route');
    final response = await http.post(
      url,
      headers: _headers(),
      body: jsonEncode({
        'origin': {
          'latitude': originLat,
          'longitude': originLng,
        },
        'destination': {
          'latitude': destLat,
          'longitude': destLng,
        }
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('ไม่สามารถดึงข้อมูลเส้นทางขนส่ง: ${response.body}');
    }
  }

  // 8. Multi-Modal: Fetch journey recommendations compared by score
  Future<List<dynamic>> queryMultiModalRecommendations(double originLat, double originLng, double destLat, double destLng, String preference) async {
    final url = Uri.parse('$baseUrl/api/v1/navigation/multi-modal-recommendations');
    final response = await http.post(
      url,
      headers: _headers(),
      body: jsonEncode({
        'origin': {
          'latitude': originLat,
          'longitude': originLng,
        },
        'destination': {
          'latitude': destLat,
          'longitude': destLng,
        },
        'preference': preference
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    } else {
      throw Exception('ไม่สามารถดึงข้อมูลเปรียบเทียบการเดินทาง: ${response.body}');
    }
  }
  // 9. Emergency: Trigger alert from sign language gesture detection
  Future<Map<String, dynamic>> triggerEmergencyAlert(double lat, double lng, String message) async {
    return reportEmergencySOS(
      lat: lat,
      lng: lng,
      sosType: message,
      confidence: 0.95,
    );
  }
}

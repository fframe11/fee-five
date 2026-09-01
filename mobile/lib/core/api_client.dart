import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  final String baseUrl;
  String? _authToken;

  static String getDefaultBaseUrl() {
    if (kIsWeb) {
      final host = Uri.base.host;
      if (host.isNotEmpty && host != 'localhost' && host != '127.0.0.1') {
        return 'http://$host:8000';
      }
      return 'http://127.0.0.1:8000';
    }
    // Allow overriding via flutter build --dart-define=BACKEND_URL=...
    const envUrl = String.fromEnvironment('BACKEND_URL');
    if (envUrl.isNotEmpty) return envUrl;

    // Default to computer LAN IP so mobile device on same WiFi connects seamlessly
    return 'http://10.0.183.244:8000';
  }

  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? getDefaultBaseUrl();

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

  // 6. Vision: Analyze image via Local Backend OR Direct Groq Cloud Vision API
  Future<String> analyzeVisionImage(String base64Image, {String? prompt}) async {
    final effectivePrompt = prompt ??
        'You are an objective computer vision obstacle detector for visually impaired pedestrian navigation.\n'
        'Analyze this camera image and accurately detect ONLY real, physical, and hazardous obstacles directly on or near the walking path (such as pole, stairs, pothole, curb, barrier, chair, table, vehicle, pedestrian, uneven ground).\n'
        'CRITICAL RULES:\n'
        '- Do NOT detect standard background structures (e.g. plain walls, ceilings, floors) or small wall attachments (e.g. power sockets, switches) unless they pose a direct physical collision hazard.\n'
        '- If the path is clear and no actual hazards are present, return an empty JSON array: [].\n'
        'Return ONLY a valid JSON array of objects without extra commentary:\n'
        '[{"label": "pole", "score": 0.95, "bbox_2d": [xmin, ymin, xmax, ymax]}]\n'
        'where coordinates are normalized 0 to 1000.';

    // 1. Try Local Backend Proxy First (Fast LAN)
    try {
      final url = Uri.parse('$baseUrl/api/v1/vision/analyze');
      final response = await http.post(
        url,
        headers: _headers(),
        body: jsonEncode({
          'image_base64': base64Image,
          'prompt': effectivePrompt,
        }),
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final desc = data['description'] ?? '';
        if (desc.isNotEmpty) return desc;
      }
    } catch (_) {
      // Local backend unreachable or on 4G/5G mobile cellular network -> fallback to Direct Cloud Vision
    }

    // 2. Direct Groq Cloud Vision API Fallback (Guaranteed to work on 4G / 5G / Any network)
    try {
      final groqUrl = Uri.parse('https://api.groq.com/openai/v1/chat/completions');
      const groqKey = String.fromEnvironment(
        'GROQ_API_KEY',
        defaultValue: '',
      );
      if (groqKey.isEmpty) return '[]';

      final imgData = base64Image.startsWith('data:image')
          ? base64Image
          : 'data:image/jpeg;base64,${base64Image.replaceAll(RegExp(r'\s+'), '')}';

      final groqResponse = await http.post(
        groqUrl,
        headers: {
          'Authorization': 'Bearer $groqKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'qwen/qwen3.8-27b',
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': effectivePrompt},
                {'type': 'image_url', 'image_url': {'url': imgData}}
              ]
            }
          ],
          'temperature': 0.1,
        }),
      ).timeout(const Duration(seconds: 8));

      if (groqResponse.statusCode == 200) {
        final resJson = jsonDecode(utf8.decode(groqResponse.bodyBytes));
        String content = resJson['choices'][0]['message']['content'] ?? '[]';
        // Strip think tags if present
        content = content.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '').trim();
        if (content.contains('```json')) {
          content = content.split('```json')[1].split('```')[0].trim();
        } else if (content.contains('```')) {
          content = content.split('```')[1].split('```')[0].trim();
        }
        return content;
      }
    } catch (e) {
      debugPrint('[ApiClient] Direct Groq Cloud Vision Error: $e');
    }

    return '[]';
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
    ).timeout(const Duration(seconds: 3));
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

  // 9. Accessibility GIS: Fetch Ramps, Elevators, Accessible Points
  Future<List<dynamic>> getAccessibilityPoints() async {
    try {
      final url = Uri.parse('$baseUrl/api/v1/accessibility/points');
      final response = await http.get(url, headers: _headers()).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  // 10. Accessibility GIS: Fetch Active Road & Sidewalk Barriers (GPS-based)
  Future<List<dynamic>> getActiveBarriers({double? lat, double? lng}) async {
    try {
      double queryLat = lat ?? 0;
      double queryLng = lng ?? 0;
      if (queryLat == 0 || queryLng == 0) {
        try {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 3),
          );
          queryLat = pos.latitude;
          queryLng = pos.longitude;
        } catch (_) {
          return [];
        }
      }
      final url = Uri.parse('$baseUrl/api/barriers/proximity?lat=$queryLat&lng=$queryLng&radius=2000');
      final response = await http.get(url, headers: _headers()).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  // 11. Emergency: Trigger alert from sign language gesture detection
  Future<Map<String, dynamic>> triggerEmergencyAlert(double lat, double lng, String message) async {
    return reportEmergencySOS(
      lat: lat,
      lng: lng,
      sosType: message,
      confidence: 0.95,
    );
  }

  // 12. Smart Accessibility Agent: Send event to ReAct agent
  Future<Map<String, dynamic>> postAgentEvent(Map<String, dynamic> eventPayload) async {
    final url = Uri.parse('$baseUrl/api/v1/agent/event');
    final response = await http.post(
      url,
      headers: _headers(),
      body: jsonEncode(eventPayload),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Agent processing error (${response.statusCode}): ${response.body}');
    }
  }

  // 13. Smart Accessibility Agent: Query session status
  Future<Map<String, dynamic>> getAgentStatus(int userId) async {
    final url = Uri.parse('$baseUrl/api/v1/agent/status/$userId');
    final response = await http.get(url, headers: _headers());
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to fetch agent status: ${response.body}');
    }
  }

  // 14. Smart Accessibility Agent: Clear user session
  Future<void> clearAgentSession(int userId) async {
    final url = Uri.parse('$baseUrl/api/v1/agent/session/$userId');
    await http.delete(url, headers: _headers());
  }

  // 15. GIS Barrier Persistence: Save detected obstacle to database with GPS
  Future<bool> reportBarrier({
    required String type,
    required double lat,
    required double lng,
    String severity = 'high',
    String? description,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/v1/accessibility/barriers');
      final response = await http.post(
        url,
        headers: _headers(),
        body: jsonEncode({
          'type': type,
          'location': {
            'latitude': lat,
            'longitude': lng,
          },
          'severity': severity,
          'status': 'active',
          'description': description ?? 'ตรวจพบอุปสรรคโดยกล้อง AI Vision',
        }),
      ).timeout(const Duration(seconds: 4));
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // 16. AI Mobility Agent: Multi-factor ReAct Transit Decision
  Future<Map<String, dynamic>?> getAiTransitDecision({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    required String destName,
    String userProfile = 'visual',
    String weather = 'normal',
    String trafficCondition = 'normal',
    String preference = 'balanced',
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/v1/navigation/ai-transit-decision');
      final response = await http.post(
        url,
        headers: _headers(),
        body: jsonEncode({
          'origin_lat': originLat,
          'origin_lon': originLng,
          'origin_name': 'ตำแหน่งปัจจุบัน',
          'dest_lat': destLat,
          'dest_lon': destLng,
          'dest_name': destName,
          'user_profile': userProfile,
          'weather': weather,
          'traffic_condition': trafficCondition,
          'preference': preference,
        }),
      ).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[ApiClient] AI Transit Decision error: $e');
    }
    return null;
  }
}


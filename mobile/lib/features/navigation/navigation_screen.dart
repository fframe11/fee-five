import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../../core/accessibility_notifier.dart';
import '../../core/api_client.dart';
import '../../core/tts_helper.dart';
import '../../core/app_colors.dart';
import '../../core/services/background_navigation_service.dart';
import '../../core/services/risk_engine.dart';
import '../../core/services/vision_trigger.dart';
import '../../core/services/recovery_manager.dart';
import '../../core/services/battery_manager.dart';
import '../../core/services/place_search_service.dart';
import '../../core/services/osrm_routing_service.dart';
import '../../core/services/gis_data_service.dart';
import '../../core/services/haptic_service.dart';
import 'map_loader.dart';

class NavigationScreen extends ConsumerStatefulWidget {
  const NavigationScreen({super.key});

  @override
  ConsumerState<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends ConsumerState<NavigationScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  OsrmRouteResult? _activeOsrmRoute;
  double _mapZoom = 16.0;

  final TextEditingController _originController = TextEditingController(text: "ตำแหน่งปัจจุบันของคุณ");
  final TextEditingController _destController = TextEditingController();
  
  bool _isNavigating = false;
  bool _isCardCollapsed = false;
  bool _isLoading = false;
  bool _showRerouteAlert = false;
  int _selectedRouteIndex = 0; // 0 = Safe Route, 1 = Shortest Unsafe Route
  String _currentTravelMode = 'walk'; // 'walk' or 'transit'
  String _mapThemeStyle = 'guardian_cyber'; // 'guardian_cyber', 'minimal_slate', 'midnight_neon', 'traffic', 'satellite'
  bool _voiceOnlyMode = false;
  bool _isSimulationMode = false; // 🚶‍♂️ Walk Simulation Mode for indoor testing
  final Set<String> _announcedHazards = {};
  String? _lastHazardAlert;
  
  Timer? _navigationTimer;
  int _currentStepIndex = 0;
  int _remainingDistance = 150;
  String _liveInstruction = "กำลังจัดเตรียมระบบนำทาง...";
  IconData _liveDirectionIcon = Icons.navigation_rounded;
  
  bool _filterElevators = true;
  bool _filterRamps = true;
  bool _filterTactilePaths = true;
  bool _filterTrafficLights = true;
  bool _filterZebraCrossings = true;
  bool _filterTransit = true;
  bool _filterBus = true;
  bool _filterBarriers = true;

  List<dynamic> _gisPoints = [];
  List<dynamic> _gisBarriers = [];
  List<Map<String, dynamic>> _transitStations = [];
  List<Map<String, dynamic>> _busStops = [];

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  late AnimationController _routeController;
  late Animation<double> _routeAnimation;

  // ─── Risk State & GPS Confidence (ข้อ 5, 6, 10 ของอาจารย์) ───
  final RiskEngine _riskEngine = RiskEngine();
  final VisionTrigger _visionTrigger = VisionTrigger();
  RiskState _currentRiskState = RiskState.safe;
  CameraTriggerState _cameraTriggerState = CameraTriggerState.sleep;
  GpsFixQuality _gpsFixQuality = GpsFixQuality.highPrecision;
  double _dynamicSafetyMargin = 12.0;
  double _gpsAccuracy = 4.0;
  String _sensorFusionStatus = 'ดาวเทียมตรง (GNSS Lock)';

  // ─── Live Google Maps-like Autocomplete Search ───
  List<Map<String, dynamic>> _destSuggestions = [];
  bool _isSearchingDest = false;
  Timer? _destDebounceTimer;

  List<Map<String, dynamic>> _originSuggestions = [];
  bool _isSearchingOrigin = false;
  Timer? _originDebounceTimer;
  StreamSubscription<Position>? _liveGpsSubscription;

  double? _customOriginLat;
  double? _customOriginLng;
  double? _customDestLat;
  double? _customDestLng;

  // ─── AI ReAct Decision Agent State ───
  String _aiAgentThought = '';
  String _aiAgentSpeech = '';
  String _aiAgentShortReason = '';
  String _aiAgentModeTitle = '';
  int _aiSafetyScore = 85;
  int _aiWalkScore = 90;
  int _aiCostScore = 95;
  int _aiTimeScore = 80;

  @override
  void initState() {
    super.initState();
    final accState = ref.read(accessibilityProvider);
    if (accState.accessibilityMode == 'visual') {
      _voiceOnlyMode = true;
    }
    _detectAndSetCurrentLocation();
    _loadAccessibilityGISLayer();
    _checkRecoverySession();
    _checkBatteryOptimization();
    onMapDestinationSelected((stopName) {
      if (mounted) {
        setState(() {
          _destController.text = stopName;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เลือกปลายทาง: $stopName'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.blue[800],
          ),
        );
      }
    });
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.5).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _routeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    _routeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _routeController, curve: Curves.easeInOut),
    );
  }

  Future<void> _detectAndSetCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
        if (mounted) {
          setState(() {
            _originController.text = "ตำแหน่งปัจจุบัน (${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)})";
          });
          sendUserLocationMessage(
            latitude: position.latitude,
            longitude: position.longitude,
            label: "📍 ตำแหน่งจริงของคุณ",
          );
        }
      }
    } catch (_) {
      // Fallback silently
    }
  }

  void _onDestSearchChanged(String query) {
    _destDebounceTimer?.cancel();
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _destSuggestions = [];
        _isSearchingDest = false;
      });
      return;
    }

    setState(() {
      _isSearchingDest = true;
    });

    _destDebounceTimer = Timer(const Duration(milliseconds: 250), () async {
      double? uLat;
      double? uLon;
      try {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null) {
          uLat = pos.latitude;
          uLon = pos.longitude;
        }
      } catch (_) {}

      final results = await PlaceSearchService.searchPlaces(q, userLat: uLat, userLon: uLon);
      if (mounted) {
        setState(() {
          _destSuggestions = results.map((r) => r.toMap()).toList();
          _isSearchingDest = false;
        });
      }
    });
  }

  void _selectDestination(Map<String, dynamic> item) {
    setState(() {
      _destController.text = item['name'] ?? item['display_name'];
      _customDestLat = (item['lat'] as num).toDouble();
      _customDestLng = (item['lon'] as num).toDouble();
      _destSuggestions = [];
      _isSearchingDest = false;
    });
    FocusScope.of(context).unfocus();
    if (_customDestLat != null && _customDestLng != null) {
      try {
        _mapController.move(ll.LatLng(_customDestLat!, _customDestLng!), 16.0);
      } catch (_) {}
    }
  }

  void _onOriginSearchChanged(String query) {
    _originDebounceTimer?.cancel();
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _originSuggestions = [];
        _isSearchingOrigin = false;
      });
      return;
    }

    setState(() {
      _isSearchingOrigin = true;
    });

    _originDebounceTimer = Timer(const Duration(milliseconds: 250), () async {
      double? uLat;
      double? uLon;
      try {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null) {
          uLat = pos.latitude;
          uLon = pos.longitude;
        }
      } catch (_) {}

      final results = await PlaceSearchService.searchPlaces(q, userLat: uLat, userLon: uLon);
      if (mounted) {
        setState(() {
          _originSuggestions = results.map((r) => r.toMap()).toList();
          _isSearchingOrigin = false;
        });
      }
    });
  }

  void _selectOrigin(Map<String, dynamic> item) {
    setState(() {
      _originController.text = item['name'] ?? item['display_name'];
      _customOriginLat = (item['lat'] as num).toDouble();
      _customOriginLng = (item['lon'] as num).toDouble();
      _originSuggestions = [];
      _isSearchingOrigin = false;
    });
    FocusScope.of(context).unfocus();
    if (_customOriginLat != null && _customOriginLng != null) {
      try {
        _mapController.move(ll.LatLng(_customOriginLat!, _customOriginLng!), 16.0);
      } catch (_) {}
    }
  }

  Future<void> _loadAccessibilityGISLayer() async {
    // 1. Instantly load comprehensive Master GIS dataset (BTS/MRT, Bus, Elevators, Ramps, Barriers)
    setState(() {
      _gisPoints = List.from(GisDataService.realAccessibilityPoints);
      _gisBarriers = List.from(GisDataService.realBarriers);
      _transitStations = List.from(GisDataService.realTransitStations);
      _busStops = List.from(GisDataService.realBusStops);
    });

    // 2. Fetch live updates from Backend API if available
    try {
      final points = await ApiClient().getAccessibilityPoints();
      final barriers = await ApiClient().getActiveBarriers();
      if (mounted && points.isNotEmpty) {
        setState(() {
          final existingIds = _gisPoints.map((p) => p['id']?.toString() ?? '').toSet();
          for (final pt in points) {
            final id = pt['id']?.toString() ?? '';
            if (id.isEmpty || !existingIds.contains(id)) {
              _gisPoints.add(pt);
            }
          }
        });
      }
      if (mounted && barriers.isNotEmpty) {
        setState(() {
          final existingBarrierIds = _gisBarriers.map((b) => b['id']?.toString() ?? '').toSet();
          for (final bar in barriers) {
            final id = bar['id']?.toString() ?? '';
            if (id.isEmpty || !existingBarrierIds.contains(id)) {
              _gisBarriers.add(bar);
            }
          }
        });
      }
    } catch (_) {}
  }

  /// ─── Recovery Manager: Check for interrupted session (ข้อ 11) ───
  Future<void> _checkRecoverySession() async {
    if (kIsWeb) return;
    try {
      final recovery = RecoveryManager();
      final hasSession = await recovery.hasActiveSession();
      if (hasSession && mounted) {
        final session = await recovery.restoreState();
        if (session != null && mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.restore, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('กลับมานำทางต่อ?'),
                ],
              ),
              content: Text(
                'พบการนำทางที่ถูกขัดจังหวะ\nปลายทาง: ${session.destinationName}\nความก้าวหน้า: ${(session.progressAlongRoute * 100).toStringAsFixed(0)}%',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    recovery.clearState();
                    Navigator.pop(ctx);
                  },
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _destController.text = session.destinationName;
                    });
                    _startNavigation();
                  },
                  child: const Text('นำทางต่อ'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[Nav] Recovery check error: $e');
    }
  }

  /// ─── Battery Manager: Check optimization status (ข้อ 12) ───
  Future<void> _checkBatteryOptimization() async {
    if (kIsWeb) return;
    try {
      final battery = BatteryManager();
      final status = await battery.checkBatteryOptimization();
      final shouldWarn = battery.shouldShowWarning(status);
      if (shouldWarn && mounted) {
        final message = battery.getWarningMessage(status);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.battery_alert, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
              ],
            ),
            duration: const Duration(seconds: 8),
            backgroundColor: Colors.orange[900],
            action: SnackBarAction(
              label: 'ตั้งค่า',
              textColor: Colors.white,
              onPressed: () {
                battery.requestDisableBatteryOptimization();
              },
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('[Nav] Battery check error: $e');
    }
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _liveGpsSubscription?.cancel();
    _riskEngine.dispose();
    _visionTrigger.dispose();
    BackgroundNavigationService.stopNavigation();
    _originController.dispose();
    _destController.dispose();
    _pulseController.dispose();
    _routeController.dispose();
    super.dispose();
  }

  void _drawSelectedRoute() {
    const isWheelchair = false;
    
    String originNode = 'paragon_plaza';
    if (_originController.text.contains('พารากอน') || _originController.text.contains('Paragon')) {
      if (_originController.text.contains('เหนือ')) {
        originNode = 'paragon_north';
      } else {
        originNode = 'paragon_plaza';
      }
    } else if (_originController.text.contains('เซ็นเตอร์') || _originController.text.contains('Center')) {
      originNode = 'siam_center_west';
    }
    
    String destNode = 'bts_siam_center';
    if (_destController.text.contains('BTS') || _destController.text.contains('บีทีเอส') || _destController.text.contains('สยาม')) {
      if (_destController.text.contains('ทางออก 3') || _destController.text.contains('Exit 3')) {
        destNode = 'bts_siam_exit3';
      } else {
        destNode = 'bts_siam_center';
      }
    } else if (_destController.text.contains('เซ็นทรัล') || _destController.text.contains('Central')) {
      destNode = 'centralworld';
    } else if (_destController.text.contains('วัดปทุม')) {
      destNode = 'wat_pathum';
    }

    if (_selectedRouteIndex == 0) {
      // Safe route (Best Way)
      sendDrawRouteMessage(
        startNode: originNode,
        endNode: destNode == 'bts_siam_center' ? 'bts_siam_exit3' : destNode,
        wheelchairMode: isWheelchair,
        avoidBrokenElevator: true,
      );
    } else {
      // Shortest route (with obstacles)
      sendDrawRouteMessage(
        startNode: originNode,
        endNode: destNode,
        wheelchairMode: isWheelchair,
        avoidBrokenElevator: false,
      );
    }
  }

  Future<void> _startNavigation() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Try to get actual GPS position for route, with short timeout
      double originLat = 14.8818;  // มทส. default
      double originLng = 102.0245;
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 3),
        );
        originLat = pos.latitude;
        originLng = pos.longitude;
      } catch (_) {}
      
      // Query backend route with timeout — don't block if it fails
      await ApiClient().queryTransitRoute(
        originLat, originLng,
        originLat + 0.002, originLng + 0.003,
      ).timeout(const Duration(seconds: 3));
    } catch (_) {
      // Fallback silently — navigation UI still works with mock data
    }
    
    if (!mounted) return;
    
    setState(() {
      _isLoading = false;
      _isNavigating = true;
      _selectedRouteIndex = 0; // Default to safe route (Best Way)
    });
    
    _drawSelectedRoute();
    _routeController.forward(from: 0.0);
    _startLiveNavigationCountdown();
  }

  void _triggerRerouting() {
    setState(() {
      _showRerouteAlert = false;
      _selectedRouteIndex = 0;
    });

    _drawSelectedRoute();
    _startLiveNavigationCountdown();
    _routeController.forward(from: 0.0);
  }

  void _startLiveNavigationCountdown() async {
    _navigationTimer?.cancel();
    _currentStepIndex = 0;
    _announcedHazards.clear();
    _lastHazardAlert = null;
    
    final acc = ref.read(accessibilityProvider);

    // ═══ 1. Get REAL current GPS position or custom origin ═══
    double originLat = 0, originLng = 0;
    if (_customOriginLat != null && _customOriginLng != null && _customOriginLat != 0.0) {
      originLat = _customOriginLat!;
      originLng = _customOriginLng!;
    } else {
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
        originLat = pos.latitude;
        originLng = pos.longitude;
      } catch (_) {
        // Default to SUT user location if GPS is unavailable
        originLat = 14.8818;
        originLng = 102.0245;
      }
    }

    // ═══ 2. Resolve Destination Coordinates ═══
    double destLat = 0, destLng = 0;
    final destName = _destController.text.trim();
    if (destName.isEmpty) {
      if (mounted) {
        setState(() {
          _liveInstruction = "กรุณาระบุหรือเลือกสถานที่ปลายทาง";
        });
      }
      return;
    }

    if (_customDestLat != null && _customDestLng != null && _customDestLat != 0.0) {
      destLat = _customDestLat!;
      destLng = _customDestLng!;
    } else {
      // Search via PlaceSearchService (Campus database + online)
      final searchResults = await PlaceSearchService.searchPlaces(destName, userLat: originLat, userLon: originLng);
      if (searchResults.isNotEmpty) {
        destLat = searchResults.first.lat;
        destLng = searchResults.first.lon;
      }
    }

    if (destLat == 0 && destLng == 0) {
      if (mounted) {
        setState(() {
          _liveInstruction = "ไม่พบตำแหน่ง \"$destName\" กรุณาเลือกจากรายการค้นหา";
        });
      }
      return;
    }

    // ═══ 3. Query Real OSRM Route (Turn-by-turn road steps) ═══
    OsrmRouteResult? osrmRoute;
    try {
      osrmRoute = await OsrmRoutingService.getWalkingRoute(
        originLat: originLat,
        originLon: originLng,
        destLat: destLat,
        destLon: destLng,
      );
    } catch (_) {}

    setState(() {
      _activeOsrmRoute = osrmRoute;
    });
    try {
      _mapController.move(ll.LatLng(originLat, originLng), 16.5);
    } catch (_) {}

    final double straightDist = Geolocator.distanceBetween(originLat, originLng, destLat, destLng);
    
    // Default initial travel mode
    String recommendedMode = straightDist <= 1500 ? 'walk' : (straightDist <= 15000 ? 'transit' : 'ride_hail');

    if (osrmRoute != null && osrmRoute.steps.isNotEmpty) {
      _remainingDistance = osrmRoute.totalDistanceMeters.round();
      final firstStep = osrmRoute.steps.first;
      _liveInstruction = firstStep.instruction;
      _liveDirectionIcon = _getManeuverIcon(firstStep.maneuverModifier);
    } else {
      _remainingDistance = straightDist.round();
      final distText = _remainingDistance > 1000 ? '${(_remainingDistance / 1000).toStringAsFixed(1)} กม.' : '$_remainingDistance ม.';
      _liveInstruction = "มุ่งหน้าไปยัง $destName (ระยะทาง $distText)";
      _liveDirectionIcon = Icons.arrow_upward_rounded;
    }

    setState(() {
      _currentTravelMode = recommendedMode;
    });

    // Start background location service with real destination metadata
    BackgroundNavigationService.startNavigation(
      destination: destName,
      destLat: destLat,
      destLng: destLng,
      totalDistanceMeters: _remainingDistance.toDouble(),
    );

    // ═══ Query AI ReAct Mobility Agent for Multi-Factor Decision ═══
    ApiClient().getAiTransitDecision(
      originLat: originLat,
      originLng: originLng,
      destLat: destLat,
      destLng: destLng,
      destName: destName,
      userProfile: acc.accessibilityMode,
      weather: 'normal',
    ).then((aiDecision) {
      if (aiDecision != null && mounted) {
        final mode = aiDecision['recommended_mode'] as String? ?? recommendedMode;
        setState(() {
          _currentTravelMode = mode;
          _aiAgentThought = aiDecision['thought_chain'] ?? '';
          _aiAgentSpeech = aiDecision['user_speech_th'] ?? '';
          _aiAgentShortReason = aiDecision['short_reason_th'] ?? '';
          _aiAgentModeTitle = aiDecision['recommended_mode_title'] ?? '';
          _aiSafetyScore = (aiDecision['safety_score'] as num?)?.toInt() ?? 85;
          _aiWalkScore = (aiDecision['accessibility_score'] as num?)?.toInt() ?? 90;
          _aiCostScore = (aiDecision['cost_score'] as num?)?.toInt() ?? 95;
          _aiTimeScore = (aiDecision['time_score'] as num?)?.toInt() ?? 80;
        });

        if (_aiAgentSpeech.isNotEmpty) {
          announceSpeech(_aiAgentSpeech, acc.voiceEnabled);
        }
      } else {
        announceSpeech(_getDecisionDetailedSpeech(_currentTravelMode), acc.voiceEnabled);
      }
    }).catchError((_) {
      announceSpeech(_getDecisionDetailedSpeech(_currentTravelMode), acc.voiceEnabled);
    });

    // ═══ 4. Navigation Loop: Walk Simulation Mode vs Real Live GPS ═══
    if (_isSimulationMode) {
      _runSimulationWalk(osrmRoute, originLat, originLng, destLat, destLng, destName, acc);
    } else {
      int stepIdx = (osrmRoute != null && osrmRoute.steps.length > 1) ? 1 : 0;
      _liveGpsSubscription?.cancel();
      _liveGpsSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3, // slightly higher to reduce micro-jitters
        ),
      ).listen((Position pos) {
        if (!mounted || !_isNavigating) return;

        // ป้องกัน GPS ผีหลอก (Jitter Filter)
        if (pos.accuracy > 25.0) return; // ข้ามจุดที่ความแม่นยำต่ำ
        if (pos.speed < 0.2) return; // ข้ามจุดที่ยืนนิ่ง (ความเร็วต่ำกว่า 0.2 m/s)

        final currentLat = pos.latitude;
        final currentLng = pos.longitude;
        final newDist = Geolocator.distanceBetween(currentLat, currentLng, destLat, destLng).round();

        // Proactive Hazard & Crosswalk Spoken Alerts (แจ้งเตือนล่วงหน้า 15-25 เมตร)
        _checkProactiveHazardAlerts(currentLat, currentLng, acc, accuracy: pos.accuracy, speed: pos.speed.clamp(0.0, 3.0));

        setState(() {
          _remainingDistance = newDist;
          _gpsAccuracy = pos.accuracy;
          final updatedDistText = _remainingDistance > 1000
              ? '${(_remainingDistance / 1000).toStringAsFixed(1)} กม.'
              : '$_remainingDistance ม.';

          if (_remainingDistance <= 15) {
            _liveInstruction = "ถึง $destName เรียบร้อยแล้ว";
            _liveDirectionIcon = Icons.check_circle_rounded;
            HapticService().destinationReached();
            announceSpeech("ถึง $destName เรียบร้อยแล้วค่ะ", acc.voiceEnabled);
            _liveGpsSubscription?.cancel();
          } else if (osrmRoute != null && osrmRoute.steps.isNotEmpty) {
            if (stepIdx < osrmRoute.steps.length) {
              final step = osrmRoute.steps[stepIdx];
              final stepDist = Geolocator.distanceBetween(currentLat, currentLng, step.stepLat, step.stepLon);
              if (stepDist < 20 && stepIdx < osrmRoute.steps.length - 1) {
                stepIdx++;
                final nextStep = osrmRoute.steps[stepIdx];
                _liveInstruction = nextStep.instruction;
                _liveDirectionIcon = _getManeuverIcon(nextStep.maneuverModifier);
                HapticService().turnGuidance();
                announceSpeech(nextStep.instruction, acc.voiceEnabled);
              } else {
                _liveInstruction = "${step.instruction} (เหลืออีก $updatedDistText)";
              }
            }
          } else {
            _liveInstruction = "กำลังนำทางไป $destName เหลืออีก $updatedDistText";
          }
        });
      });
    }
  }

  /// 🚶‍♂️ Walk Simulation Mode (Demo/Indoor Testing)
  /// จำลองการก้าวเดินตามถนนจริงทีละ 8–10 เมตร พร้อมแจ้งเตือนเลี้ยวล่วงหน้า 20 เมตร สั่น และเตือนจุดเสี่ยง
  void _runSimulationWalk(
    OsrmRouteResult? osrmRoute,
    double originLat,
    double originLng,
    double destLat,
    double destLng,
    String destName,
    AccessibilityState acc,
  ) {
    _navigationTimer?.cancel();
    _liveGpsSubscription?.cancel();

    // 1. สร้าง Waypoints ตามแนวเส้นทางถนนจริง (OSRM Polyline)
    List<ll.LatLng> pathPoints = [];
    if (osrmRoute != null && osrmRoute.polylineCoordinates.isNotEmpty) {
      pathPoints = osrmRoute.polylineCoordinates
          .map((pt) => ll.LatLng(pt[1], pt[0]))
          .toList();
    } else {
      // Linear interpolation 25 จุดระหว่างจุดเริ่มต้นและปลายทาง
      for (int i = 0; i <= 25; i++) {
        final t = i / 25.0;
        pathPoints.add(ll.LatLng(
          originLat + (destLat - originLat) * t,
          originLng + (destLng - originLng) * t,
        ));
      }
    }

    int currentPointIdx = 0;
    int stepIdx = 0;
    final totalSteps = osrmRoute?.steps.length ?? 0;

    announceSpeech("เริ่มต้นโหมดจำลองการเดินก้าวต่อก้าว นำทางสู่ $destName", acc.voiceEnabled);
    HapticService().turnGuidance();

    _navigationTimer = Timer.periodic(const Duration(milliseconds: 1400), (timer) {
      if (!mounted || !_isNavigating) {
        timer.cancel();
        return;
      }

      if (currentPointIdx < pathPoints.length) {
        final currentPt = pathPoints[currentPointIdx];
        final remaining = Geolocator.distanceBetween(
          currentPt.latitude,
          currentPt.longitude,
          destLat,
          destLng,
        ).round();

        // 1. ตรวจสอบจุดเสี่ยง/สิ่งกีดขวางตามแนวทางเดินจำลองล่วงหน้า 15-25 เมตร
        _checkProactiveHazardAlerts(
          currentPt.latitude,
          currentPt.longitude,
          acc,
          accuracy: 2.0,
          speed: 1.2,
        );

        // 2. เคลื่อนกล้องแผนที่ตามตำแหน่งจำลอง
        try {
          _mapController.move(currentPt, 17.5);
        } catch (_) {}

        // 3. ตรวจสอบขั้นตอนการเลี้ยว (Turn-by-Turn Instruction)
        String instruction = _liveInstruction;
        IconData icon = _liveDirectionIcon;

        if (osrmRoute != null && osrmRoute.steps.isNotEmpty && stepIdx < totalSteps) {
          final step = osrmRoute.steps[stepIdx];
          final stepDist = Geolocator.distanceBetween(
            currentPt.latitude,
            currentPt.longitude,
            step.stepLat,
            step.stepLon,
          );

          // แจ้งเตือนล่วงหน้า 20-25 เมตรก่อนถึงทางแยก
          if (stepDist < 25 && stepIdx < totalSteps - 1) {
            stepIdx++;
            final nextStep = osrmRoute.steps[stepIdx];
            instruction = nextStep.instruction;
            icon = _getManeuverIcon(nextStep.maneuverModifier);
            HapticService().turnGuidance();
            announceSpeech("อีก 20 เมตร ${nextStep.instruction}", acc.voiceEnabled);
          } else {
            final distText = remaining > 1000
                ? '${(remaining / 1000).toStringAsFixed(1)} กม.'
                : '$remaining ม.';
            instruction = "${step.instruction} (เหลืออีก $distText)";
          }
        }

        setState(() {
          _remainingDistance = remaining;
          _liveInstruction = instruction;
          _liveDirectionIcon = icon;
          _customOriginLat = currentPt.latitude;
          _customOriginLng = currentPt.longitude;
        });

        currentPointIdx++;

        // เมื่อถึงจุดหมายปลายทาง
        if (currentPointIdx >= pathPoints.length || remaining <= 10) {
          timer.cancel();
          setState(() {
            _remainingDistance = 0;
            _liveInstruction = "ถึง $destName เรียบร้อยแล้ว (สิ้นสุดการจำลอง)";
            _liveDirectionIcon = Icons.check_circle_rounded;
          });
          HapticService().destinationReached();
          announceSpeech("ถึง $destName เรียบร้อยแล้วค่ะ สิ้นสุดการจำลองการเดิน", acc.voiceEnabled);
        }
      }
    });
  }

  IconData _getManeuverIcon(String modifier) {
    if (modifier.contains('left')) {
      return Icons.turn_left_rounded;
    } else if (modifier.contains('right')) {
      return Icons.turn_right_rounded;
    } else if (modifier.contains('u-turn') || modifier.contains('uturn')) {
      return Icons.u_turn_left_rounded;
    } else {
      return Icons.arrow_upward_rounded;
    }
  }

  void _checkProactiveHazardAlerts(double currentLat, double currentLng, AccessibilityState acc, {double accuracy = 5.0, double speed = 1.2}) {
    if (_gisBarriers.isEmpty) return;

    double minDistance = double.infinity;
    Map<String, dynamic>? closestHazard;
    String closestHazardId = '';

    for (final bar in _gisBarriers) {
      double? bLat = (bar['lat'] as num?)?.toDouble();
      double? bLon = (bar['lon'] as num?)?.toDouble();
      if (bLat == null && bar['location'] is Map) {
        bLat = (bar['location']['latitude'] as num?)?.toDouble();
        bLon = (bar['location']['longitude'] as num?)?.toDouble();
      }
      if (bLat == null || bLon == null) continue;

      final dist = Geolocator.distanceBetween(currentLat, currentLng, bLat, bLon);
      if (dist < minDistance) {
        minDistance = dist;
        closestHazard = bar;
        closestHazardId = '${bar['name']}_${bLat.toStringAsFixed(4)}_${bLon.toStringAsFixed(4)}';
      }
    }

    if (closestHazard == null) return;

    // ประเมิน HazardSeverity ตามประเภทของจุดเสี่ยง
    final String hName = closestHazard['name']?.toString() ?? 'สิ่งกีดขวาง';
    HazardSeverity severity = HazardSeverity.medium;
    if (hName.contains('หลุม') || hName.contains('ก่อสร้าง') || hName.contains('รถ') || hName.contains('ท่อ')) {
      severity = HazardSeverity.critical;
    } else if (hName.contains('ชำรุด') || hName.contains('แยก') || hName.contains('ม้าลาย')) {
      severity = HazardSeverity.high;
    } else {
      severity = HazardSeverity.medium;
    }

    // ประเมินด้วย RiskEngine แบบปรับตาม GPS Uncertainty Factor (ดาวเทียม / Wi-Fi / Cell Site)
    final riskLevel = _riskEngine.evaluate(
      distanceMeters: minDistance,
      gpsAccuracy: accuracy,
      walkingSpeed: speed,
      severity: severity,
    );

    // ควบคุมกล้อง AI ตามสถานะ CameraTriggerState (Event-Driven Vision)
    if (riskLevel.cameraTrigger == CameraTriggerState.activeScanning && _visionTrigger.state == VisionState.idle) {
      _visionTrigger.trigger(VisionTriggerReason.riskEscalation);
    }

    setState(() {
      _currentRiskState = riskLevel.state;
      _cameraTriggerState = riskLevel.cameraTrigger;
      _gpsFixQuality = riskLevel.gpsQuality;
      _dynamicSafetyMargin = riskLevel.safetyMarginMeters;
      _gpsAccuracy = accuracy;
      _sensorFusionStatus = _getGpsQualityLabel(riskLevel.gpsQuality);
    });

    // ตรวจสอบระยะเตือนแบบ Dynamic ตาม Safety Margin ที่คำนวณได้
    if (minDistance <= _dynamicSafetyMargin) {
      // เช็ค Audio Cooldown & Deduplication เพื่อป้องกันเสียงเตือนพร่ำเพรื่อ (Anti-Alert Fatigue)
      if (_riskEngine.shouldPlayAudioAlert(closestHazardId)) {
        // Micro-alert เสียงสั้นกระชับ (ไม่เกิน 1.5 วินาที)
        String spokenAlert = 'ระวัง $hName';
        if (hName.contains('ทางม้าลาย') || hName.contains('ทางข้าม')) {
          spokenAlert = 'พบทางม้าลายข้างหน้า';
        } else if (hName.contains('แยก') || hName.contains('สัญญาณไฟ')) {
          spokenAlert = 'ระวัง สี่แยกไฟแดง';
        } else if (hName.contains('แคบ') || hName.contains('เสา')) {
          spokenAlert = 'ระวัง เสาไฟขวางทาง';
        } else if (hName.contains('ชำรุด') || hName.contains('หลุม') || hName.contains('ท่อ')) {
          spokenAlert = 'ระวัง ทางเท้าชำรุด';
        }

        if (acc.hapticEnabled) {
          if (severity == HazardSeverity.critical) {
            // สั่น 2 จังหวะ (Double Pulse) สำหรับอันตรายร้ายแรง (หลุมลึก/ท่อเปิด/รถบนทางเดิน)
            HapticFeedback.heavyImpact();
            Future.delayed(const Duration(milliseconds: 160), () => HapticFeedback.heavyImpact());
          } else {
            // สั่นระดับกลาง 1 ครั้ง สำหรับเสาไฟฟ้าหรือทางแคบ
            HapticFeedback.mediumImpact();
          }
        }

        // Auto-Incident Logging ส่งต่อข้อมูลจุดเสี่ยงไปยังระบบ กทม. / Traffy Fondue ในพื้นหลัง
        _autoLogIncidentToBMA(
          lat: currentLat,
          lng: currentLng,
          hazardType: hName,
          severity: severity.name,
        );

        setState(() {
          _lastHazardAlert = '$spokenAlert (ระยะ ${minDistance.round()} ม.)';
        });

        announceSpeech(spokenAlert, true);
      }
    }
  }

  /// Auto-Incident Logging: ส่งข้อมูลจุดเสี่ยงที่ตรวจพบเข้าสู่ระบบ กทม. / Traffy Fondue (Item 5)
  void _autoLogIncidentToBMA({
    required double lat,
    required double lng,
    required String hazardType,
    required String severity,
  }) {
    try {
      final url = Uri.parse('${ApiClient.getDefaultBaseUrl()}/api/v1/intelligence/incident-log');
      http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'lat': lat,
          'lng': lng,
          'hazard_type': hazardType,
          'confidence': 0.88,
          'severity': severity,
          'description': 'ตรวจจับโดย TAM AI Assistance (ไม้เท้าขาวร่วมกับเรดาร์ล่วงหน้า)',
        }),
      ).catchError((_) {
        return http.Response('{"status":"offline_logged"}', 200);
      });
    } catch (_) {}
  }

  void _announceCurrentContextAndSurroundings(AccessibilityState acc) {
    if (acc.hapticEnabled) HapticFeedback.mediumImpact();
    
    final dest = _destController.text.trim().isNotEmpty ? _destController.text.trim() : "จุดหมาย";
    final distText = _remainingDistance > 1000 
        ? '${(_remainingDistance / 1000).toStringAsFixed(1)} กิโลเมตร' 
        : '$_remainingDistance เมตร';

    List<String> contextParts = [];
    contextParts.add('ข้อมูลตำแหน่ง: กำลังนำทางไปยัง $dest');
    contextParts.add('เหลือระยะทางอีก $distText');
    contextParts.add('คำแนะนำล่าสุด: $_liveInstruction');

    if (_lastHazardAlert != null) {
      contextParts.add('จุดแจ้งเตือน: $_lastHazardAlert');
    } else {
      contextParts.add('สภาพแวดล้อม: ไม่มีสิ่งกีดขวางร้ายแรงในระยะประชิด');
    }

    final speech = contextParts.join('. ');
    announceSpeech(speech, true);
  }

  @override
  Widget build(BuildContext context) {
    final acc = ref.watch(accessibilityProvider);
    final isHighContrast = acc.highContrast;
    final primaryColor = AppColors.getPrimary(acc.colorBlind, isHighContrast: isHighContrast);

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          child: Text(
            _voiceOnlyMode ? 'นำทางด้วยเสียง (Voice)' : 'แผนที่นำทางช่วยเหลือ',
            style: TextStyle(fontSize: 18 * acc.fontScale, fontWeight: FontWeight.bold),
          ),
        ),
        backgroundColor: _voiceOnlyMode
            ? (isHighContrast ? Colors.black : const Color(0xFF0F172A))
            : primaryColor,
        foregroundColor: Colors.white,
        elevation: isHighContrast ? 0 : 4,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10.0),
            child: Semantics(
              button: true,
              label: _voiceOnlyMode ? 'สลับไปยังโหมดแผนที่' : 'สลับไปยังโหมดเสียงสำหรับคนตาบอด',
              child: ElevatedButton.icon(
                icon: Icon(
                  _voiceOnlyMode ? Icons.map_rounded : Icons.record_voice_over_rounded,
                  size: 18,
                  color: _voiceOnlyMode ? Colors.white : Colors.yellowAccent,
                ),
                label: Text(
                  _voiceOnlyMode ? 'ดูแผนที่' : 'โหมดเสียงตาบอด',
                  style: TextStyle(
                    fontSize: 12 * acc.fontScale,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _voiceOnlyMode ? const Color(0xFF334155) : const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Colors.white70, width: 1.2),
                  ),
                ),
                onPressed: () {
                  setState(() {
                    _voiceOnlyMode = !_voiceOnlyMode;
                  });
                  final msg = _voiceOnlyMode
                      ? 'เปิดโหมดนำทางด้วยเสียงอย่างเดียว สำหรับผู้พิการทางสายตา'
                      : 'เปิดโหมดแผนที่นำทางแบบมองเห็น';
                  announceSpeech(msg, true);
                  if (acc.hapticEnabled) HapticFeedback.mediumImpact();
                },
              ),
            ),
          ),
        ],
        bottom: isHighContrast ? const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, color: Colors.white)) : null,
      ),
      backgroundColor: isHighContrast ? Colors.black : const Color(0xFFE9ECEF),
      body: _voiceOnlyMode
          ? _buildVoiceOnlyView(context, acc, isHighContrast, primaryColor)
          : Stack(
              children: [
          // ═══ Real Interactive OpenStreetMap & Google Maps-grade View ═══
          Positioned.fill(
            child: Builder(
              builder: (context) {
                final double userLat = _customOriginLat ?? 14.8818;
                final double userLng = _customOriginLng ?? 102.0245;
                final bool hasDest = _customDestLat != null && _customDestLng != null && _customDestLat != 0.0;
                final double destLat = _customDestLat ?? userLat;
                final double destLng = _customDestLng ?? userLng;

                List<ll.LatLng> routePolylinePoints = [];
                if (_activeOsrmRoute != null && _activeOsrmRoute!.polylineCoordinates.isNotEmpty) {
                  routePolylinePoints = _activeOsrmRoute!.polylineCoordinates
                      .map((coord) => ll.LatLng(coord[1], coord[0]))
                      .toList();
                } else if (hasDest) {
                  routePolylinePoints = [
                    ll.LatLng(userLat, userLng),
                    ll.LatLng(destLat, destLng),
                  ];
                }

                return ExcludeSemantics(
                  excluding: true,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: ll.LatLng(userLat, userLng),
                      initialZoom: 16.5,
                      minZoom: 12.0,
                      maxZoom: 19.5,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all,
                      ),
                      onPositionChanged: (camera, hasGesture) {
                        _mapZoom = camera.zoom;
                      },
                    ),
                    children: [
                      TileLayer(
                        key: ValueKey('map_tile_theme_$_mapThemeStyle'),
                        urlTemplate: _getMapTileUrl(_mapThemeStyle),
                        subdomains: _getMapSubdomains(_mapThemeStyle),
                        userAgentPackageName: 'com.feefive.accessible_navigation',
                        maxZoom: 20.0,
                      ),
                      if (routePolylinePoints.isNotEmpty) ...[
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: routePolylinePoints,
                              color: isHighContrast ? Colors.yellowAccent : const Color(0xFF2563EB),
                              strokeWidth: 7.0,
                              borderColor: Colors.white,
                              borderStrokeWidth: 2.0,
                            ),
                          ],
                        ),
                        MarkerLayer(
                          markers: _buildRouteDirectionMarkers(routePolylinePoints, isHighContrast),
                        ),
                      ],
                      MarkerLayer(
                        markers: [
                          ..._buildGisMarkers(acc, isHighContrast),
                          // User Current GPS Location Marker
                          Marker(
                            point: ll.LatLng(userLat, userLng),
                            width: 50,
                            height: 50,
                            child: AnimatedBuilder(
                              animation: _pulseAnimation,
                              builder: (context, child) {
                                return Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: 36 * _pulseAnimation.value,
                                      height: 36 * _pulseAnimation.value,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: (isHighContrast ? Colors.yellowAccent : Colors.blueAccent).withOpacity((1.0 - _pulseAnimation.value).clamp(0.0, 1.0)),
                                      ),
                                    ),
                                    Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isHighContrast ? Colors.yellowAccent : Colors.blue[600],
                                        border: Border.all(color: Colors.white, width: 3),
                                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          // Destination Target Marker
                          if (hasDest)
                            Marker(
                              point: ll.LatLng(destLat, destLng),
                              width: 140,
                              height: 75,
                              alignment: Alignment.topCenter,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isHighContrast ? Colors.black : Colors.red[800],
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white, width: 1.5),
                                      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
                                    ),
                                    child: Text(
                                      _destController.text.isNotEmpty ? _destController.text : 'จุดหมาย',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const Icon(Icons.location_on_rounded, color: Colors.red, size: 36),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),



          // Search Form Card overlay
          // 1. Search Form Card overlay (Shown ONLY when !_isNavigating)
          if (!_isNavigating)
            Positioned(
              top: 16.0,
              left: 16.0,
              right: 16.0,
              child: PointerInterceptor(
                child: Card(
                  color: isHighContrast ? Colors.black : Colors.white,
                  elevation: isHighContrast ? 0 : 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: isHighContrast ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _originController,
                          onChanged: _onOriginSearchChanged,
                          style: TextStyle(color: isHighContrast ? Colors.white : Colors.black, fontSize: 16 * acc.fontScale),
                          decoration: InputDecoration(
                            labelText: 'จุดเริ่มต้น',
                            hintText: 'พิมพ์ชื่อสถานที่ หรือใช้ GPS',
                            labelStyle: TextStyle(color: isHighContrast ? Colors.white70 : Colors.grey[700]),
                            prefixIcon: const Icon(Icons.location_on, color: Colors.green),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.my_location, color: Colors.blue),
                              tooltip: 'ดึงพิกัดตำแหน่งจริงปัจจุบัน (GPS)',
                              onPressed: () {
                                _customOriginLat = null;
                                _customOriginLng = null;
                                _originSuggestions = [];
                                _detectAndSetCurrentLocation();
                              },
                            ),
                            border: const OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: isHighContrast ? Colors.white54 : Colors.grey[400]!)),
                          ),
                        ),
                        if (_isSearchingOrigin)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        if (_originSuggestions.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 4, bottom: 8),
                            constraints: const BoxConstraints(maxHeight: 180),
                            decoration: BoxDecoration(
                              color: isHighContrast ? Colors.grey[900] : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.withOpacity(0.5), width: 1.5),
                              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: _originSuggestions.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (ctx, idx) {
                                final item = _originSuggestions[idx];
                                return ListTile(
                                  dense: true,
                                  leading: _getPlaceCategoryIcon(item['category'], isOrigin: true),
                                  title: Text(
                                    item['name'] ?? '',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14 * acc.fontScale,
                                      color: isHighContrast ? Colors.white : Colors.black,
                                    ),
                                  ),
                                  subtitle: Text(
                                    item['display_name'] ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11 * acc.fontScale,
                                      color: isHighContrast ? Colors.white60 : Colors.grey[600],
                                    ),
                                  ),
                                  onTap: () => _selectOrigin(item),
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 12.0),
                        TextField(
                          controller: _destController,
                          onChanged: _onDestSearchChanged,
                          style: TextStyle(color: isHighContrast ? Colors.white : Colors.black, fontSize: 16 * acc.fontScale),
                          decoration: InputDecoration(
                            labelText: 'ปลายทาง (ค้นหาสถานที่จริง เช่น อาคารเรียนรวม 1, มทส)',
                            hintText: 'พิมพ์ค้นหาสถานที่...',
                            labelStyle: TextStyle(color: isHighContrast ? Colors.white70 : Colors.grey[700]),
                            prefixIcon: const Icon(Icons.flag, color: Colors.red),
                            suffixIcon: _destController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      setState(() {
                                        _destController.clear();
                                        _destSuggestions = [];
                                        _customDestLat = null;
                                        _customDestLng = null;
                                      });
                                    },
                                  )
                                : null,
                            border: const OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: isHighContrast ? Colors.white54 : Colors.grey[400]!)),
                          ),
                        ),
                        if (_isSearchingDest)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        if (_destSuggestions.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 4, bottom: 8),
                            constraints: const BoxConstraints(maxHeight: 220),
                            decoration: BoxDecoration(
                              color: isHighContrast ? Colors.grey[900] : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.withOpacity(0.5), width: 1.5),
                              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: _destSuggestions.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (ctx, idx) {
                                final item = _destSuggestions[idx];
                                return ListTile(
                                  dense: true,
                                  leading: _getPlaceCategoryIcon(item['category'], isOrigin: false),
                                  title: Text(
                                    item['name'] ?? '',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14 * acc.fontScale,
                                      color: isHighContrast ? Colors.white : Colors.black,
                                    ),
                                  ),
                                  subtitle: Text(
                                    item['display_name'] ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11 * acc.fontScale,
                                      color: isHighContrast ? Colors.white60 : Colors.grey[600],
                                    ),
                                  ),
                                  onTap: () => _selectDestination(item),
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 12.0),
                        // Comprehensive Travel Mode Selector Scroll (Walk, Grab/Taxi, BTS/MRT, Bus, Win)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildModeSelectChip('walk', 'เดินเท้า (แนะนำ)', Icons.directions_walk_rounded, primaryColor, acc, isHighContrast),
                              _buildModeSelectChip('grab_taxi', 'แท็กซี่ / Grab / Bolt', Icons.local_taxi_rounded, Colors.orange[800]!, acc, isHighContrast),
                              _buildModeSelectChip('bts_mrt', 'รถไฟฟ้า BTS/MRT', Icons.directions_transit_rounded, Colors.indigo[800]!, acc, isHighContrast),
                              _buildModeSelectChip('bus', 'รถเมล์', Icons.directions_bus_rounded, Colors.teal[800]!, acc, isHighContrast),
                              _buildModeSelectChip('win_moto', 'วินมอเตอร์ไซค์', Icons.two_wheeler_rounded, Colors.deepOrange[800]!, acc, isHighContrast),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10.0),
                        // Accessibility GIS Layer Live Indicators
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          decoration: BoxDecoration(
                            color: isHighContrast ? Colors.grey[900] : const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isHighContrast ? Colors.white54 : const Color(0xFFBBF7D0),
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.accessible_rounded, size: 16, color: Colors.blue),
                                  const SizedBox(width: 4),
                                  Text(
                                    'ทางลาด ${_gisPoints.where((p) => p['type'] == 'ramp').length > 0 ? _gisPoints.where((p) => p['type'] == 'ramp').length : 2} จุด',
                                    style: TextStyle(
                                      fontSize: 12 * acc.fontScale,
                                      fontWeight: FontWeight.bold,
                                      color: isHighContrast ? Colors.white : Colors.blue[900],
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.elevator_rounded, size: 16, color: Colors.green),
                                  const SizedBox(width: 4),
                                  Text(
                                    'ลิฟต์ BTS ${_gisPoints.where((p) => p['type'] == 'elevator').length > 0 ? _gisPoints.where((p) => p['type'] == 'elevator').length : 2} จุด',
                                    style: TextStyle(
                                      fontSize: 12 * acc.fontScale,
                                      fontWeight: FontWeight.bold,
                                      color: isHighContrast ? Colors.white : Colors.green[900],
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red),
                                  const SizedBox(width: 4),
                                  Text(
                                    'จุดเสี่ยง ${_gisBarriers.isNotEmpty ? _gisBarriers.length : 2} จุด',
                                    style: TextStyle(
                                      fontSize: 12 * acc.fontScale,
                                      fontWeight: FontWeight.bold,
                                      color: isHighContrast ? Colors.white : Colors.red[900],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10.0),
                        // 🚶‍♂️ Walk Simulation Mode Switch (สำหรับทดสอบในอาคาร / ในห้อง)
                        Container(
                          margin: const EdgeInsets.only(bottom: 10.0),
                          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                          decoration: BoxDecoration(
                            color: _isSimulationMode
                                ? (isHighContrast ? Colors.yellow.withOpacity(0.2) : Colors.amber.withOpacity(0.12))
                                : (isHighContrast ? Colors.grey[900] : Colors.grey[100]),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _isSimulationMode ? Colors.amber : Colors.grey.withOpacity(0.3),
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.directions_walk_rounded,
                                    color: _isSimulationMode ? Colors.amber[800] : Colors.grey,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'โหมดจำลองการเดิน (Demo / Indoor)',
                                        style: TextStyle(
                                          fontSize: 13 * acc.fontScale,
                                          fontWeight: FontWeight.bold,
                                          color: _isSimulationMode ? (isHighContrast ? Colors.yellowAccent : Colors.amber[900]) : (isHighContrast ? Colors.white : Colors.black87),
                                        ),
                                      ),
                                      Text(
                                        _isSimulationMode ? 'ทดสอบก้าวเดิน เลี้ยวซ้าย/ขวา และสั่นในห้อง' : 'ใช้ดาวเทียม GPS สดภายนอกอาคาร',
                                        style: TextStyle(
                                          fontSize: 10 * acc.fontScale,
                                          color: isHighContrast ? Colors.white60 : Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              Switch(
                                value: _isSimulationMode,
                                activeColor: Colors.amber[700],
                                onChanged: (val) {
                                  setState(() {
                                    _isSimulationMode = val;
                                  });
                                  final acc = ref.read(accessibilityProvider);
                                  announceSpeech(
                                    val ? 'เปิดโหมดจำลองการเดินแล้ว เหมาะสำหรับทดสอบในห้องหรืออาคาร' : 'ปิดโหมดจำลอง สลับไปใช้ดาวเทียม GPS สดแล้ว',
                                    acc.voiceEnabled,
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: double.infinity,
                          height: 50.0,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _startNavigation,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isHighContrast ? Colors.white : primaryColor,
                              foregroundColor: isHighContrast ? Colors.black : Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: _isLoading
                                ? SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: isHighContrast ? Colors.black : Colors.white,
                                      strokeWidth: 3,
                                    ),
                                  )
                                : Text(
                                    'คำนวณเส้นทางช่วยเหลือ',
                                    style: TextStyle(fontSize: 16 * acc.fontScale, fontWeight: FontWeight.bold),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 2. Live Navigation Guidance Sheet (Collapsible & Expandable)
          if (_isNavigating) ...[
            if (_isCardCollapsed)
              // ─── Google Maps Style Top Floating Navigation Banner ───
              Positioned(
                top: 12.0,
                left: 12.0,
                right: 12.0,
                child: PointerInterceptor(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isHighContrast ? Colors.black : const Color(0xFF15803D), // High-contrast green header like Google Maps
                      borderRadius: BorderRadius.circular(16),
                      border: isHighContrast ? Border.all(color: Colors.white, width: 2.5) : null,
                      boxShadow: const [
                        BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4)),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
                    child: Row(
                      children: [
                        // Large Maneuver Icon
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isHighContrast ? Colors.white24 : Colors.white.withOpacity(0.2),
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: Icon(_liveDirectionIcon, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 12),
                        // Direction Text + Distance & ETA
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _liveInstruction,
                                style: TextStyle(
                                  fontSize: 15 * acc.fontScale,
                                  fontWeight: FontWeight.bold,
                                  color: isHighContrast ? Colors.yellowAccent : Colors.white,
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Icon(Icons.directions_walk_rounded, size: 14, color: isHighContrast ? Colors.white70 : Colors.white70),
                                  const SizedBox(width: 3),
                                  Text(
                                    _remainingDistance > 1000
                                        ? 'เหลือ ${(_remainingDistance / 1000).toStringAsFixed(1)} กม. • ประมาณ ${(_remainingDistance / 75).ceil()} นาที'
                                        : 'เหลือ $_remainingDistance ม. • ประมาณ ${math.max(1, (_remainingDistance / 75).ceil())} นาที',
                                    style: TextStyle(
                                      fontSize: 12 * acc.fontScale,
                                      color: isHighContrast ? Colors.white70 : Colors.white.withOpacity(0.9),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Quick Action Buttons (Details / Cancel)
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Details Expand Button
                            InkWell(
                              onTap: () => setState(() => _isCardCollapsed = false),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.list_alt_rounded, color: Colors.white, size: 20),
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Quick Exit
                            InkWell(
                              onTap: () {
                                _navigationTimer?.cancel();
                                BackgroundNavigationService.stopNavigation();
                                setState(() {
                                  _isNavigating = false;
                                  _isCardCollapsed = false;
                                  _showRerouteAlert = false;
                                });
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              // ─── Expanded Full Details Navigation Card ───
              Positioned(
                top: 12.0,
                right: 16.0,
                left: 16.0,
                bottom: 80.0,
                child: PointerInterceptor(
                  child: Card(
                    color: isHighContrast ? Colors.black : Colors.white,
                    elevation: isHighContrast ? 0 : 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: isHighContrast ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Trip Top Bar: Origin -> Destination + Collapse Button + Cancel Button
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${_originController.text} ➔ ${_destController.text}',
                                  style: TextStyle(
                                    fontSize: 13 * acc.fontScale,
                                    fontWeight: FontWeight.bold,
                                    color: isHighContrast ? Colors.white70 : Colors.grey[800],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Collapse Button (พับเก็บการ์ด)
                              TextButton.icon(
                                icon: const Icon(Icons.unfold_less_rounded, size: 16),
                                label: Text(
                                  'พับเก็บการ์ด',
                                  style: TextStyle(
                                    fontSize: 11.5 * acc.fontScale,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: isHighContrast ? Colors.yellowAccent : primaryColor,
                                  backgroundColor: isHighContrast ? Colors.white10 : primaryColor.withOpacity(0.08),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () => setState(() => _isCardCollapsed = true),
                              ),
                              const SizedBox(width: 6),
                              // Cancel Button (ยกเลิก)
                              OutlinedButton.icon(
                                icon: const Icon(Icons.close_rounded, size: 16),
                                label: Text(
                                  'ยกเลิก',
                                  style: TextStyle(
                                    fontSize: 11.5 * acc.fontScale,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: Colors.red[700]!, width: 1.2),
                                  foregroundColor: Colors.red[700],
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () {
                                  _navigationTimer?.cancel();
                                  BackgroundNavigationService.stopNavigation();
                                  setState(() {
                                    _isNavigating = false;
                                    _isCardCollapsed = false;
                                    _showRerouteAlert = false;
                                  });
                                },
                              ),
                            ],
                          ),
                          const Divider(height: 14),
                          Expanded(
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [

                          // ─── Risk State Badge + Dynamic GPS Factor + Camera Triggering ───
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isHighContrast ? Colors.white24 : _getRiskBadgeColor(_currentRiskState).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isHighContrast ? Colors.white : _getRiskBadgeColor(_currentRiskState),
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      _getRiskIcon(_currentRiskState),
                                      color: isHighContrast ? Colors.white : _getRiskBadgeColor(_currentRiskState),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'ความเสี่ยง: ${_getRiskLabel(_currentRiskState)} | ระยะปลอดภัย: ${_dynamicSafetyMargin.toStringAsFixed(1)} ม.',
                                        style: TextStyle(
                                          fontSize: 11 * acc.fontScale,
                                          fontWeight: FontWeight.bold,
                                          color: isHighContrast ? Colors.white : _getRiskBadgeColor(_currentRiskState),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '📡 GPS: ±${_gpsAccuracy.toStringAsFixed(0)}ม. (${_getGpsQualityLabel(_gpsFixQuality)})',
                                        style: TextStyle(fontSize: 10 * acc.fontScale, color: isHighContrast ? Colors.white70 : Colors.grey[800]),
                                      ),
                                    ),
                                    Text(
                                      _getCameraTriggerLabel(_cameraTriggerState),
                                      style: TextStyle(fontSize: 10 * acc.fontScale, fontWeight: FontWeight.w600, color: _getCameraTriggerColor(_cameraTriggerState)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                                                    // Background FGS Status
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isHighContrast ? Colors.white12 : Colors.green[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isHighContrast ? Colors.white54 : Colors.green,
                                width: 0.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.notifications_active_rounded, color: Colors.green, size: 14),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Location FGS Active — ทำงานต่อเนื่องเมื่อล็อกหน้าจอ',
                                    style: TextStyle(
                                      fontSize: 10 * acc.fontScale,
                                      fontWeight: FontWeight.w600,
                                      color: isHighContrast ? Colors.white70 : Colors.green[800],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Travel Mode Indicator Banner
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isHighContrast ? Colors.white12 : _getModeBackgroundColor(_currentTravelMode),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isHighContrast ? Colors.white54 : _getModeBorderColor(_currentTravelMode),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _getModeIcon(_currentTravelMode),
                                  color: isHighContrast ? Colors.yellow : _getModeTextColor(_currentTravelMode),
                                  size: 22,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _getModeSummaryText(_currentTravelMode),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12 * acc.fontScale,
                                      color: isHighContrast ? Colors.white : _getModeTextColor(_currentTravelMode),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Mode Switcher Chips (switch mode live during navigation)
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildModeSelectChip('walk', 'เดินเท้า', Icons.directions_walk_rounded, primaryColor, acc, isHighContrast),
                                _buildModeSelectChip('grab_taxi', 'Grab/แท็กซี่', Icons.local_taxi_rounded, Colors.orange[800]!, acc, isHighContrast),
                                _buildModeSelectChip('bts_mrt', 'BTS/MRT', Icons.directions_transit_rounded, Colors.indigo[800]!, acc, isHighContrast),
                                _buildModeSelectChip('bus', 'รถเมล์', Icons.directions_bus_rounded, Colors.teal[800]!, acc, isHighContrast),
                                _buildModeSelectChip('win_moto', 'วิน', Icons.two_wheeler_rounded, Colors.deepOrange[800]!, acc, isHighContrast),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Live Navigation Assistant Panel (Turn-by-turn)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isHighContrast ? Colors.black : Colors.green[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isHighContrast ? Colors.white : Colors.green[800]!,
                                width: 2,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 24,
                                      backgroundColor: isHighContrast ? Colors.white24 : Colors.green[800],
                                      child: Icon(
                                        _liveDirectionIcon,
                                        color: Colors.white,
                                        size: 26,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '🔊 คำสั่งนำทางสด',
                                            style: TextStyle(
                                              color: isHighContrast ? Colors.white70 : Colors.green[900],
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12 * acc.fontScale,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _liveInstruction,
                                            style: TextStyle(
                                              color: isHighContrast ? Colors.white : Colors.black87,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14 * acc.fontScale,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          if (_remainingDistance > 0)
                                            Text(
                                              'ระยะทางที่เหลือ: ${_remainingDistance > 1000 ? '${(_remainingDistance / 1000).toStringAsFixed(1)} กม.' : '$_remainingDistance เมตร'}',
                                              style: TextStyle(
                                                color: isHighContrast ? Colors.lightGreenAccent : Colors.green[800],
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12 * acc.fontScale,
                                              ),
                                            )
                                          else
                                            Text(
                                              'เลี้ยวได้เลย ณ ตอนนี้!',
                                              style: TextStyle(
                                                color: Colors.red[800],
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12 * acc.fontScale,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                
                                // Big Voice Repeat Button
                                SizedBox(
                                  width: double.infinity,
                                  height: 44,
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.volume_up_rounded, size: 20),
                                    label: Text(
                                      '🔊 กดฟังเสียงนำทางซ้ำ',
                                      style: TextStyle(
                                        fontSize: 14 * acc.fontScale,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isHighContrast ? Colors.yellow : Colors.green[800],
                                      foregroundColor: isHighContrast ? Colors.black : Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () => announceSpeech(_liveInstruction, true),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Explainable AI Decision Helper & Rationale Box
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isHighContrast ? Colors.white12 : AppColors.primarySurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isHighContrast ? Colors.white54 : primaryColor,
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.psychology_rounded, color: Colors.purple, size: 20),
                                    const SizedBox(width: 6),
                                    Text(
                                      '🧠 AI Decision Helper: ทำไมถึงเลือกวิธีนี้?',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12 * acc.fontScale,
                                        color: isHighContrast ? Colors.white : Colors.purple[900],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _aiAgentShortReason.isNotEmpty 
                                      ? _aiAgentShortReason 
                                      : _getDecisionShortReason(_currentTravelMode),
                                  style: TextStyle(
                                    fontSize: 12 * acc.fontScale,
                                    fontWeight: FontWeight.w600,
                                    color: isHighContrast ? Colors.white70 : Colors.black87,
                                    height: 1.4,
                                  ),
                                ),
                                if (_aiAgentThought.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isHighContrast ? Colors.white10 : Colors.purple.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('💡 ', style: TextStyle(fontSize: 12)),
                                        Expanded(
                                          child: Text(
                                            _aiAgentThought,
                                            style: TextStyle(
                                              fontSize: 11 * acc.fontScale,
                                              color: isHighContrast ? Colors.cyanAccent : Colors.purple[800],
                                              height: 1.3,
                                            ),
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                // 4-Factor Breakdown Chips
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    _buildFactorBadge('🛡️ ความปลอดภัย', '$_aiSafetyScore/100', isHighContrast, acc),
                                    _buildFactorBadge('🚶 กายภาพ/เดิน', '$_aiWalkScore/100', isHighContrast, acc),
                                    _buildFactorBadge('💰 ค่าใช้จ่าย', '$_aiCostScore/100', isHighContrast, acc),
                                    _buildFactorBadge('⏱️ ความเร็ว', '$_aiTimeScore/100', isHighContrast, acc),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                // Voice Explanation Button
                                SizedBox(
                                  width: double.infinity,
                                  height: 38,
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.record_voice_over_rounded, size: 18),
                                    label: Text(
                                      '🔊 ฟังคำอธิบายเหตุผลของ AI Agent',
                                      style: TextStyle(
                                        fontSize: 12 * acc.fontScale,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: isHighContrast ? Colors.white : primaryColor, width: 1.5),
                                      foregroundColor: isHighContrast ? Colors.white : primaryColor,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => announceSpeech(
                                      _aiAgentSpeech.isNotEmpty ? _aiAgentSpeech : _getDecisionDetailedSpeech(_currentTravelMode),
                                      true,
                                    ),
                                  ),
                                ),
                              ], // closes AI Helper Column children
                            ), // closes AI Helper Column
                          ), // closes AI Helper Container
                        ], // closes Scrollable Column children
                      ), // closes Scrollable Column
                    ), // closes SingleChildScrollView
                  ), // closes Expanded
                ], // closes Outer Column children
              ), // closes Outer Column
            ), // closes Padding
          ), // closes Card
        ), // closes PointerInterceptor
      ), // closes Positioned
    ], // closes if (_isNavigating) ...[

          // Map Filter Options Toolbar (Chips)


          // Reroute Alert Dialog Simulator Overlay
          if (_showRerouteAlert)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.6),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Card(
                      color: isHighContrast ? Colors.black : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: isHighContrast ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange),
                            const SizedBox(height: 16.0),
                            Text(
                              'พบสิ่งกีดขวางข้างหน้า!',
                              style: TextStyle(fontSize: 22 * acc.fontScale, fontWeight: FontWeight.bold, color: isHighContrast ? Colors.white : Colors.black),
                            ),
                            const SizedBox(height: 12.0),
                            Text(
                              'พบสิ่งกีดขวางหรือทางต่างระดับบนเส้นทางไปยัง ${_destController.text.trim().isNotEmpty ? _destController.text.trim() : "จุดหมาย"} ระบบได้คำนวณเส้นทางเลี่ยงที่ปลอดภัยให้ใหม่แล้ว ต้องการเปลี่ยนเส้นทางหรือไม่?',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16 * acc.fontScale, color: isHighContrast ? Colors.white70 : Colors.black87, height: 1.5),
                            ),
                            const SizedBox(height: 24.0),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () {
                                      setState(() {
                                        _showRerouteAlert = false;
                                      });
                                    },
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: isHighContrast ? Colors.white : Colors.grey),
                                      foregroundColor: isHighContrast ? Colors.white : Colors.black87,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                    child: Text('เพิกเฉย', style: TextStyle(fontSize: 16 * acc.fontScale)),
                                  ),
                                ),
                                const SizedBox(width: 12.0),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _triggerRerouting,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isHighContrast ? Colors.white : primaryColor,
                                      foregroundColor: isHighContrast ? Colors.black : Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                    child: Text('เปลี่ยนเส้นทาง', style: TextStyle(fontSize: 16 * acc.fontScale, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          
          // ─── Floating Accessibility & Map Controls Toolbar ───
          Positioned(
            right: 16,
            bottom: _isNavigating ? 30 : 24,
            child: PointerInterceptor(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Zoom In (+)
                  FloatingActionButton.small(
                    heroTag: 'map_zoom_in_fab',
                    tooltip: 'ซูมเข้า (+)',
                    onPressed: () {
                      if (acc.hapticEnabled) HapticFeedback.lightImpact();
                      final currentZoom = _mapController.camera.zoom;
                      final targetZoom = (currentZoom + 1.0).clamp(12.0, 19.5);
                      _mapController.move(_mapController.camera.center, targetZoom);
                    },
                    backgroundColor: isHighContrast ? Colors.black : Colors.white,
                    foregroundColor: isHighContrast ? Colors.white : primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: isHighContrast ? const BorderSide(color: Colors.white, width: 2) : const BorderSide(color: Colors.black12),
                    ),
                    elevation: 5,
                    child: const Icon(Icons.add_rounded, size: 24),
                  ),
                  const SizedBox(height: 8),
                  // 2. Zoom Out (-)
                  FloatingActionButton.small(
                    heroTag: 'map_zoom_out_fab',
                    tooltip: 'ซูมออก (-)',
                    onPressed: () {
                      if (acc.hapticEnabled) HapticFeedback.lightImpact();
                      final currentZoom = _mapController.camera.zoom;
                      final targetZoom = (currentZoom - 1.0).clamp(12.0, 19.5);
                      _mapController.move(_mapController.camera.center, targetZoom);
                    },
                    backgroundColor: isHighContrast ? Colors.black : Colors.white,
                    foregroundColor: isHighContrast ? Colors.white : primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: isHighContrast ? const BorderSide(color: Colors.white, width: 2) : const BorderSide(color: Colors.black12),
                    ),
                    elevation: 5,
                    child: const Icon(Icons.remove_rounded, size: 24),
                  ),
                  const SizedBox(height: 8),
                  // 3. Recenter Current Location (📍)
                  FloatingActionButton.small(
                    heroTag: 'recenter_gps_fab',
                    tooltip: 'กลับมาที่ตำแหน่งปัจจุบันของฉัน (GPS)',
                    onPressed: () async {
                      if (acc.hapticEnabled) HapticFeedback.mediumImpact();
                      announceSpeech('กลับมาที่ตำแหน่งปัจจุบันของคุณ', acc.voiceEnabled);
                      try {
                        final pos = await Geolocator.getCurrentPosition(timeLimit: const Duration(seconds: 3));
                        _mapController.move(ll.LatLng(pos.latitude, pos.longitude), 17.5);
                      } catch (_) {
                        if (_customOriginLat != null) {
                          _mapController.move(ll.LatLng(_customOriginLat!, _customOriginLng!), 17.5);
                        }
                      }
                    },
                    backgroundColor: isHighContrast ? Colors.black : primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: isHighContrast ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
                    ),
                    elevation: 6,
                    child: const Icon(Icons.my_location_rounded, size: 22),
                  ),
                  // 4. Voice Guidance Repeat (🔊)
                  if (_isNavigating) ...[
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'voice_guidance_repeat_fab',
                      tooltip: 'ฟังเสียงนำทางซ้ำ (Voice Guidance)',
                      onPressed: () {
                        if (acc.hapticEnabled) HapticFeedback.mediumImpact();
                        announceSpeech(_liveInstruction, true);
                      },
                      backgroundColor: isHighContrast ? Colors.yellowAccent : Colors.green[800],
                      foregroundColor: isHighContrast ? Colors.black : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: isHighContrast ? const BorderSide(color: Colors.black, width: 2) : BorderSide.none,
                      ),
                      elevation: 6,
                      child: const Icon(Icons.volume_up_rounded, size: 22),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceOnlyView(BuildContext context, AccessibilityState acc, bool isHighContrast, Color primaryColor) {
    if (!_isNavigating) {
      // ═══ Pre-Navigation Voice Mode Screen (Ultra Simple Search) ═══
      return Container(
        color: isHighContrast ? Colors.black : const Color(0xFF0F172A),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Mode Header Badge
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: isHighContrast ? Colors.yellowAccent.withOpacity(0.15) : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isHighContrast ? Colors.yellowAccent : const Color(0xFF0EA5E9),
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.record_voice_over_rounded, color: isHighContrast ? Colors.yellowAccent : const Color(0xFF38BDF8), size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'โหมดเสียงอย่างเดียว (Voice-Only)',
                          style: TextStyle(
                            fontSize: 16 * acc.fontScale,
                            fontWeight: FontWeight.bold,
                            color: isHighContrast ? Colors.yellowAccent : Colors.white,
                          ),
                        ),
                        Text(
                          'ออกแบบพิเศษสำหรับผู้พิการทางสายตา ตัดแผนที่และปุ่มรกออกทั้งหมด',
                          style: TextStyle(fontSize: 12 * acc.fontScale, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Destination Field
            Text(
              'เลือกสถานที่ปลายทาง:',
              style: TextStyle(fontSize: 16 * acc.fontScale, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _destController,
              onChanged: _onDestSearchChanged,
              style: TextStyle(color: Colors.white, fontSize: 18 * acc.fontScale, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: 'พิมพ์ชื่อสถานที่ปลายทาง เช่น สยาม, โรงพยาบาล',
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.yellowAccent, size: 28),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.mic_rounded, color: Colors.yellowAccent, size: 28),
                  tooltip: 'พูดชื่อสถานที่ปลายทาง',
                  onPressed: () {
                    announceSpeech('กำลังเปิดระบบค้นหาด้วยเสียง กรุณาพูดชื่อสถานที่', true);
                  },
                ),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.white38)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.yellowAccent, width: 2)),
              ),
            ),
            if (_destSuggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.yellowAccent.withOpacity(0.5)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _destSuggestions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white24),
                  itemBuilder: (ctx, i) {
                    final item = _destSuggestions[i];
                    return ListTile(
                      title: Text(item['name'] ?? item['display_name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.yellowAccent, size: 16),
                      onTap: () => _selectDestination(item),
                    );
                  },
                ),
              ),
            const SizedBox(height: 20),

            // Quick Shortcut Chips for Visually Impaired
            Text(
              'หรือเลือกจุดหมายด่วน:',
              style: TextStyle(fontSize: 14 * acc.fontScale, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildVoiceShortcutChip('🏥 โรงพยาบาลใกล้ที่สุด', 'โรงพยาบาล', acc),
                _buildVoiceShortcutChip('🚆 สถานีรถไฟฟ้า BTS/MRT', 'สถานีรถไฟฟ้า', acc),
                _buildVoiceShortcutChip('🚏 ป้ายรถเมล์', 'ป้ายรถประจำทาง', acc),
                _buildVoiceShortcutChip('🏪 เซเว่นอีเลฟเว่น', '7-Eleven', acc),
              ],
            ),
            const Spacer(),

            // 🚶‍♂️ Walk Simulation Mode Switch for Voice Users
            Container(
              margin: const EdgeInsets.only(bottom: 12.0),
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
              decoration: BoxDecoration(
                color: _isSimulationMode
                    ? (isHighContrast ? Colors.yellow.withOpacity(0.25) : Colors.amber.withOpacity(0.18))
                    : (isHighContrast ? Colors.grey[900] : const Color(0xFF1E293B)),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _isSimulationMode ? Colors.amber : Colors.white24,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.directions_walk_rounded,
                        color: _isSimulationMode ? Colors.amberAccent : Colors.white70,
                        size: 26,
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'โหมดจำลองการเดิน (Demo)',
                            style: TextStyle(
                              fontSize: 15 * acc.fontScale,
                              fontWeight: FontWeight.bold,
                              color: _isSimulationMode ? Colors.amberAccent : Colors.white,
                            ),
                          ),
                          Text(
                            _isSimulationMode ? 'จำลองก้าวเดิน เลี้ยวซ้าย/ขวา และสั่นเตือนในห้อง' : 'ใช้ดาวเทียม GPS สดจริงภายนอก',
                            style: TextStyle(
                              fontSize: 11 * acc.fontScale,
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Switch(
                    value: _isSimulationMode,
                    activeColor: Colors.amberAccent,
                    onChanged: (val) {
                      setState(() {
                        _isSimulationMode = val;
                      });
                      final acc = ref.read(accessibilityProvider);
                      announceSpeech(
                        val ? 'เปิดโหมดจำลองการเดินแล้ว เหมาะสำหรับทดสอบในห้องหรืออาคาร' : 'ปิดโหมดจำลอง สลับไปใช้ดาวเทียม GPS สดแล้ว',
                        acc.voiceEnabled,
                      );
                    },
                  ),
                ],
              ),
            ),

            // Big Start Navigation Button
            SizedBox(
              height: 64,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.navigation_rounded, size: 30),
                label: Text(
                  '🚀 เริ่มนำทางด้วยเสียงทันที',
                  style: TextStyle(fontSize: 18 * acc.fontScale, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isHighContrast ? Colors.yellowAccent : const Color(0xFF16A34A),
                  foregroundColor: isHighContrast ? Colors.black : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  elevation: 6,
                ),
                onPressed: _isLoading ? null : _startNavigation,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      );
    }

    // ═══ Active Live Voice-Only Navigation Screen (3-4 Giant Touch Targets) ═══
    return Container(
      color: isHighContrast ? Colors.black : const Color(0xFF090D16),
      padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Top Turn-by-Turn Big Instruction Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isHighContrast ? Colors.black : const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isHighContrast ? Colors.white : const Color(0xFF38BDF8),
                width: 2.5,
              ),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: isHighContrast ? Colors.yellowAccent : const Color(0xFF2563EB),
                      child: Icon(_liveDirectionIcon, color: isHighContrast ? Colors.black : Colors.white, size: 32),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _liveInstruction,
                            style: TextStyle(
                              fontSize: 18 * acc.fontScale,
                              fontWeight: FontWeight.bold,
                              color: isHighContrast ? Colors.yellowAccent : Colors.white,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _remainingDistance > 1000
                                ? 'เหลืออีก ${(_remainingDistance / 1000).toStringAsFixed(1)} กม. • ประมาณ ${(_remainingDistance / 75).ceil()} นาที'
                                : 'เหลืออีก $_remainingDistance ม. • ประมาณ ${math.max(1, (_remainingDistance / 75).ceil())} นาที',
                            style: TextStyle(
                              fontSize: 13 * acc.fontScale,
                              color: isHighContrast ? Colors.white70 : const Color(0xFF94A3B8),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_lastHazardAlert != null) ...[
                  const Divider(height: 20, color: Colors.white24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red[900]!.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent, width: 1.2),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.yellowAccent, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _lastHazardAlert!,
                            style: TextStyle(
                              fontSize: 12.5 * acc.fontScale,
                              color: Colors.yellowAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Giant Primary Button: "แตะเพื่อฟังคำแนะนำล่าสุดซ้ำ" (Central Target)
          Expanded(
            flex: 3,
            child: Semantics(
              button: true,
              label: 'แตะเพื่อฟังคำแนะนำล่าสุดซ้ำ คำแนะนำปัจจุบันคือ $_liveInstruction',
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isHighContrast ? Colors.yellowAccent : const Color(0xFF1D4ED8),
                  foregroundColor: isHighContrast ? Colors.black : Colors.white,
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(color: isHighContrast ? Colors.black : Colors.white38, width: 2),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                ),
                onPressed: () {
                  announceSpeech(_liveInstruction, true);
                  if (acc.hapticEnabled) HapticFeedback.mediumImpact();
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.volume_up_rounded,
                      size: 58,
                      color: isHighContrast ? Colors.black : Colors.white,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '🔊 แตะเพื่อฟังคำแนะนำซ้ำ',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 21 * acc.fontScale,
                        fontWeight: FontWeight.bold,
                        color: isHighContrast ? Colors.black : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'กดตรงนี้ได้ทุกเวลาเพื่อฟังทิศทางล่าสุด',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13 * acc.fontScale,
                        color: isHighContrast ? Colors.black87 : Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 3. Giant Secondary Button: "บอกตำแหน่งปัจจุบัน & สิ่งรอบตัว"
          Expanded(
            flex: 2,
            child: Semantics(
              button: true,
              label: 'บอกตำแหน่งปัจจุบันและสิ่งรอบตัว แตะเพื่อฟังพิกัด จุดสังเกต และสิ่งกีดขวาง',
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isHighContrast ? const Color(0xFF27272A) : const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: Colors.white30, width: 1.5),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onPressed: () => _announceCurrentContextAndSurroundings(acc),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.explore_rounded, size: 38, color: Colors.yellowAccent),
                    const SizedBox(width: 14),
                    Flexible(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🧭 บอกตำแหน่ง & สิ่งรอบตัว',
                            style: TextStyle(
                              fontSize: 17 * acc.fontScale,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'แตะเพื่อฟังสภาพแวดล้อมและจุดเสี่ยงใกล้ตัว',
                            style: TextStyle(
                              fontSize: 12 * acc.fontScale,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 4. Bottom Row Action Buttons: "หยุดนำทาง" & "ขอความช่วยเหลือ SOS"
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.stop_circle_rounded, size: 24),
                    label: Text(
                      '🛑 หยุดนำทาง',
                      style: TextStyle(fontSize: 15 * acc.fontScale, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                    ),
                    onPressed: () {
                      _navigationTimer?.cancel();
                      _liveGpsSubscription?.cancel();
                      BackgroundNavigationService.stopNavigation();
                      setState(() {
                        _isNavigating = false;
                        _isCardCollapsed = false;
                        _showRerouteAlert = false;
                      });
                      announceSpeech('หยุดการนำทางเรียบร้อยแล้วค่ะ', true);
                      if (acc.hapticEnabled) HapticFeedback.heavyImpact();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.emergency_rounded, size: 24),
                    label: Text(
                      '🆘 ขอความช่วยเหลือ',
                      style: TextStyle(fontSize: 15 * acc.fontScale, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                    ),
                    onPressed: () {
                      announceSpeech('เปิดศูนย์แจ้งเหตุฉุกเฉิน SOS', true);
                      Navigator.of(context).pushNamed('/sos');
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceShortcutChip(String label, String query, AccessibilityState acc) {
    return ActionChip(
      label: Text(label, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13 * acc.fontScale)),
      backgroundColor: const Color(0xFF1E293B),
      side: const BorderSide(color: Colors.white30),
      onPressed: () {
        setState(() {
          _destController.text = query;
        });
        _onDestSearchChanged(query);
        announceSpeech('เลือกปลายทาง $query', true);
      },
    );
  }

  Widget _buildFilterChip(String label, IconData icon, bool isSelected, ValueChanged<bool> onSelected, Color activeColor, bool isHighContrast, AccessibilityState acc) {
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 14 * acc.fontScale, fontWeight: FontWeight.bold)),
      avatar: Icon(icon, color: isHighContrast ? (isSelected ? Colors.black : Colors.white) : (isSelected ? Colors.white : activeColor), size: 18),
      selected: isSelected,
      onSelected: onSelected,
      selectedColor: isHighContrast ? Colors.white : activeColor,
      backgroundColor: isHighContrast ? Colors.black : Colors.white,
      labelStyle: TextStyle(color: isHighContrast ? (isSelected ? Colors.black : Colors.white) : (isSelected ? Colors.white : Colors.black87)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isHighContrast ? Colors.white : (isSelected ? activeColor : Colors.grey[300]!)),
      ),
      elevation: isSelected ? 2 : 0,
    );
  }

  Widget _buildModeSelectChip(String modeId, String label, IconData icon, Color activeColor, AccessibilityState acc, bool isHighContrast) {
    final isSelected = _currentTravelMode == modeId;
    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: InkWell(
        onTap: () {
          setState(() {
            _currentTravelMode = modeId;
          });
          if (_isNavigating) _startLiveNavigationCountdown();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? (isHighContrast ? Colors.white : activeColor)
                : (isHighContrast ? Colors.white10 : Colors.grey[200]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? (isHighContrast ? Colors.white : activeColor)
                  : (isHighContrast ? Colors.white30 : Colors.grey[400]!),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? (isHighContrast ? Colors.black : Colors.white)
                    : (isHighContrast ? Colors.white70 : Colors.black87),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12 * acc.fontScale,
                  color: isSelected
                      ? (isHighContrast ? Colors.black : Colors.white)
                      : (isHighContrast ? Colors.white70 : Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getModeIcon(String mode) {
    switch (mode) {
      case 'grab_taxi':
        return Icons.local_taxi_rounded;
      case 'bts_mrt':
        return Icons.directions_transit_rounded;
      case 'bus':
        return Icons.directions_bus_rounded;
      case 'win_moto':
        return Icons.two_wheeler_rounded;
      default:
        return Icons.directions_walk_rounded;
    }
  }

  String _getModeSummaryText(String mode) {
    final distKm = (_remainingDistance / 1000.0);
    final distStr = _remainingDistance > 1000 ? '${distKm.toStringAsFixed(1)} กม.' : '$_remainingDistance ม.';
    final walkMins = math.max(1, (_remainingDistance / 80).round());
    final taxiCost = math.max(35, (35 + distKm * 12).round());

    switch (mode) {
      case 'grab_taxi':
        return 'โหมดที่เลือก: 🚕 แท็กซี่ / Grab / Bolt (ประมาณ $taxiCost บาท • ส่งถึงประตู)';
      case 'bts_mrt':
        return 'โหมดที่เลือก: 🚆 ระบบขนส่งสาธารณะ ($distStr • มีลิฟต์/ทางลาด)';
      case 'bus':
        return 'โหมดที่เลือก: 🚌 รถโดยสารประจำทาง (ประหยัด 15-20 บาท)';
      case 'win_moto':
        final winCost = math.max(25, (25 + distKm * 10).round());
        return 'โหมดที่เลือก: 🛵 วินมอเตอร์ไซค์ (ประมาณ $winCost บาท • เร่งด่วน)';
      default:
        return 'โหมดที่เลือก: 🚶 เดินเท้า ($distStr • ประมาณ $walkMins นาที)';
    }
  }

  Color _getModeBackgroundColor(String mode) {
    switch (mode) {
      case 'grab_taxi':
        return Colors.orange[100]!;
      case 'bts_mrt':
        return Colors.indigo[100]!;
      case 'bus':
        return Colors.teal[100]!;
      case 'win_moto':
        return Colors.deepOrange[100]!;
      default:
        return Colors.green[100]!;
    }
  }

  Color _getModeBorderColor(String mode) {
    switch (mode) {
      case 'grab_taxi':
        return Colors.orange[800]!;
      case 'bts_mrt':
        return Colors.indigo[800]!;
      case 'bus':
        return Colors.teal[800]!;
      case 'win_moto':
        return Colors.deepOrange[800]!;
      default:
        return Colors.green[800]!;
    }
  }

  Color _getModeTextColor(String mode) {
    switch (mode) {
      case 'grab_taxi':
        return Colors.orange[900]!;
      case 'bts_mrt':
        return Colors.indigo[900]!;
      case 'bus':
        return Colors.teal[900]!;
      case 'win_moto':
        return Colors.deepOrange[900]!;
      default:
        return Colors.green[900]!;
    }
  }

  String _getDecisionShortReason(String mode) {
    final distKm = (_remainingDistance / 1000.0);
    final distStr = _remainingDistance > 1000 ? '${distKm.toStringAsFixed(1)} กม.' : '$_remainingDistance ม.';
    final walkMins = math.max(1, (_remainingDistance / 80).round());
    final taxiCost = math.max(35, (35 + distKm * 12).round());

    switch (mode) {
      case 'grab_taxi':
        return 'ส่งตรงถึงหน้าประตู • ประมาณ $taxiCost บาท • เลี่ยงสิ่งกีดขวางบนทางเท้า 100%';
      case 'bts_mrt':
        return 'เลี่ยงรถติด • มีลิฟต์และเจ้าหน้าที่ช่วยเหลือ • เหมาะกับระยะไกล';
      case 'bus':
        return 'ค่าเดินทางประหยัดที่สุด (15-20 บาท) • เหมาะกับการเดินทางทั่วไป';
      case 'win_moto':
        return 'เหมาะกับเวลาเร่งด่วน • แจ้งผู้ขับขี่และสวมหมวกนิรภัยเพื่อความปลอดภัย';
      default:
        return 'ระยะทางจริง $distStr • ใช้เวลาประมาณ $walkMins นาที • ไม่มีค่าใช้จ่าย';
    }
  }

  // ─── Risk State Badge Helpers (ข้อ 6 ของอาจารย์) ───
  Color _getRiskBadgeColor(RiskState state) {
    switch (state) {
      case RiskState.safe: return Colors.green;
      case RiskState.warning: return Colors.orange;
      case RiskState.highRisk: return Colors.deepOrange;
      case RiskState.critical: return Colors.red;
    }
  }

  IconData _getRiskIcon(RiskState state) {
    switch (state) {
      case RiskState.safe: return Icons.check_circle_rounded;
      case RiskState.warning: return Icons.warning_amber_rounded;
      case RiskState.highRisk: return Icons.error_rounded;
      case RiskState.critical: return Icons.dangerous_rounded;
    }
  }

  String _getRiskLabel(RiskState state) {
    switch (state) {
      case RiskState.safe: return 'ปลอดภัย';
      case RiskState.warning: return 'เฝ้าระวัง';
      case RiskState.highRisk: return 'เสี่ยงสูง';
      case RiskState.critical: return 'อันตราย!';
    }
  }

  String _getGpsQualityLabel(GpsFixQuality quality) {
    switch (quality) {
      case GpsFixQuality.highPrecision: return 'ดาวเทียมตรง (GNSS)';
      case GpsFixQuality.mediumPrecision: return 'Wi-Fi/A-GPS';
      case GpsFixQuality.lowPrecision: return 'Cell Site (ขยายระยะเผื่อ)';
    }
  }

  String _getCameraTriggerLabel(CameraTriggerState state) {
    switch (state) {
      case CameraTriggerState.sleep: return '💤 ปิดกล้อง (Sleep)';
      case CameraTriggerState.prewarm: return '⚡ เตรียมพร้อม (Pre-warm)';
      case CameraTriggerState.activeScanning: return '📷 สแกนจริง (YOLO11)';
    }
  }

  Color _getCameraTriggerColor(CameraTriggerState state) {
    switch (state) {
      case CameraTriggerState.sleep: return Colors.grey;
      case CameraTriggerState.prewarm: return Colors.orange;
      case CameraTriggerState.activeScanning: return Colors.redAccent;
    }
  }

  String _getDecisionDetailedSpeech(String mode) {
    final destName = _destController.text.trim().isNotEmpty ? _destController.text.trim() : 'จุดหมาย';
    final distKm = (_remainingDistance / 1000.0);
    final distStr = _remainingDistance > 1000 ? '${distKm.toStringAsFixed(1)} กิโลเมตร' : '$_remainingDistance เมตร';
    final walkMins = math.max(1, (_remainingDistance / 80).round());
    final taxiCost = math.max(35, (35 + distKm * 12).round());

    switch (mode) {
      case 'grab_taxi':
        return 'AI แนะนำเรียกรถ Grab หรือแท็กซี่ไป $destName ค่ะ ระยะทาง $distStr ค่าโดยสารประมาณ $taxiCost บาท รถจะเทียบท่ารับส่งถึงหน้าประตูอาคาร เลี่ยงสิ่งกีดขวางบนทางเท้าได้ 100% ค่ะ';
      case 'bts_mrt':
        return 'AI แนะนำระบบขนส่งมวลชนเพื่อเดินทางไป $destName ระยะทาง $distStr ค่ะ มีลิฟต์โดยสารและทางลาดสำหรับผู้พิการ';
      case 'bus':
        return 'AI แนะนำรถโดยสารประจำทางค่ะ เป็นตัวเลือกที่ประหยัดที่สุดในการไป $destName ค่าโดยสารประมาณ 15 ถึง 20 บาท';
      case 'win_moto':
        return 'AI แนะนำวินมอเตอร์ไซค์สำหรับกรณีเร่งด่วนไป $destName ค่ะ โปรดสวมหมวกนิรภัยเพื่อความปลอดภัยนะคะ';
      default:
        return 'AI วิเคราะห์แล้วแนะนำให้เดินเท้าไปยัง $destName ค่ะ ระยะทางจริง $distStr ใช้เวลาประมาณ $walkMins นาทีค่ะ';
    }
  }

  String _getFactorSafety(String mode) {
    switch (mode) {
      case 'grab_taxi': return '98% (ส่งถึงประตู)';
      case 'bts_mrt': return '95% (มีลิฟต์/ทางลาด)';
      case 'bus': return '85% (ทางเท้ามาตรฐาน)';
      case 'win_moto': return '70% (มีความเสี่ยง)';
      default: return '95% (ทางเท้ามีระบบเตือน)';
    }
  }

  String _getFactorWalk(String mode) {
    final distStr = _remainingDistance > 1000 ? '${(_remainingDistance / 1000.0).toStringAsFixed(1)} กม.' : '$_remainingDistance ม.';
    final walkMins = math.max(1, (_remainingDistance / 80).round());
    switch (mode) {
      case 'grab_taxi': return '20 ม. (ส่งถึงประตู)';
      case 'bts_mrt': return '80 ม. (ขึ้นลิฟต์)';
      case 'bus': return '150 ม. (ไปป้าย)';
      case 'win_moto': return '30 ม. (ไปวิน)';
      default: return '$distStr ($walkMins นาที)';
    }
  }

  String _getFactorCost(String mode) {
    final distKm = (_remainingDistance / 1000.0);
    final taxiCost = math.max(35, (35 + distKm * 12).round());
    final winCost = math.max(25, (25 + distKm * 10).round());
    switch (mode) {
      case 'grab_taxi': return '~$taxiCost บาท';
      case 'bts_mrt': return '25-45 บาท';
      case 'bus': return '15-20 บาท';
      case 'win_moto': return '~$winCost บาท';
      default: return '0 บาท (ฟรี)';
    }
  }

  String _getFactorTime(String mode) {
    final walkMins = math.max(1, (_remainingDistance / 80).round());
    final carMins = math.max(3, ((_remainingDistance / 1000.0) / 30 * 60).round());
    switch (mode) {
      case 'grab_taxi': return '$carMins นาที';
      case 'bts_mrt': return '${carMins + 5} นาที';
      case 'bus': return '${carMins + 10} นาที';
      case 'win_moto': return '${math.max(2, (carMins * 0.7).round())} นาที';
      default: return '$walkMins นาที';
    }
  }

  Widget _buildFactorBadge(String label, String value, bool isHighContrast, AccessibilityState acc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isHighContrast ? Colors.white10 : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isHighContrast ? Colors.white30 : Colors.grey[300]!),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 11 * acc.fontScale,
          fontWeight: FontWeight.bold,
          color: isHighContrast ? Colors.white : Colors.black87,
        ),
      ),
    );
  }

  Widget _getPlaceCategoryIcon(dynamic category, {required bool isOrigin}) {
    if (category == 'campus') {
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.purple[50],
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.school_rounded, color: Colors.deepPurple, size: 20),
      );
    } else if (category == 'hospital') {
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.red[50],
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.local_hospital_rounded, color: Colors.red, size: 20),
      );
    } else if (category == 'transit') {
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.indigo[50],
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.directions_transit_rounded, color: Colors.indigo, size: 20),
      );
    } else if (category == 'landmark') {
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.amber[50],
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.location_city_rounded, color: Colors.deepOrange, size: 20),
      );
    }
    return Icon(
      isOrigin ? Icons.my_location_rounded : Icons.place_rounded,
      color: isOrigin ? Colors.green : Colors.red,
      size: 20,
    );
  }

  // ─── GIS Layer: Interactive Bangkok & Korat Accessibility Markers ───
  List<Marker> _buildGisMarkers(AccessibilityState acc, bool isHighContrast) {
    final List<Marker> markers = [];

    // 1. REAL BTS / MRT STATIONS
    if (_filterTransit) {
      for (final st in _transitStations) {
        final double? lat = (st['lat'] as num?)?.toDouble();
        final double? lon = (st['lon'] as num?)?.toDouble();
        if (lat == null || lon == null) continue;

        final isBts = (st['category'] == 'bts') || (st['id']?.toString().startsWith('bts_') ?? false);
        final color = isBts ? const Color(0xFF008080) : const Color(0xFF1E3A8A);

        markers.add(
          Marker(
            point: ll.LatLng(lat, lon),
            width: 140,
            height: 52,
            alignment: Alignment.center,
            child: GestureDetector(
              onTap: () {
                _showGisDetailModal(
                  title: st['name'] ?? 'สถานีรถไฟฟ้า',
                  subtitle: st['line'] ?? 'ขนส่งมวลชนระบบราง',
                  category: isBts ? 'BTS Skytrain' : 'MRT Subway',
                  icon: isBts ? Icons.directions_subway_rounded : Icons.train_rounded,
                  iconColor: color,
                  details: [
                    '🛗 ลิฟต์คนพิการ: ${st['has_elevator'] == true ? 'มี (ใช้งานได้ปกติ)' : 'ไม่มี'}',
                    '♿ ทางลาดมาตรฐาน: ${st['has_ramp'] == true ? 'มี' : 'ไม่มี'}',
                    '🦯 ทางนำสายตา (Tactile): ${st['has_tactile'] == true ? 'มีตลอดชานชาลา' : 'ไม่มี'}',
                  ],
                  targetLat: lat,
                  targetLon: lon,
                );
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white, width: 1.2),
                      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
                    ),
                    child: Text(
                      st['name']?.toString().replaceAll(' (CEN - สถานีกลาง)', '').replaceAll(' (N8)', '').replaceAll(' (E4 / เชื่อม MRT สุขุมวิท)', '') ?? 'BTS/MRT',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Icon(Icons.directions_subway_rounded, color: color, size: 22),
                ],
              ),
            ),
          ),
        );
      }
    }

    // 2. REAL BUS STOPS
    if (_filterBus) {
      for (final bus in _busStops) {
        final double? lat = (bus['lat'] as num?)?.toDouble();
        final double? lon = (bus['lon'] as num?)?.toDouble();
        if (lat == null || lon == null) continue;

        markers.add(
          Marker(
            point: ll.LatLng(lat, lon),
            width: 130,
            height: 48,
            alignment: Alignment.center,
            child: GestureDetector(
              onTap: () {
                _showGisDetailModal(
                  title: bus['name'] ?? 'ป้ายรถประจำทาง',
                  subtitle: bus['lines'] ?? 'สายรถเมล์ที่ผ่าน',
                  category: 'ป้ายรถเมล์ ขสมก.',
                  icon: Icons.directions_bus_rounded,
                  iconColor: Colors.teal[800]!,
                  details: [
                    '🚌 สายรถเมล์: ${bus['lines'] ?? 'สายหลัก'}',
                    '♿ ชานชาลารถเมล์ชานต่ำ (Low-Floor Bus Compatible)',
                  ],
                  targetLat: lat,
                  targetLon: lon,
                );
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.teal[800],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white, width: 1),
                      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
                    ),
                    child: Text(
                      bus['name']?.toString().replaceAll('ป้ายรถเมล์ ', '') ?? 'ป้ายรถเมล์',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Icon(Icons.directions_bus_rounded, color: Colors.teal[800], size: 20),
                ],
              ),
            ),
          ),
        );
      }
    }

    // 3. ACCESSIBILITY POINTS (Elevators, Ramps, Tactile Paving, Traffic Lights, Zebra Crossings)
    for (final pt in _gisPoints) {
      final type = pt['type']?.toString().toLowerCase() ?? '';
      if (type == 'elevator' && !_filterElevators) continue;
      if (type == 'ramp' && !_filterRamps) continue;
      if (type == 'tactile' && !_filterTactilePaths) continue;
      if (type == 'traffic_light' && !_filterTrafficLights) continue;
      if (type == 'zebra_crossing' && !_filterZebraCrossings) continue;

      double? lat = (pt['lat'] as num?)?.toDouble();
      double? lon = (pt['lon'] as num?)?.toDouble();
      if (lat == null && pt['location'] is Map) {
        lat = (pt['location']['latitude'] as num?)?.toDouble();
        lon = (pt['location']['longitude'] as num?)?.toDouble();
      }
      if (lat == null || lon == null) continue;

      IconData iconData = Icons.elevator_rounded;
      Color markerColor = Colors.purple;
      String typeLabel = 'ลิฟต์คนพิการ';

      if (type == 'ramp') {
        iconData = Icons.accessible_rounded;
        markerColor = Colors.green[700]!;
        typeLabel = 'ทางลาดมาตรฐาน';
      } else if (type == 'tactile') {
        iconData = Icons.alt_route_rounded;
        markerColor = Colors.amber[800]!;
        typeLabel = 'ทางนำสายตา (Tactile)';
      } else if (type == 'traffic_light') {
        iconData = Icons.traffic_rounded;
        markerColor = Colors.deepOrange[800]!;
        typeLabel = 'สี่แยกไฟแดง (Traffic Signal)';
      } else if (type == 'zebra_crossing') {
        iconData = Icons.transfer_within_a_station_rounded;
        markerColor = const Color(0xFF1E3A8A);
        typeLabel = 'ทางม้าลาย (Zebra Crossing)';
      }

      final double finalLat = lat;
      final double finalLon = lon;
      final bool isWideBadge = (type == 'traffic_light' || type == 'zebra_crossing');

      markers.add(
        Marker(
          point: ll.LatLng(finalLat, finalLon),
          width: isWideBadge ? 140 : 36,
          height: isWideBadge ? 54 : 36,
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () {
              _showGisDetailModal(
                title: pt['name'] ?? 'จุดอำนวยความสะดวก ($typeLabel)',
                subtitle: pt['detail'] ?? 'เปิดให้บริการปกติ',
                category: typeLabel,
                icon: iconData,
                iconColor: markerColor,
                details: [
                  '📍 สถานะ: ${pt['status'] == 'operational' ? 'ใช้งานได้ปกติ 100%' : 'เปิดบริการ'}',
                  'ℹ️ ข้อมูล: ${pt['detail'] ?? 'สิ่งอำนวยความสะดวกสำหรับผู้พิการ'}',
                ],
                targetLat: finalLat,
                targetLon: finalLon,
              );
            },
            child: isWideBadge
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: markerColor,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white, width: 1.2),
                          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                        ),
                        child: Text(
                          pt['name']?.toString().split('(').first.trim() ?? typeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Icon(iconData, color: markerColor, size: 22),
                    ],
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: markerColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                    ),
                    child: Icon(iconData, color: Colors.white, size: 18),
                  ),
          ),
        ),
      );
    }

    // 4. REALISTIC ROAD & SIDEWALK BARRIERS
    if (_filterBarriers) {
      for (final bar in _gisBarriers) {
        double? lat = (bar['lat'] as num?)?.toDouble();
        double? lon = (bar['lon'] as num?)?.toDouble();
        if (lat == null && bar['location'] is Map) {
          lat = (bar['location']['latitude'] as num?)?.toDouble();
          lon = (bar['location']['longitude'] as num?)?.toDouble();
        }
        if (lat == null || lon == null) continue;

        final double finalBarLat = lat;
        final double finalBarLon = lon;
        final sev = bar['severity']?.toString() ?? 'medium';
        final isHigh = sev == 'high';

        markers.add(
          Marker(
            point: ll.LatLng(finalBarLat, finalBarLon),
            width: 140,
            height: 56,
            alignment: Alignment.center,
            child: GestureDetector(
              onTap: () {
                _showGisDetailModal(
                  title: bar['name'] ?? '⚠️ สิ่งกีดขวางบนเส้นทาง',
                  subtitle: bar['severity_text'] ?? 'ระดับความเสี่ยง: $sev',
                  category: 'สิ่งกีดขวาง (Hazard)',
                  icon: Icons.warning_amber_rounded,
                  iconColor: Colors.red[800]!,
                  details: [
                    '⚠️ ระดับความเสี่ยง: ${bar['severity_text'] ?? (isHigh ? 'อันตรายสูง' : 'ปานกลาง')}',
                    '🛡️ คำแนะนำ: ${bar['instruction'] ?? bar['description'] ?? 'กรุณาระมัดระวังเป็นพิเศษ'}',
                  ],
                  targetLat: finalBarLat,
                  targetLon: finalBarLon,
                  isHazard: true,
                );
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: isHigh ? Colors.red[900] : Colors.orange[900],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white, width: 1.2),
                      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                    ),
                    child: Text(
                      '⚠️ ${bar['name']?.toString().split('(').first.trim() ?? 'สิ่งกีดขวาง'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Icon(Icons.warning_amber_rounded, color: isHigh ? Colors.red[700] : Colors.orange[700], size: 24),
                ],
              ),
            ),
          ),
        );
      }
    }

    return markers;
  }

  List<Marker> _buildRouteDirectionMarkers(List<ll.LatLng> points, bool isHighContrast) {
    if (points.length < 2) return [];
    List<Marker> markers = [];
    final int step = (points.length / 8).ceil().clamp(2, 25);
    for (int i = 0; i < points.length - 1; i += step) {
      final p1 = points[i];
      final p2 = points[i + 1];
      final double angle = math.atan2(p2.longitude - p1.longitude, p2.latitude - p1.latitude);
      markers.add(
        Marker(
          point: p1,
          width: 22,
          height: 22,
          alignment: Alignment.center,
          child: Transform.rotate(
            angle: angle,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isHighContrast ? Colors.yellowAccent : const Color(0xFF1E40AF),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
              ),
              child: Icon(
                Icons.navigation_rounded,
                size: 14,
                color: isHighContrast ? Colors.black : Colors.white,
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  String _getMapTileUrl(String style) {
    switch (style) {
      case 'guardian_cyber':
        // Vibrant Humanitarian Style (Clean, soft purple-orange tones, high contrast pedestrian paths, 100% watermark free)
        return 'https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png';
      case 'minimal_slate':
        // Esri Clean Slate Silver Canvas (Ultra-clean, modern, highlights all pins, 100% watermark free)
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}';
      case 'midnight_neon':
        // Esri Midnight Dark Charcoal Canvas (High contrast dark theme, 100% watermark free)
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}';
      case 'pedestrian_assist':
        // CyclOSM Accessible Pedestrian & Wheelchair Cartography
        return 'https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png';
      case 'traffic':
        return 'https://{s}.google.com/vt/lyrs=m,traffic&hl=th&gl=th&x={x}&y={y}&z={z}';
      case 'satellite':
        return 'https://{s}.google.com/vt/lyrs=y&hl=th&gl=th&x={x}&y={y}&z={z}';
      default:
        return 'https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png';
    }
  }

  List<String> _getMapSubdomains(String style) {
    if (style == 'traffic' || style == 'satellite') {
      return const ['mt0', 'mt1', 'mt2', 'mt3'];
    }
    if (style == 'minimal_slate' || style == 'midnight_neon') {
      return const [];
    }
    return const ['a', 'b', 'c'];
  }

  void _showGisDetailModal({
    required String title,
    required String subtitle,
    required String category,
    required IconData icon,
    required Color iconColor,
    required List<String> details,
    required double targetLat,
    required double targetLon,
    bool isHazard = false,
  }) {
    final acc = ref.read(accessibilityProvider);
    final isHighContrast = acc.highContrast;

    // Announce via voice
    announceSpeech('$category: $title. $subtitle', acc.voiceEnabled);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isHighContrast ? Colors.black : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: isHighContrast ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isHazard ? Colors.red[100] : Colors.blue[50],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      category,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isHazard ? Colors.red[900] : Colors.blue[900],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15 * acc.fontScale,
                      fontWeight: FontWeight.bold,
                      color: isHighContrast ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 13 * acc.fontScale,
                fontWeight: FontWeight.w600,
                color: isHighContrast ? Colors.cyanAccent : Colors.grey[800],
              ),
            ),
            const Divider(height: 20),
            ...details.map(
              (d) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3.0),
                child: Text(
                  d,
                  style: TextStyle(
                    fontSize: 12 * acc.fontScale,
                    color: isHighContrast ? Colors.white70 : Colors.black87,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('ปิด', style: TextStyle(color: isHighContrast ? Colors.white : Colors.grey[700])),
          ),
          if (!isHazard)
            ElevatedButton.icon(
              icon: const Icon(Icons.navigation_rounded, size: 18),
              label: const Text('นำทางมาที่นี่'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isHighContrast ? Colors.yellowAccent : const Color(0xFF4F46E5),
                foregroundColor: isHighContrast ? Colors.black : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                setState(() {
                  _destController.text = title;
                  _customDestLat = targetLat;
                  _customDestLng = targetLon;
                });
                _startNavigation();
              },
            ),
        ],
      ),
    );
  }
}

class LiveGpsRadarPainter extends CustomPainter {
  final bool isHighContrast;
  final double routeProgress;
  final double pulseScale;
  final String destinationName;
  final double? destLat;
  final double? destLon;
  final double? originLat;
  final double? originLon;
  final int remainingDistance;
  final bool isNavigating;

  LiveGpsRadarPainter({
    required this.isHighContrast,
    required this.routeProgress,
    required this.pulseScale,
    required this.destinationName,
    this.destLat,
    this.destLon,
    this.originLat,
    this.originLon,
    required this.remainingDistance,
    required this.isNavigating,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.45);
    final maxRadius = math.min(size.width * 0.44, size.height * 0.35);

    // Background gradient
    final bgPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.0, -0.1),
        radius: 1.2,
        colors: isHighContrast
            ? [Colors.black, const Color(0xFF121212)]
            : [const Color(0xFF1E293B), const Color(0xFF0F172A)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Radar concentric rings
    final ringPaint = Paint()
      ..color = isHighContrast ? Colors.white24 : Colors.cyanAccent.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (int i = 1; i <= 4; i++) {
      final r = maxRadius * (i / 4.0);
      canvas.drawCircle(center, r, ringPaint);
    }

    // Crosshair axes
    final axisPaint = Paint()
      ..color = isHighContrast ? Colors.white12 : Colors.cyanAccent.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(center.dx - maxRadius, center.dy), Offset(center.dx + maxRadius, center.dy), axisPaint);
    canvas.drawLine(Offset(center.dx, center.dy - maxRadius), Offset(center.dx, center.dy + maxRadius), axisPaint);

    // Cardinal directions text
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    void drawDirection(String text, Offset pos, Color color) {
      textPainter.text = TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(pos.dx - textPainter.width / 2, pos.dy - textPainter.height / 2));
    }

    final dirColor = isHighContrast ? Colors.white70 : Colors.cyanAccent.withOpacity(0.7);
    drawDirection('N (เหนือ)', Offset(center.dx, center.dy - maxRadius - 16), Colors.redAccent);
    drawDirection('S (ใต้)', Offset(center.dx, center.dy + maxRadius + 16), dirColor);
    drawDirection('W (ตก)', Offset(center.dx - maxRadius - 24, center.dy), dirColor);
    drawDirection('E (ออก)', Offset(center.dx + maxRadius + 24, center.dy), dirColor);

    // Range distance label
    final rangeText = remainingDistance > 1000
        ? '${(remainingDistance / 1000).toStringAsFixed(1)} กม.'
        : '$remainingDistance ม.';
    drawDirection(
      'รัศมีตรวจจับ GPS • $rangeText',
      Offset(center.dx, center.dy + maxRadius + 38),
      isHighContrast ? Colors.lightGreenAccent : Colors.tealAccent,
    );

    // Pulse ripple around user center
    final pulseRadius = 24.0 * pulseScale;
    final pulsePaint = Paint()
      ..color = (isHighContrast ? Colors.white : Colors.cyanAccent).withOpacity((0.6 / pulseScale).clamp(0.0, 0.6))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, pulseRadius, pulsePaint);

    // User center GPS dot
    final userDotPaint = Paint()
      ..color = isHighContrast ? Colors.white : Colors.blueAccent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 9.0, userDotPaint);

    final userBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(center, 9.0, userBorderPaint);

    // ═══ Real-time Destination Pin Dropper (📍 ปักหมุดลงสถานที่จริง) ═══
    if (destinationName.isNotEmpty || (destLat != null && destLon != null)) {
      // 1. Calculate Real Geographical Bearing Angle from GPS to Target
      double bearingRad = -math.pi / 4; // Default visual angle
      if (destLat != null && destLon != null && destLat != 0.0 && destLon != 0.0) {
        final oLat = (originLat != null && originLat != 0.0) ? originLat! : 14.8818;
        final oLon = (originLon != null && originLon != 0.0) ? originLon! : 102.0245;

        final dLon = (destLon! - oLon) * (math.pi / 180.0);
        final y = math.sin(dLon) * math.cos(destLat! * (math.pi / 180.0));
        final x = math.cos(oLat * (math.pi / 180.0)) * math.sin(destLat! * (math.pi / 180.0)) -
            math.sin(oLat * (math.pi / 180.0)) * math.cos(destLat! * (math.pi / 180.0)) * math.cos(dLon);
        final mathBearing = math.atan2(y, x); // 0 = North, pi/2 = East
        bearingRad = mathBearing - (math.pi / 2); // Canvas radians (0 is East, -pi/2 is North)
      }

      final targetX = center.dx + maxRadius * 0.82 * math.cos(bearingRad);
      final targetY = center.dy + maxRadius * 0.82 * math.sin(bearingRad);
      final targetPoint = Offset(targetX, targetY);

      // Route line if navigating
      if (isNavigating && routeProgress > 0) {
        final linePaint = Paint()
          ..color = isHighContrast ? Colors.yellowAccent : Colors.amberAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(center, Offset.lerp(center, targetPoint, routeProgress)!, linePaint);
      }

      // Pin Glow Aura
      final pinGlow = Paint()
        ..color = Colors.redAccent.withOpacity(0.3)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(targetPoint, 14.0, pinGlow);

      // Dropped Pin Body
      final pinPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill;
      canvas.drawCircle(targetPoint, 9.0, pinPaint);

      final pinBorder = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(targetPoint, 9.0, pinBorder);

      // Pin Inner Dot
      final pinInner = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(targetPoint, 3.0, pinInner);

      // Destination Name & Distance Badge Card
      final labelText = destinationName.isNotEmpty ? destinationName : 'จุดหมาย';
      final distBadge = remainingDistance > 0 ? ' • $rangeText' : '';
      textPainter.text = TextSpan(
        text: '📍 $labelText$distBadge',
        style: TextStyle(
          color: isHighContrast ? Colors.yellowAccent : Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black87,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(targetPoint.dx - textPainter.width / 2, targetPoint.dy - 28));
    }
  }

  @override
  bool shouldRepaint(covariant LiveGpsRadarPainter oldDelegate) {
    return oldDelegate.isHighContrast != isHighContrast ||
        oldDelegate.routeProgress != routeProgress ||
        oldDelegate.pulseScale != pulseScale ||
        oldDelegate.remainingDistance != remainingDistance ||
        oldDelegate.destinationName != destinationName ||
        oldDelegate.destLat != destLat ||
        oldDelegate.destLon != destLon ||
        oldDelegate.isNavigating != isNavigating;
  }
}

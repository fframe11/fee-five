import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/accessibility_notifier.dart';
import '../../core/api_client.dart';
import '../../core/tts_helper.dart';
import 'map_loader.dart';

class NavigationScreen extends ConsumerStatefulWidget {
  const NavigationScreen({super.key});

  @override
  ConsumerState<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends ConsumerState<NavigationScreen> with TickerProviderStateMixin {
  final TextEditingController _originController = TextEditingController(text: "สยามพารากอน");
  final TextEditingController _destController = TextEditingController(text: "สถานีรถไฟฟ้า BTS สยาม");
  
  bool _isNavigating = false;
  bool _isLoading = false;
  bool _showRerouteAlert = false;
  double _score = 1.0;
  int _selectedRouteIndex = 0; // 0 = Safe Route, 1 = Shortest Unsafe Route
  Map<String, dynamic>? _transitRouteData;
  List<dynamic>? _multiModalOptions;
  String _selectedPreference = 'balanced';
  bool _isCardCollapsed = false;
  
  Timer? _navigationTimer;
  int _currentStepIndex = 0;
  int _remainingDistance = 150;
  String _liveInstruction = "กำลังจัดเตรียมระบบนำทาง...";
  IconData _liveDirectionIcon = Icons.navigation_rounded;
  
  bool _filterElevators = true;
  bool _filterRamps = true;
  bool _filterTactilePaths = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  late AnimationController _routeController;
  late Animation<double> _routeAnimation;

  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _originController.dispose();
    _destController.dispose();
    _pulseController.dispose();
    _routeController.dispose();
    super.dispose();
  }

  void _drawSelectedRoute() {
    final acc = ref.read(accessibilityProvider);
    final isWheelchair = acc.accessibilityMode == 'wheelchair';
    
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
    
    Map<String, dynamic>? routeData;
    List<dynamic>? multiModalData;
    try {
      // Query GTFS / GTFS-Realtime from backend
      routeData = await ApiClient().queryTransitRoute(
        13.7461, 100.5348, // Siam Paragon
        13.7450, 100.5380, // CentralWorld
      );
      
      // Query Multi-Modal Journey recommendations
      multiModalData = await ApiClient().queryMultiModalRecommendations(
        13.7461, 100.5348,
        13.7450, 100.5380,
        _selectedPreference,
      );
    } catch (e) {
      // Local fallback mock data if backend connection fails
      routeData = {
        'route': 'สาย 1',
        'walk_to_stop': '180 เมตร',
        'vehicle': 'BUS-102',
        'next_stop': 'สยามเซ็นเตอร์ ฝั่งตะวันตก',
        'eta_minutes': 6,
        'stops_remaining': 3,
        'destination': 'หน้าเซ็นทรัลเวิลด์'
      };
      
      multiModalData = [
        {
          'mode': 'bus',
          'mode_name': 'รถเมล์แอร์ (สาย 1)',
          'price': 15.0,
          'price_text': '15 บาท (รถร้อน 8 บาท)',
          'duration_minutes': 13,
          'walk_distance_meters': 250,
          'icon': 'directions_bus',
          'score': _selectedPreference == 'cheapest' ? 95.0 : 82.0,
          'is_recommended': _selectedPreference == 'cheapest',
          'reason': 'แนะนำรถเมล์: ป้ายห่าง 250 ม. ค่าเดินทาง 15 บาท ประหยัดและเสถียรที่สุด'
        },
        {
          'mode': 'train',
          'mode_name': 'รถไฟฟ้า (BTS / MRT)',
          'price': 17.0,
          'price_text': '17 บาท (BTS 17-62 / MRT 17-44)',
          'duration_minutes': 8,
          'walk_distance_meters': 450,
          'icon': 'directions_transit',
          'score': _selectedPreference == 'fastest' ? 94.0 : 85.0,
          'is_recommended': _selectedPreference == 'fastest' || _selectedPreference == 'balanced',
          'reason': 'แนะนำรถไฟฟ้า: เลี่ยงรถติด ทำเวลาได้เร็วที่สุดใน 8 นาที ปลอดภัยตลอดชานชาลา'
        },
        {
          'mode': 'ride_hailing',
          'mode_name': 'แท็กซี่ (Grab / Bolt)',
          'price': 51.0,
          'price_text': 'Grab 51 บาท / Bolt 42 บาท',
          'duration_minutes': 6,
          'walk_distance_meters': 50,
          'icon': 'local_taxi',
          'score': _selectedPreference == 'least_walking' ? 96.0 : 65.0,
          'is_recommended': _selectedPreference == 'least_walking',
          'reason': 'แนะนำแท็กซี่/Grab: ลดระยะการเดินเหลือ 50 ม. ส่งตรงจุดหมาย สะดวกกับผู้ต้องการสิ่งอำนวยความสะดวก'
        },
        {
          'mode': 'walking',
          'mode_name': 'เดินเท้า (แนะนำให้เดิน 🟢)',
          'price': 0.0,
          'price_text': 'ฟรี',
          'duration_minutes': 4,
          'walk_distance_meters': 370,
          'icon': 'directions_walk',
          'score': 86.9,
          'is_recommended': false,
          'reason': 'แนะนำเดินเท้า: ระยะทางใกล้เพียง 370 ม. เส้นทาง แนะนำให้เดิน 🟢 ไม่มีค่าใช้จ่ายและปลอดภัย'
        }
      ];
      
      // Sort multiModalData by score descending
      multiModalData.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
      // Set the first item as recommended
      for (var i = 0; i < multiModalData.length; i++) {
        multiModalData[i]['is_recommended'] = (i == 0);
      }
    }
    
    if (!mounted) return;
    
    setState(() {
      _isLoading = false;
      _isNavigating = true;
      _selectedRouteIndex = 0; // Default to safe route (Best Way)
      _score = 0.98;
      _transitRouteData = routeData;
      _multiModalOptions = multiModalData;
    });
    
    _drawSelectedRoute();
    
    _routeController.forward(from: 0.0);
    _startLiveNavigationCountdown();

    // Simulate elevator outage barrier trigger in 5 seconds if they choose shortest
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _isNavigating && _selectedRouteIndex == 1) {
        setState(() {
          _showRerouteAlert = true;
        });
      }
    });
  }

  Future<void> _updatePreference(String preference) async {
    setState(() {
      _selectedPreference = preference;
      _isLoading = true;
    });
    
    try {
      final multiModalData = await ApiClient().queryMultiModalRecommendations(
        13.7461, 100.5348,
        13.7450, 100.5380,
        preference,
      );
      if (mounted) {
        setState(() {
          _multiModalOptions = multiModalData;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final fallbackData = [
          {
            'mode': 'bus',
            'mode_name': 'รถเมล์แอร์ (สาย 1)',
            'price': 15.0,
            'price_text': '15 บาท (รถร้อน 8 บาท)',
            'duration_minutes': 13,
            'walk_distance_meters': 250,
            'icon': 'directions_bus',
            'score': preference == 'cheapest' ? 95.0 : 82.0,
            'is_recommended': preference == 'cheapest',
            'reason': 'แนะนำรถเมล์: ป้ายห่าง 250 ม. ค่าเดินทาง 15 บาท ประหยัดและเสถียรที่สุด'
          },
          {
            'mode': 'train',
            'mode_name': 'รถไฟฟ้า (BTS / MRT)',
            'price': 17.0,
            'price_text': '17 บาท (BTS 17-62 / MRT 17-44)',
            'duration_minutes': 8,
            'walk_distance_meters': 450,
            'icon': 'directions_transit',
            'score': preference == 'fastest' ? 94.0 : 85.0,
            'is_recommended': preference == 'fastest' || preference == 'balanced',
            'reason': 'แนะนำรถไฟฟ้า: เลี่ยงรถติด ทำเวลาได้เร็วที่สุดใน 8 นาที ปลอดภัยตลอดชานชาลา'
          },
          {
            'mode': 'ride_hailing',
            'mode_name': 'แท็กซี่ (Grab / Bolt)',
            'price': 51.0,
            'price_text': 'Grab 51 บาท / Bolt 42 บาท',
            'duration_minutes': 6,
            'walk_distance_meters': 50,
            'icon': 'local_taxi',
            'score': preference == 'least_walking' ? 96.0 : 65.0,
            'is_recommended': preference == 'least_walking',
            'reason': 'แนะนำแท็กซี่/Grab: ลดระยะการเดินเหลือ 50 ม. ส่งตรงจุดหมาย สะดวกกับผู้ต้องการสิ่งอำนวยความสะดวก'
          },
          {
            'mode': 'walking',
            'mode_name': 'เดินเท้า (แนะนำให้เดิน 🟢)',
            'price': 0.0,
            'price_text': 'ฟรี',
            'duration_minutes': 4,
            'walk_distance_meters': 370,
            'icon': 'directions_walk',
            'score': 86.9,
            'is_recommended': false,
            'reason': 'แนะนำเดินเท้า: ระยะทางใกล้เพียง 370 ม. เส้นทาง แนะนำให้เดิน 🟢 ไม่มีค่าใช้จ่ายและปลอดภัย'
          }
        ];
        fallbackData.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
        for (var i = 0; i < fallbackData.length; i++) {
          fallbackData[i]['is_recommended'] = (i == 0);
        }
        
        setState(() {
          _multiModalOptions = fallbackData;
          _isLoading = false;
        });
      }
    }
  }

  void _triggerRerouting() {
    setState(() {
      _showRerouteAlert = false;
      _selectedRouteIndex = 0; // switch to safe route
      _score = 0.98; 
      _destController.text = "BTS สยาม (ลิฟต์ทางออก 3)";
    });

    _drawSelectedRoute();
    _startLiveNavigationCountdown();

    _routeController.forward(from: 0.0);
  }

  void _startLiveNavigationCountdown() {
    _navigationTimer?.cancel();
    _currentStepIndex = 0;
    _remainingDistance = 150;
    _liveInstruction = "เดินตรงไปตามทางนำสายตาเลี่ยงสิ่งกีดขวาง";
    _liveDirectionIcon = Icons.arrow_upward_rounded;
    
    final acc = ref.read(accessibilityProvider);
    announceSpeech("กำลังเริ่มระบบนำทางสดเลี่ยงสิ่งกีดขวางค่ะ เดินตรงไปตามทางนำสายตา 150 เมตร", acc.voiceEnabled);

    _navigationTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (!mounted || !_isNavigating) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_currentStepIndex == 0) {
          // Step 1: Walk straight. Remaining counts down from 150m to 0m.
          _remainingDistance -= 10;
          if (_remainingDistance == 100) {
            _liveInstruction = "อีก 100 เมตร เตรียมเลี้ยวซ้ายเข้าทางเชื่อมสกายวอล์ก";
            _liveDirectionIcon = Icons.turn_left_rounded;
            announceSpeech("อีก 100 เมตร เลี้ยวซ้ายเข้าสู่ทางเชื่อมสกายวอล์กค่ะ", acc.voiceEnabled);
          } else if (_remainingDistance <= 0) {
            _remainingDistance = 0;
            _liveInstruction = "เลี้ยวซ้ายได้เลย ณ ตอนนี้! เข้าสู่ทางเชื่อมสกายวอล์ก";
            _liveDirectionIcon = Icons.arrow_back_rounded;
            announceSpeech("เลี้ยวซ้ายได้เลย ณ ตอนนี้ค่ะ", acc.voiceEnabled);
            
            // Advance to Step 2 after 3 seconds delay
            _currentStepIndex = 1;
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted && _isNavigating && _currentStepIndex == 1) {
                setState(() {
                  _remainingDistance = 80;
                  _liveInstruction = "เดินตรงไปบนทางเชื่อมสกายวอล์กเลี่ยงบันไดชัน";
                  _liveDirectionIcon = Icons.arrow_upward_rounded;
                  announceSpeech("เดินตรงไปบนทางเชื่อมสกายวอล์ก 80 เมตรเพื่อเลี่ยงบันไดชันค่ะ", acc.voiceEnabled);
                });
              }
            });
          }
        } else if (_currentStepIndex == 1) {
          // Step 2: Walk on Skywalk. Remaining counts down from 80m to 0m.
          _remainingDistance -= 10;
          if (_remainingDistance == 50) {
            _liveInstruction = "อีก 50 เมตร เตรียมเลี้ยวขวาใช้ทางลาดเข้าทางออก 3 ของสถานี BTS";
            _liveDirectionIcon = Icons.turn_right_rounded;
            announceSpeech("อีก 50 เมตร เลี้ยวขวาใช้ทางลาดเข้าสู่สถานี บีทีเอส สยามค่ะ", acc.voiceEnabled);
          } else if (_remainingDistance <= 0) {
            _remainingDistance = 0;
            _liveInstruction = "เลี้ยวขวาได้เลย ณ ตอนนี้! เข้าสู่ทางลาดลิฟต์ทางออก 3";
            _liveDirectionIcon = Icons.arrow_forward_rounded;
            announceSpeech("เลี้ยวขวาได้เลย ณ ตอนนี้ ใช้ทางลาดเข้าสู่ลิฟต์ บีทีเอส สยาม ทางออก 3 ค่ะ", acc.voiceEnabled);

            // Advance to Step 3 after 3 seconds delay
            _currentStepIndex = 2;
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted && _isNavigating && _currentStepIndex == 2) {
                setState(() {
                  _remainingDistance = 0;
                  _liveInstruction = "เดินทางถึงสถานีรถไฟฟ้า BTS สยาม ทางออก 3 (มีลิฟต์ให้บริการ)";
                  _liveDirectionIcon = Icons.check_circle_rounded;
                  announceSpeech("เดินทางถึงจุดหมายปลายทางอย่างปลอดภัยแล้วค่ะ ขอบพระคุณที่ใช้บริการค่ะ", acc.voiceEnabled);
                });
              }
            });
          }
        }
      });
    });
  }

  void _showMarkerInfo(BuildContext context, String title, String detail, IconData icon, Color color, AccessibilityState acc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: acc.highContrast ? Colors.black : Colors.white,
        shape: RoundedRectangleBorder(
          side: acc.highContrast ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(icon, color: acc.highContrast ? Colors.white : color),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(color: acc.highContrast ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 18 * acc.fontScale)),
          ],
        ),
        content: Text(
          detail,
          style: TextStyle(color: acc.highContrast ? Colors.white70 : Colors.black87, fontSize: 16 * acc.fontScale),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('ปิด', style: TextStyle(color: acc.highContrast ? Colors.white : Colors.blue[800], fontSize: 16 * acc.fontScale)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final acc = ref.watch(accessibilityProvider);
    final isHighContrast = acc.highContrast;

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          child: Text(
            'แผนที่นำทางช่วยเหลือ',
            style: TextStyle(fontSize: 20 * acc.fontScale, fontWeight: FontWeight.bold),
          ),
        ),
        backgroundColor: isHighContrast ? Colors.black : Colors.blue[900],
        foregroundColor: Colors.white,
        elevation: isHighContrast ? 0 : 4,
        bottom: isHighContrast ? const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, color: Colors.white)) : null,
      ),
      backgroundColor: isHighContrast ? Colors.black : Colors.grey[100],
      body: Stack(
        children: [
          // Custom Painted Map Canvas
          Positioned.fill(
            child: kIsWeb
                ? HtmlElementView(
                    key: ValueKey('map-iframe-$isHighContrast'),
                    viewType: 'map-iframe',
                  )
                : RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_pulseController, _routeController]),
                      builder: (context, child) {
                        return CustomPaint(
                          painter: CityMapPainter(
                            isHighContrast: isHighContrast,
                            routeProgress: _isNavigating ? _routeAnimation.value : 0.0,
                          ),
                          child: Container(),
                        );
                      },
                    ),
                  ),
          ),

          // User GPS Dot
          if (!kIsWeb) ...[
            Positioned(
              left: 100,
              top: 250,
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: isHighContrast ? Colors.white.withOpacity(0.5) : Colors.blue.withOpacity(0.4),
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              left: 105,
              top: 255,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isHighContrast ? Colors.white : Colors.blue[800],
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),

            // Origin and Destination Markers
            if (_isNavigating) ...[
              Positioned(
                left: 90,
                top: 215,
                child: Semantics(
                  label: 'จุดเริ่มต้น: ${_originController.text}',
                  child: Icon(Icons.my_location_rounded, color: isHighContrast ? Colors.white : Colors.blue[800], size: 30),
                ),
              ),
              Positioned(
                left: 235,
                top: 410,
                child: Semantics(
                  label: 'ปลายทาง: ${_destController.text}',
                  child: Icon(Icons.location_on_rounded, color: Colors.red[800], size: 40),
                ),
              ),
              
              // Interactive Accessibility Markers
              if (_filterElevators)
                Positioned(
                  left: 170,
                  top: 320,
                  child: GestureDetector(
                    onTap: () => _showMarkerInfo(context, 'ลิฟต์โดยสาร', 'ลิฟต์สถานีรถไฟฟ้า ใช้งานได้ปกติ กว้าง 1.5 เมตร', Icons.elevator_rounded, Colors.blue[800]!, acc),
                    child: Semantics(
                      button: true,
                      label: 'ข้อมูลลิฟต์',
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: isHighContrast ? Colors.black : Colors.white,
                        child: Icon(Icons.elevator_rounded, color: isHighContrast ? Colors.white : Colors.blue[800], size: 22),
                      ),
                    ),
                  ),
                ),

              if (_filterRamps)
                Positioned(
                  left: 210,
                  top: 380,
                  child: GestureDetector(
                    onTap: () => _showMarkerInfo(context, 'ทางลาด', 'ทางลาดมาตรฐาน ความชัน 1:12 พื้นผิวไม่ลื่น', Icons.accessible_rounded, Colors.teal[800]!, acc),
                    child: Semantics(
                      button: true,
                      label: 'ข้อมูลทางลาด',
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: isHighContrast ? Colors.black : Colors.white,
                        child: Icon(Icons.accessible_rounded, color: isHighContrast ? Colors.white : Colors.teal[800], size: 22),
                      ),
                    ),
                  ),
                ),
            ],
          ],

          // Search Form Card overlay
          Positioned(
            top: 16.0,
            left: 16.0,
            right: 16.0,
            child: MouseRegion(
              onEnter: (_) => toggleMapIframeClickable(false),
              onExit: (_) => toggleMapIframeClickable(true),
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
                  children: [
                    TextField(
                      controller: _originController,
                      style: TextStyle(color: isHighContrast ? Colors.white : Colors.black, fontSize: 16 * acc.fontScale),
                      decoration: InputDecoration(
                        labelText: 'จุดเริ่มต้น',
                        labelStyle: TextStyle(color: isHighContrast ? Colors.white70 : Colors.grey[700]),
                        prefixIcon: const Icon(Icons.location_on, color: Colors.green),
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: isHighContrast ? Colors.white54 : Colors.grey[400]!)),
                      ),
                    ),
                    const SizedBox(height: 12.0),
                    TextField(
                      controller: _destController,
                      style: TextStyle(color: isHighContrast ? Colors.white : Colors.black, fontSize: 16 * acc.fontScale),
                      decoration: InputDecoration(
                        labelText: 'ปลายทาง',
                        labelStyle: TextStyle(color: isHighContrast ? Colors.white70 : Colors.grey[700]),
                        prefixIcon: const Icon(Icons.flag, color: Colors.red),
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: isHighContrast ? Colors.white54 : Colors.grey[400]!)),
                      ),
                    ),
                    const SizedBox(height: 16.0),
                    if (!_isNavigating)
                      SizedBox(
                        width: double.infinity,
                        height: 50.0,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _startNavigation,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isHighContrast ? Colors.white : Colors.blue[800],
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
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        height: 50.0,
                        child: ElevatedButton(
                          onPressed: () {
                            _navigationTimer?.cancel();
                            setState(() {
                              _isNavigating = false;
                              _showRerouteAlert = false;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isHighContrast ? Colors.transparent : Colors.red[50],
                            foregroundColor: isHighContrast ? Colors.white : Colors.red[800],
                            elevation: 0,
                            side: BorderSide(color: isHighContrast ? Colors.white : Colors.red[800]!),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(
                            'ยกเลิกนำทาง',
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

          // Route Info Card
          if (_isNavigating)
            Positioned(
              top: 230,
              right: 16,
              left: 16,
              child: MouseRegion(
                onEnter: (_) => toggleMapIframeClickable(false),
                onExit: (_) => toggleMapIframeClickable(true),
                child: Card(
                color: isHighContrast ? Colors.black : Colors.white,
                elevation: isHighContrast ? 0 : 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: isHighContrast ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Container(
                    constraints: BoxConstraints(
                      maxHeight: _isCardCollapsed
                          ? 60.0
                          : MediaQuery.of(context).size.height * 0.55,
                    ),
                    child: _isCardCollapsed
                        ? InkWell(
                            onTap: () {
                              setState(() {
                                _isCardCollapsed = false;
                              });
                            },
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: isHighContrast ? Colors.white24 : Colors.green[800],
                                  child: Icon(
                                    _liveDirectionIcon,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '🔊 นำทางสด (คลิกเพื่อขยายรายละเอียด)',
                                        style: TextStyle(
                                          color: isHighContrast ? Colors.white70 : Colors.green[900],
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11 * acc.fontScale,
                                        ),
                                      ),
                                      Text(
                                        _liveInstruction,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: isHighContrast ? Colors.white : Colors.black87,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13 * acc.fontScale,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: isHighContrast ? Colors.white70 : Colors.grey[700],
                                  size: 28,
                                ),
                              ],
                            ),
                          )
                        : SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'รายละเอียดการนำทาง',
                                      style: TextStyle(
                                        color: isHighContrast ? Colors.white70 : Colors.grey[700],
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12 * acc.fontScale,
                                      ),
                                    ),
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: Icon(
                                        Icons.keyboard_arrow_up_rounded,
                                        color: isHighContrast ? Colors.white : Colors.black,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _isCardCollapsed = true;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                const Divider(height: 8),
                      // Live Navigation Assistant Panel (Turn-by-turn)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isHighContrast ? Colors.black : Colors.green[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isHighContrast ? Colors.white : Colors.green[800]!,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: isHighContrast ? Colors.white24 : Colors.green[800],
                              child: Icon(
                                _liveDirectionIcon,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '🔊 ระบบนำทางช่วยเหลือสด (Live Navigation)',
                                    style: TextStyle(
                                      color: isHighContrast ? Colors.white70 : Colors.green[900],
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12 * acc.fontScale,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _liveInstruction,
                                    style: TextStyle(
                                      color: isHighContrast ? Colors.white : Colors.black87,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15 * acc.fontScale,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (_remainingDistance > 0)
                                    Text(
                                      'ระยะทางที่เหลือ: $_remainingDistance เมตร',
                                      style: TextStyle(
                                        color: isHighContrast ? Colors.lightGreenAccent : Colors.green[800],
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13 * acc.fontScale,
                                      ),
                                    )
                                  else
                                    Text(
                                      'เลี้ยวได้เลย ณ ตอนนี้!',
                                      style: TextStyle(
                                        color: Colors.red[800],
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13 * acc.fontScale,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'ตัวเลือกการประเมินสิ่งกีดขวาง (A* Pathfinding)',
                        style: TextStyle(
                          color: isHighContrast ? Colors.white : Colors.blue[900],
                          fontWeight: FontWeight.bold,
                          fontSize: 15 * acc.fontScale,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Route Choice 1: Safe Route (Best Way)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedRouteIndex = 0;
                            _score = 0.98;
                          });
                          _drawSelectedRoute();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _selectedRouteIndex == 0
                                ? (isHighContrast ? Colors.white24 : Colors.blue[50])
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _selectedRouteIndex == 0
                                  ? (isHighContrast ? Colors.white : Colors.blue[800]!)
                                  : Colors.grey[300]!,
                              width: _selectedRouteIndex == 0 ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.verified_user_rounded,
                                color: _selectedRouteIndex == 0 ? Colors.green[600] : Colors.grey,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'เส้นทางเลี่ยงสิ่งกีดขวาง',
                                          style: TextStyle(
                                            color: isHighContrast ? Colors.white : Colors.black87,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14 * acc.fontScale,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.green[600],
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'ดีที่สุด (แนะนำ)',
                                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'ระยะทาง: 490 เมตร | เวลา: 7 นาที (ลิฟต์ & ทางลาด 🟢)',
                                      style: TextStyle(
                                        color: isHighContrast ? Colors.white70 : Colors.grey[600],
                                        fontSize: 12 * acc.fontScale,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Route Choice 2: Shortest Unsafe Route
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedRouteIndex = 1;
                            _score = 0.45;
                          });
                          _drawSelectedRoute();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _selectedRouteIndex == 1
                                ? (isHighContrast ? Colors.white24 : Colors.red[50])
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _selectedRouteIndex == 1
                                  ? (isHighContrast ? Colors.white : Colors.red[800]!)
                                  : Colors.grey[300]!,
                              width: _selectedRouteIndex == 1 ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: _selectedRouteIndex == 1 ? Colors.red[600] : Colors.grey,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'เส้นทางดั้งเดิม (ผ่านบันไดปกติ)',
                                          style: TextStyle(
                                            color: isHighContrast ? Colors.white : Colors.black87,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14 * acc.fontScale,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.red[600],
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'มีสิ่งกีดขวาง',
                                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'ระยะทาง: 350 เมตร | เวลา: 5 นาที (บันไดชัน & ลิฟต์เสีย 🔴)',
                                      style: TextStyle(
                                        color: isHighContrast ? Colors.white70 : Colors.grey[600],
                                        fontSize: 12 * acc.fontScale,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_transitRouteData != null) ...[
                        const SizedBox(height: 12),
                        const Divider(color: Colors.grey),
                        const SizedBox(height: 8),
                        Text(
                          '📡 แหล่งข้อมูล: ขนส่งสาธารณะ (GTFS + GTFS-Realtime)',
                          style: TextStyle(
                            color: isHighContrast ? Colors.white : Colors.blue[800],
                            fontWeight: FontWeight.bold,
                            fontSize: 13 * acc.fontScale,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isHighContrast ? Colors.white12 : Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '• สายรถ: ${_transitRouteData!['route']} (รหัสรถ: ${_transitRouteData!['vehicle']})',
                                style: TextStyle(fontSize: 12 * acc.fontScale, fontWeight: FontWeight.bold, color: isHighContrast ? Colors.white : Colors.black87),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '• ตำแหน่งรถล่าสุด: ${_transitRouteData!['next_stop']}',
                                style: TextStyle(fontSize: 12 * acc.fontScale, color: isHighContrast ? Colors.white70 : Colors.black54),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '• รถจะถึงในอีก: ${_transitRouteData!['eta_minutes']} นาที (ดีเลย์เลี่ยงสิ่งกีดขวาง)',
                                style: TextStyle(fontSize: 12 * acc.fontScale, color: Colors.deepOrange, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '• ปลายทางเป้าหมาย: ${_transitRouteData!['destination']}',
                                style: TextStyle(fontSize: 12 * acc.fontScale, color: isHighContrast ? Colors.white70 : Colors.black54),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '📱 แหล่งข้อมูล: GPS โทรศัพท์มือถือผู้ใช้',
                          style: TextStyle(
                            color: isHighContrast ? Colors.white : Colors.green[800],
                            fontWeight: FontWeight.bold,
                            fontSize: 13 * acc.fontScale,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isHighContrast ? Colors.white12 : Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '• ระยะเดินเท้าเฉลี่ยจากพิกัด GPS ปัจจุบันของคุณไปป้าย: ${_transitRouteData!['walk_to_stop']}',
                            style: TextStyle(fontSize: 12 * acc.fontScale, color: isHighContrast ? Colors.white70 : Colors.black87),
                          ),
                        ),
                      ],
                      if (_multiModalOptions != null) ...[
                        const SizedBox(height: 16),
                        const Divider(color: Colors.grey),
                        const SizedBox(height: 8),
                        Text(
                          '🏆 ระบบแนะนำการเดินทางที่เหมาะสมที่สุด (Multi-Modal Recommendation)',
                          style: TextStyle(
                            color: isHighContrast ? Colors.white : Colors.purple[800],
                            fontWeight: FontWeight.bold,
                            fontSize: 14 * acc.fontScale,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildPrefChip('แนะนำสำหรับคุณ', 'balanced', isHighContrast, acc),
                              const SizedBox(width: 6),
                              _buildPrefChip('เร็วที่สุด', 'fastest', isHighContrast, acc),
                              const SizedBox(width: 6),
                              _buildPrefChip('ประหยัดที่สุด', 'cheapest', isHighContrast, acc),
                              const SizedBox(width: 6),
                              _buildPrefChip('เดินน้อยที่สุด', 'least_walking', isHighContrast, acc),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        ..._multiModalOptions!.map((opt) {
                          final isRec = opt['is_recommended'] == true;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isRec
                                  ? (isHighContrast ? Colors.white24 : Colors.green[50])
                                  : (isHighContrast ? Colors.transparent : Colors.grey[50]),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isRec
                                    ? Colors.green[600]!
                                    : Colors.grey[300]!,
                                width: isRec ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      opt['mode'] == 'bus'
                                          ? Icons.directions_bus
                                          : opt['mode'] == 'train'
                                              ? Icons.directions_transit
                                              : opt['mode'] == 'ride_hailing'
                                                  ? Icons.local_taxi
                                                  : Icons.directions_walk,
                                      color: isRec ? Colors.green[700] : (isHighContrast ? Colors.white : Colors.grey[700]),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      opt['mode_name'],
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13 * acc.fontScale,
                                        color: isHighContrast ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (isRec)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.green[600],
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'แนะนำ 🌟',
                                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      )
                                    else
                                      Text(
                                        'คะแนน: ${opt['score']}',
                                        style: TextStyle(fontSize: 11, color: isHighContrast ? Colors.white70 : Colors.grey[600]),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'ราคา: ${opt['price_text']}',
                                      style: TextStyle(fontSize: 11, color: isHighContrast ? Colors.white70 : Colors.black87),
                                    ),
                                    Text(
                                      'เวลา: ${opt['duration_minutes']} นาที',
                                      style: TextStyle(fontSize: 11, color: isHighContrast ? Colors.white70 : Colors.black87),
                                    ),
                                    Text(
                                      'ระยะเดิน: ${opt['walk_distance_meters']} ม.',
                                      style: TextStyle(fontSize: 11, color: isHighContrast ? Colors.white70 : Colors.black87),
                                    ),
                                  ],
                                ),
                                if (isRec) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isHighContrast ? Colors.black54 : Colors.white.withOpacity(0.8),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      opt['reason'],
                                      style: TextStyle(
                                        fontSize: 11 * acc.fontScale,
                                        color: isHighContrast ? Colors.lightGreenAccent : Colors.green[900],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

          // Map Filter Options Toolbar (Chips)
          if (_isNavigating)
            Positioned(
              bottom: 24.0,
              left: 16.0,
              right: 16.0,
              child: MouseRegion(
                onEnter: (_) => toggleMapIframeClickable(false),
                onExit: (_) => toggleMapIframeClickable(true),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('ลิฟต์', Icons.elevator_rounded, _filterElevators, (val) => setState(() => _filterElevators = val), Colors.blue[800]!, isHighContrast, acc),
                      const SizedBox(width: 8),
                      _buildFilterChip('ทางลาด', Icons.accessible_rounded, _filterRamps, (val) => setState(() => _filterRamps = val), Colors.teal[800]!, isHighContrast, acc),
                      const SizedBox(width: 8),
                      _buildFilterChip('ทางนำสายตา', Icons.alt_route_rounded, _filterTactilePaths, (val) => setState(() => _filterTactilePaths = val), Colors.amber[800]!, isHighContrast, acc),
                    ],
                  ),
                ),
              ),
            ),

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
                              'ลิฟต์สถานีบีทีเอสสยามฝั่งตะวันออกขัดข้องชั่วคราว ระบบได้คำนวณเส้นทางใหม่เพื่อใช้ลิฟต์ฝั่งตรงข้ามแทน ต้องการเปลี่ยนเส้นทางหรือไม่?',
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
                                      backgroundColor: isHighContrast ? Colors.white : Colors.blue[800],
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
        ],
      ),
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

  Widget _buildPrefChip(String label, String prefValue, bool isHighContrast, AccessibilityState acc) {
    final isSelected = _selectedPreference == prefValue;
    return GestureDetector(
      onTap: () {
        _updatePreference(prefValue);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isHighContrast ? Colors.white : Colors.purple[800])
              : (isHighContrast ? Colors.transparent : Colors.grey[200]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? (isHighContrast ? Colors.white : Colors.purple[800]!) : Colors.grey[400]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? (isHighContrast ? Colors.black : Colors.white)
                : (isHighContrast ? Colors.white70 : Colors.black87),
            fontSize: 11 * acc.fontScale,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class CityMapPainter extends CustomPainter {
  final bool isHighContrast;
  final double routeProgress;

  CityMapPainter({required this.isHighContrast, required this.routeProgress});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = isHighContrast ? Colors.grey[900]! : const Color(0xFFF0F4F8);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Draw Parks (Green Zones)
    final parkPaint = Paint()..color = isHighContrast ? Colors.green[900]!.withOpacity(0.5) : const Color(0xFFC8E6C9);
    canvas.drawRRect(RRect.fromLTRBR(20, 100, 150, 220, const Radius.circular(16)), parkPaint);
    canvas.drawRRect(RRect.fromLTRBR(size.width - 120, size.height - 300, size.width - 20, size.height - 150, const Radius.circular(16)), parkPaint);

    // Draw Water (Blue path)
    final waterPaint = Paint()
      ..color = isHighContrast ? Colors.blue[900]!.withOpacity(0.5) : const Color(0xFFBBDEFB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 40
      ..strokeCap = StrokeCap.round;
    
    final waterPath = Path()
      ..moveTo(size.width, 100)
      ..quadraticBezierTo(size.width / 2, 150, 0, 300);
    canvas.drawPath(waterPath, waterPaint);

    // Draw Roads
    final mainRoadPaint = Paint()
      ..color = isHighContrast ? Colors.grey[700]! : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.square;

    final roadShadowPaint = Paint()
      ..color = Colors.black.withOpacity(isHighContrast ? 0.0 : 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28
      ..strokeCap = StrokeCap.square;

    final subRoadPaint = Paint()
      ..color = isHighContrast ? Colors.grey[800]! : const Color(0xFFE0E0E0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.square;

    // Main Road (Vertical & Horizontal)
    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), roadShadowPaint);
    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), mainRoadPaint);
    
    canvas.drawLine(Offset(0, size.height * 0.6), Offset(size.width, size.height * 0.6), roadShadowPaint);
    canvas.drawLine(Offset(0, size.height * 0.6), Offset(size.width, size.height * 0.6), mainRoadPaint);

    // Sub Roads
    canvas.drawLine(Offset(size.width * 0.25, 0), Offset(size.width * 0.25, size.height), subRoadPaint);
    canvas.drawLine(Offset(size.width * 0.75, 0), Offset(size.width * 0.75, size.height), subRoadPaint);
    canvas.drawLine(Offset(0, size.height * 0.3), Offset(size.width, size.height * 0.3), subRoadPaint);

    // Draw Buildings
    final buildingPaint = Paint()
      ..color = isHighContrast ? Colors.black : const Color(0xFFFAFAFA)
      ..style = PaintingStyle.fill;
    
    final buildingShadowPaint = Paint()
      ..color = Colors.black.withOpacity(isHighContrast ? 0.5 : 0.1)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    
    final buildingBorderPaint = Paint()
      ..color = isHighContrast ? Colors.white30 : const Color(0xFFE0E0E0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    void drawBuilding(Rect rect) {
      canvas.drawRect(rect.translate(2, 2), buildingShadowPaint);
      canvas.drawRect(rect, buildingPaint);
      canvas.drawRect(rect, buildingBorderPaint);
    }

    drawBuilding(const Rect.fromLTRB(40, 350, 150, 450));
    drawBuilding(Rect.fromLTRB(size.width - 150, 400, size.width - 40, 500));
    drawBuilding(Rect.fromLTRB(size.width / 2 + 30, 150, size.width - 40, 250));
    drawBuilding(const Rect.fromLTRB(40, 500, 120, 600));

    // Draw Labels
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    
    void drawLabel(String text, Offset offset, {bool isMain = false}) {
      textPainter.text = TextSpan(
        text: text,
        style: TextStyle(
          color: isHighContrast ? Colors.white : Colors.grey[700],
          fontSize: isMain ? 16 : 12,
          fontWeight: isMain ? FontWeight.bold : FontWeight.w500,
          backgroundColor: isHighContrast ? Colors.black54 : Colors.white70,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, offset);
    }

    drawLabel('ถนนพระราม 1', Offset(size.width * 0.6, size.height * 0.58), isMain: true);
    drawLabel('ถนนพญาไท', Offset(size.width * 0.52, size.height * 0.15), isMain: true);
    drawLabel('ซอยสยามสแควร์', Offset(size.width * 0.26, size.height * 0.7));
    drawLabel('สวนปทุมวนานุรักษ์', const Offset(40, 150));
    
    // Draw Animated Route Polyline
    if (routeProgress > 0) {
      final routePaint = Paint()
        ..color = isHighContrast ? Colors.white : Colors.blue[600]!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      
      final routeShadowPaint = Paint()
        ..color = Colors.blue[900]!.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10.0
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

      final routePath = Path()
        ..moveTo(110, 260) // Origin
        ..lineTo(110, 320)
        ..lineTo(size.width / 2, 320)
        ..lineTo(size.width / 2, size.height * 0.6)
        ..lineTo(240, size.height * 0.6)
        ..lineTo(240, 420); // Dest

      // Create animated path
      final pathMetrics = routePath.computeMetrics();
      final animatedPath = Path();
      for (final metric in pathMetrics) {
        final extractLength = metric.length * routeProgress;
        animatedPath.addPath(metric.extractPath(0.0, extractLength), Offset.zero);
      }

      canvas.drawPath(animatedPath, routeShadowPaint);
      canvas.drawPath(animatedPath, routePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CityMapPainter oldDelegate) {
    return oldDelegate.isHighContrast != isHighContrast || 
           oldDelegate.routeProgress != routeProgress;
  }
}

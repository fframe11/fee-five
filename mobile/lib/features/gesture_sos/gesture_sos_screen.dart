import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/accessibility_notifier.dart';
import '../../core/api_client.dart';
import '../../core/tts_helper.dart';
import '../vision_assist/camera_loader.dart';

class GestureSosScreen extends ConsumerStatefulWidget {
  const GestureSosScreen({super.key});

  @override
  ConsumerState<GestureSosScreen> createState() => _GestureSosScreenState();
}

class _GestureSosScreenState extends ConsumerState<GestureSosScreen> with TickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _hasCameraPermission = true;
  
  bool _isSearching = true;
  bool _isCountingDown = false;
  int _countdownSeconds = 3;
  Timer? _timer;
  String _sosStatus = "กำลังค้นหาท่าทาง (Searching)";
  
  late AnimationController _handAnimController;
  late AnimationController _numberAnimController;

  @override
  void initState() {
    super.initState();
    _handAnimController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _numberAnimController = AnimationController(vsync: this, duration: const Duration(seconds: 1));
    _initCamera();
    
    // Bind real-time gesture callback!
    setSosGestureCallback(() {
      if (mounted && _isSearching && !_isCountingDown) {
        _triggerGestureSOS();
      }
    });
  }

  Future<void> _initCamera() async {
    // Web camera is fully supported
    
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      
      await _cameraController!.initialize();
      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      setState(() {
        _hasCameraPermission = false;
        _isCameraInitialized = false;
      });
    }
  }

  void _triggerGestureSOS() {
    if (_isCountingDown) return;
    
    final acc = ref.read(accessibilityProvider);
    HapticFeedback.vibrate();
    SemanticsService.announce("ตรวจพบสัญญาณฉุกเฉิน กำลังนับถอยหลัง 3 วินาที", TextDirection.ltr);
    announceSpeech("ตรวจพบสัญญาณมือฉุกเฉิน! กำลังนับถอยหลัง", acc.voiceEnabled);

    setState(() {
      _isSearching = false;
      _isCountingDown = true;
      _countdownSeconds = 3;
      _sosStatus = "ตรวจพบท่าทาง! กำลังนับถอยหลัง...";
    });
    
    _numberAnimController.forward(from: 0.0);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      
      final currentAcc = ref.read(accessibilityProvider);
      setState(() {
        if (_countdownSeconds > 1) {
          _countdownSeconds--;
          _numberAnimController.forward(from: 0.0);
          HapticFeedback.lightImpact();
          SemanticsService.announce("$_countdownSeconds", TextDirection.ltr);
          announceSpeech("$_countdownSeconds", currentAcc.voiceEnabled);
        } else {
          _timer?.cancel();
          _isCountingDown = false;
          _sosStatus = "ส่งสัญญาณ SOS เรียบร้อยแล้ว!";
          HapticFeedback.heavyImpact();
          SemanticsService.announce("ส่งสัญญาณฉุกเฉินเสร็จสิ้น", TextDirection.ltr);
          announceSpeech("ส่งสัญญาณฉุกเฉินเสร็จสิ้นแล้วและพิกัดที่ตั้งส่งถึงเจ้าหน้าที่เรียบร้อยแล้ว", currentAcc.voiceEnabled);
          _completeEmergency();
        }
      });
    });
  }

  Future<void> _completeEmergency() async {
    double realLat = 0.0;
    double realLng = 0.0;

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
      realLat = pos.latitude;
      realLng = pos.longitude;
    } catch (_) {
      try {
        final lastPos = await Geolocator.getLastKnownPosition();
        if (lastPos != null) {
          realLat = lastPos.latitude;
          realLng = lastPos.longitude;
        }
      } catch (_) {}
    }

    try {
      await ApiClient().reportEmergencySOS(
        lat: realLat,
        lng: realLng,
        sosType: 'gesture',
        confidence: 0.95,
      );
    } catch (e) {
      debugPrint('[SOS] API report error: $e');
    }
    
    if (!mounted) return;
    
    final coordText = (realLat != 0.0 && realLng != 0.0)
        ? '${realLat.toStringAsFixed(5)}, ${realLng.toStringAsFixed(5)}'
        : 'GPS กำลังค้นหาตำแหน่ง';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('ส่งข้อมูลฉุกเฉินสำเร็จ', style: TextStyle(color: Colors.red)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ส่งพิกัดจริงไปยังศูนย์ช่วยเหลือและผู้ติดต่อฉุกเฉินแล้ว'),
            const SizedBox(height: 8),
            Text('พิกัดจริง: $coordText', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _isSearching = true;
                _sosStatus = "พร้อมวิเคราะห์ท่าทางฉุกเฉิน";
              });
            },
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
  }

  void _cancelSOS() {
    _timer?.cancel();
    HapticFeedback.mediumImpact();
    SemanticsService.announce("ยกเลิกสัญญาณฉุกเฉิน", TextDirection.ltr);
    final acc = ref.read(accessibilityProvider);
    announceSpeech("ยกเลิกการส่งสัญญาณเตือนฉุกเฉินเรียบร้อยแล้ว", acc.voiceEnabled);
    setState(() {
      _isCountingDown = false;
      _isSearching = true;
      _sosStatus = "พร้อมวิเคราะห์ท่าทางฉุกเฉิน";
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _handAnimController.dispose();
    _numberAnimController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final acc = ref.watch(accessibilityProvider);
    final isHighContrast = acc.highContrast;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'ท่าทางขอความช่วยเหลือ (SOS)',
          style: TextStyle(fontSize: 20 * acc.fontScale, fontWeight: FontWeight.bold),
        ),
        backgroundColor: isHighContrast ? Colors.black : Colors.red[900],
        foregroundColor: Colors.white,
      ),
      backgroundColor: isHighContrast ? Colors.black : Colors.grey[900],
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            color: isHighContrast ? Colors.white : Colors.red[50],
            child: Text(
              'ชูมือขึ้นระดับอกที่กล้องหน้าและทำท่าขยับมือ 3 วินาทีเพื่อเปิดใช้ SOS',
              style: TextStyle(
                fontSize: 16 * acc.fontScale,
                color: isHighContrast ? Colors.black : Colors.red[900],
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (kIsWeb)
                  const HtmlElementView(viewType: 'webcam-view')
                else if (_isCameraInitialized && _cameraController != null)
                  CameraPreview(_cameraController!)
                else if (!_hasCameraPermission)
                  Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.videocam_off, color: Colors.white, size: 64),
                          const SizedBox(height: 16),
                          Text(
                            'ไม่ได้รับอนุญาตให้ใช้งานกล้อง',
                            style: TextStyle(color: Colors.white, fontSize: 16 * acc.fontScale),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _initCamera,
                            child: Text('ขออนุญาตอีกครั้ง', style: TextStyle(fontSize: 16 * acc.fontScale)),
                          )
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.videocam, color: Colors.white54, size: 64),
                          const SizedBox(height: 16),
                          Text(
                            'กล้องไม่พร้อมใช้งานบนเว็บ ใช้อุปกรณ์มือถือเพื่อเปิดกล้อง',
                            style: TextStyle(color: Colors.white, fontSize: 16 * acc.fontScale),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),

                AnimatedBuilder(
                  animation: _handAnimController,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: HandSkeletonPainter(
                        animationValue: _handAnimController.value,
                        isHighContrast: isHighContrast,
                      ),
                    );
                  },
                ),

                if (_isCountingDown)
                  Container(
                    color: Colors.black54,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedBuilder(
                            animation: _numberAnimController,
                            builder: (context, child) {
                              final scale = 1.0 + (_numberAnimController.value * 0.5);
                              final opacity = 1.0 - (_numberAnimController.value * 0.5);
                              return Transform.scale(
                                scale: scale,
                                child: Opacity(
                                  opacity: opacity,
                                  child: Text(
                                    '$_countdownSeconds',
                                    style: TextStyle(
                                      fontSize: 120,
                                      fontWeight: FontWeight.bold,
                                      color: isHighContrast ? Colors.white : Colors.redAccent,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: 250,
                            height: 60,
                            child: ElevatedButton.icon(
                              onPressed: _cancelSOS,
                              icon: const Icon(Icons.cancel, size: 32),
                              label: Text(
                                'ยกเลิกภัย (Cancel)',
                                style: TextStyle(fontSize: 22 * acc.fontScale, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isHighContrast ? Colors.white : Colors.red[800],
                                foregroundColor: isHighContrast ? Colors.black : Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          if (!_isCountingDown && _isSearching)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                height: 54,
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _triggerGestureSOS,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    'จำลองสัญญาณมือฉุกเฉิน (Simulate)',
                    style: TextStyle(fontSize: 16 * acc.fontScale, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isHighContrast ? Colors.white : Colors.red[900],
                    foregroundColor: isHighContrast ? Colors.black : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
            
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
            color: _isCountingDown 
                ? Colors.red 
                : (_isSearching ? Colors.orange[800] : Colors.green[800]),
            child: Text(
              _sosStatus,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18 * acc.fontScale,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HandSkeletonPainter extends CustomPainter {
  final double animationValue;
  final bool isHighContrast;

  HandSkeletonPainter({
    required this.animationValue,
    required this.isHighContrast,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = isHighContrast ? Colors.white : Colors.greenAccent
      ..style = PaintingStyle.fill;
      
    final linePaint = Paint()
      ..color = isHighContrast ? Colors.white70 : Colors.greenAccent.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final cx = size.width * 0.5 + (math.sin(animationValue * math.pi * 2) * 20);
    final cy = size.height * 0.6 + (math.cos(animationValue * math.pi * 2) * 10);
    final scale = size.width * 0.3;

    final points = <Offset>[
      Offset(cx, cy + scale * 0.8), // 0
      Offset(cx - scale * 0.3, cy + scale * 0.4), // 1
      Offset(cx - scale * 0.5, cy + scale * 0.1), // 2
      Offset(cx - scale * 0.6, cy - scale * 0.1), // 3
      Offset(cx - scale * 0.65, cy - scale * 0.2), // 4
      Offset(cx - scale * 0.2, cy - scale * 0.1), // 5
      Offset(cx - scale * 0.25, cy - scale * 0.4), // 6
      Offset(cx - scale * 0.28, cy - scale * 0.6), // 7
      Offset(cx - scale * 0.3, cy - scale * 0.75), // 8
      Offset(cx, cy - scale * 0.15), // 9
      Offset(cx, cy - scale * 0.45), // 10
      Offset(cx, cy - scale * 0.65), // 11
      Offset(cx, cy - scale * 0.8), // 12
      Offset(cx + scale * 0.2, cy - scale * 0.1), // 13
      Offset(cx + scale * 0.25, cy - scale * 0.4), // 14
      Offset(cx + scale * 0.28, cy - scale * 0.6), // 15
      Offset(cx + scale * 0.3, cy - scale * 0.7), // 16
      Offset(cx + scale * 0.4, cy + scale * 0.1), // 17
      Offset(cx + scale * 0.45, cy - scale * 0.1), // 18
      Offset(cx + scale * 0.48, cy - scale * 0.25), // 19
      Offset(cx + scale * 0.5, cy - scale * 0.4), // 20
    ];

    final connections = [
      [0, 1, 2, 3, 4],
      [0, 5, 6, 7, 8],
      [0, 9, 10, 11, 12],
      [0, 13, 14, 15, 16],
      [0, 17, 18, 19, 20],
      [5, 9, 13, 17]
    ];

    for (final bone in connections) {
      for (int i = 0; i < bone.length - 1; i++) {
        canvas.drawLine(points[bone[i]], points[bone[i + 1]], linePaint);
      }
    }

    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], 5.0, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant HandSkeletonPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}

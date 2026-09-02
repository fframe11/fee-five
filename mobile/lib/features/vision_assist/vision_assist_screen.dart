import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/accessibility_notifier.dart';
import '../../core/api_client.dart';
import '../../core/tflite_service.dart';
import '../../core/tts_helper.dart';
import '../../core/risk_engine.dart';
import '../../core/app_colors.dart';
import '../../core/services/vision_trigger.dart';
import '../../core/services/haptic_service.dart';
import 'dart:convert';
import 'camera_loader.dart';

class DetectedObstacle {
  final String label;
  final double score;
  final double x;
  final double y;
  final double w;
  final double h;
  final bool isValid;
  final String? proofReason;

  DetectedObstacle({
    required this.label,
    required this.score,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.isValid = true,
    this.proofReason,
  });

  factory DetectedObstacle.fromJson(Map<String, dynamic> json) {
    String lbl = (json['class'] ?? json['label'] ?? json['name'] ?? 'obstacle').toString().trim();
    double sc = (json['score'] ?? json['confidence'] ?? 0.9).toDouble();
    if (sc > 1.0) sc = sc / 100.0;

    double xVal = 0.3, yVal = 0.3, wVal = 0.4, hVal = 0.4;

    if (json.containsKey('bbox_2d') && json['bbox_2d'] is List) {
      final List<dynamic> bbox = json['bbox_2d'];
      if (bbox.length >= 4) {
        double p0 = (bbox[0] as num).toDouble();
        double p1 = (bbox[1] as num).toDouble();
        double p2 = (bbox[2] as num).toDouble();
        double p3 = (bbox[3] as num).toDouble();

        // Check if scale is 0-1000 (common in Qwen/Vision) or 0-1
        if (p0 > 1.0 || p1 > 1.0 || p2 > 1.0 || p3 > 1.0) {
          p0 /= 1000.0; p1 /= 1000.0; p2 /= 1000.0; p3 /= 1000.0;
        }

        // Qwen vision format: [ymin, xmin, ymax, xmax] or standard [xmin, ymin, xmax, ymax]
        final double minY = math.min(p0, p2).clamp(0.0, 1.0);
        final double maxY = math.max(p0, p2).clamp(0.0, 1.0);
        final double minX = math.min(p1, p3).clamp(0.0, 1.0);
        final double maxX = math.max(p1, p3).clamp(0.0, 1.0);

        xVal = minX;
        yVal = minY;
        wVal = (maxX - minX).clamp(0.05, 1.0);
        hVal = (maxY - minY).clamp(0.05, 1.0);
      }
    } else {
      xVal = (json['x'] ?? 0.3).toDouble();
      yVal = (json['y'] ?? 0.3).toDouble();
      wVal = (json['w'] ?? 0.4).toDouble();
      hVal = (json['h'] ?? 0.4).toDouble();
      if (xVal > 1.0) xVal /= 1000.0;
      if (yVal > 1.0) yVal /= 1000.0;
      if (wVal > 1.0) wVal /= 1000.0;
      if (hVal > 1.0) hVal /= 1000.0;
    }

    // Standard Synonym Normalization only (e.g. column -> pillar)
    String normalizedLabel = lbl.toLowerCase().trim();
    if (normalizedLabel == 'column' || normalizedLabel == 'post' || normalizedLabel == 'pole') {
      normalizedLabel = 'pillar';
    } else {
      normalizedLabel = lbl;
    }

    final bool valid = (json['is_valid'] ?? true) != false;
    final String? reason = json['proof_reason']?.toString();

    return DetectedObstacle(
      label: normalizedLabel,
      score: sc,
      x: xVal,
      y: yVal,
      w: wVal,
      h: hVal,
      isValid: valid,
      proofReason: reason,
    );
  }
}

class VisionAssistScreen extends ConsumerStatefulWidget {
  const VisionAssistScreen({super.key});

  @override
  ConsumerState<VisionAssistScreen> createState() => _VisionAssistScreenState();
}

class _VisionAssistScreenState extends ConsumerState<VisionAssistScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _hasCameraPermission = true;
  bool _isScanning = false;
  bool _isFlashlightOn = false;
  
  late AnimationController _boxAnimController;
  late AnimationController _pulseController;
  
  Timer? _hapticTimer;
  double _simulatedProximity = 0.0; 
  List<DetectedObstacle> _obstacles = [];
  bool _isAnalyzingShot = false;
  DateTime? _lastBarrierReportTime;
  bool _isSavingBarrier = false;
  final FocusNode _keyboardFocusNode = FocusNode();
  
  /// Event-Driven Vision Trigger (ข้อ 8 ของอาจารย์)
  /// Camera เปิดเฉพาะเมื่อ Risk Engine trigger หรือผู้ใช้สั่งเสียง
  final VisionTrigger _visionTrigger = VisionTrigger();
  
  /// Layer 1 On-Device Detection Engine (YOLO / TFLite)
  final TfliteService _tfliteService = TfliteService();
  bool _isTfliteReady = false;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boxAnimController = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..repeat(reverse: true);
    
    _initCamera();
    _initOnDeviceModel();
  }

  Future<void> _initOnDeviceModel() async {
    try {
      await _tfliteService.loadModel();
      if (mounted) {
        setState(() {
          _isTfliteReady = true;
        });
      }
    } catch (e) {
      debugPrint('[Layer 1 YOLO] Model init error: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      _stopSimulation();
      _cameraController?.pausePreview();
    } else if (state == AppLifecycleState.resumed) {
      _cameraController?.resumePreview();
    }
  }
  
  List<CameraDescription> _availableCamerasList = [];
  int _selectedCameraIndex = 0;
  
  Future<void> _initCamera() async {
    try {
      if (!kIsWeb) {
        final status = await Permission.camera.request();
        if (status.isDenied || status.isPermanentlyDenied) {
          if (mounted) {
            setState(() {
              _hasCameraPermission = false;
              _isCameraInitialized = false;
            });
            announceSpeech('กรุณาอนุญาตให้แอป TAM เข้าถึงกล้องถ่ายรูปในการตั้งค่า', true);
          }
          return;
        }
      }

      _availableCamerasList = await availableCameras();
      if (_availableCamerasList.isEmpty) {
        if (mounted) {
          setState(() {
            _hasCameraPermission = false;
            _isCameraInitialized = false;
          });
        }
        return;
      }

      final backCamera = _availableCamerasList.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _availableCamerasList.first,
      );
      _selectedCameraIndex = _availableCamerasList.indexOf(backCamera);
      
      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      
      await _cameraController!.initialize();
      try {
        await _cameraController!.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _hasCameraPermission = true;
          _isCameraInitialized = true;
        });
        // Auto-start scanning immediately for visually impaired users
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && !_isScanning) {
            _startScanning();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasCameraPermission = false;
          _isCameraInitialized = false;
        });
      }
    }
  }

  Future<void> _switchCameraLens() async {
    if (_availableCamerasList.length < 2) return;
    HapticService().turnGuidance();
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _availableCamerasList.length;
    final newCamera = _availableCamerasList[_selectedCameraIndex];
    
    await _cameraController?.dispose();
    _cameraController = CameraController(
      newCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await _cameraController!.initialize();
      if (mounted) setState(() {});
      final acc = ref.read(accessibilityProvider);
      final isBack = newCamera.lensDirection == CameraLensDirection.back;
      announceSpeech(isBack ? 'สลับเป็นกล้องหลังแล้ว' : 'สลับเป็นกล้องหน้าแล้ว', acc.voiceEnabled);
    } catch (_) {}
  }

  void _toggleScan() {
    if (_isScanning) {
      _stopScanning();
    } else {
      _startScanning();
    }
  }

  bool _isProcessingStream = false;

  void _startScanning() {
    setState(() {
      _isScanning = true;
    });
    final acc = ref.read(accessibilityProvider);
    announceSpeech("เปิดกล้องตรวจจับแล้ว กำลังสแกนภาพด้านหน้า", acc.voiceEnabled);
    HapticService().cameraToggle(opening: true);

    if (kIsWeb) {
      _runContinuousScanLoop();
    } else {
      // Use continuous shot loop instead of heavy stream processing on mobile to prevent freezing
      _runContinuousScanLoop();
    }
  }

  void _stopScanning() {
    setState(() {
      _isScanning = false;
      _isAnalyzingShot = false;
      _obstacles = [];
      _simulatedProximity = 0.0;
    });
    if (!kIsWeb && _cameraController != null && _cameraController!.value.isStreamingImages) {
      try {
        _cameraController!.stopImageStream();
      } catch (_) {}
    }
    final acc = ref.read(accessibilityProvider);
    announceSpeech("หยุดสแกนกล้องแล้ว", acc.voiceEnabled);
    HapticService().cameraToggle(opening: false);
  }

  Future<void> _processCameraStream(CameraImage image) async {
    if (!mounted || !_isScanning) return;
    try {
      final tfliteResults = await _tfliteService.detectOnFrame(image);
      if (!mounted || !_isScanning) return;

      List<DetectedObstacle> stage1Candidates = [];
      for (var item in tfliteResults) {
        stage1Candidates.add(DetectedObstacle.fromJson(item));
      }
      
      _updateObstaclesUI(stage1Candidates);
    } catch (e) {
      debugPrint('[Stream processing] error: $e');
    }
  }

  Future<void> _runContinuousScanLoop() async {
    while (mounted && _isScanning) {
      await _executeSingleShotAnalysis();
      if (!mounted || !_isScanning) break;
      await Future.delayed(const Duration(milliseconds: 800));
    }
  }

  /// 📸 2-Layer Detection Pipeline:
  /// Layer 1: Fast Edge Real-Time YOLO / TFLite (On-Device, 100% Offline, Low-latency)
  /// Layer 2: Cloud / Backend Vision AI API (Deep Semantic Context & Thai Voice Reasoning)
  Future<void> _executeSingleShotAnalysis() async {
    if (!mounted || !_isScanning || _isAnalyzingShot) return;
    final acc = ref.read(accessibilityProvider);

    setState(() {
      _isAnalyzingShot = true;
    });

    List<DetectedObstacle> stage1Candidates = [];
    List<DetectedObstacle> proofedDetections = [];

    try {
      String? base64Img = captureFrame();
      if (base64Img == null || base64Img.isEmpty) {
        if (_cameraController != null && _cameraController!.value.isInitialized) {
          try {
            final xFile = await _cameraController!.takePicture();
            final bytes = await xFile.readAsBytes();
            base64Img = base64Encode(bytes);
          } catch (e) {
            debugPrint('[Camera] Take picture error: $e');
          }
        }
      }

      if (base64Img != null && base64Img.isNotEmpty) {
        // =====================================================================
        // 📸 STAGE 1: Fast Edge Candidate Detection (YOLO-World / TFLite)
        // =====================================================================
        try {
          final tfliteResults = await _tfliteService.detectOnBase64(base64Img);
          if (tfliteResults.isNotEmpty) {
            for (var item in tfliteResults) {
              stage1Candidates.add(DetectedObstacle.fromJson(item));
            }
          }
        } catch (e) {
          debugPrint('[Stage 1 YOLO-World] Edge inference error: $e');
        }

        // 🚀 ZERO-LATENCY FAST PATH: Update UI & Haptics immediately (0.05s) from On-Device AI
        if (stage1Candidates.isNotEmpty) {
          _updateObstaclesUI(stage1Candidates);
        }

        // =====================================================================
        // 🧠 STAGE 2: Gemini / Vision AI Proofing (Non-blocking background enhancement)
        // =====================================================================
        try {
          final candidateSummary = stage1Candidates.map((c) => {
            'label': c.label,
            'score': c.score,
            'bbox_2d': [(c.y * 1000).round(), (c.x * 1000).round(), ((c.y + c.h) * 1000).round(), ((c.x + c.w) * 1000).round()]
          }).toList();

          final proofingPrompt = '''You are a Critical Computer Vision Proofing & Verification Engine for visually impaired pedestrian navigation.

STAGE 1 RAW YOLO-WORLD CANDIDATE DETECTIONS:
${jsonEncode(candidateSummary)}

YOUR TASK (STAGE 2 PROOFING & REFINEMENT):
1. Detect physical structures and obstacles in front of the user (such as door, wall, pillar, chair, table, stairs, pothole, curb, barrier, zebra_crossing, intersection, person, vehicle).
2. Proof each candidate detection:
   - If it is a FALSE POSITIVE, DISCARD it with "is_valid": false.
   - If it is a TRUE physical obstacle, CONFIRM it with "is_valid": true.
3. Return ONLY a valid JSON array of objects without extra text:
[
  {"label": "door", "score": 0.90, "is_valid": true, "proof_reason": "พบประตูทางเข้าด้านหน้า", "bbox_2d": [0, 0, 1000, 1000]}
]''';

          final description = await ApiClient().analyzeVisionImage(
            base64Img,
            prompt: proofingPrompt,
          ).timeout(const Duration(milliseconds: 1200));

          String jsonStr = description.trim();
          final startIdx = jsonStr.indexOf('[');
          final endIdx = jsonStr.lastIndexOf(']');
          if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
            jsonStr = jsonStr.substring(startIdx, endIdx + 1);
            final List<dynamic> decoded = jsonDecode(jsonStr);
            final List<DetectedObstacle> cloudVerified = [];
            for (var item in decoded) {
              if (item is Map<String, dynamic>) {
                final isValid = item['is_valid'] ?? true;
                if (isValid == true || isValid == 'true') {
                  cloudVerified.add(DetectedObstacle.fromJson(item));
                }
              }
            }
            if (cloudVerified.isNotEmpty) {
              _updateObstaclesUI(cloudVerified);
            }
          }
        } catch (_) {
          // Fast on-device candidates already active
        }
      }
    } catch (e) {
      debugPrint('[Vision Pipeline] Frame capture error: $e');
    }

    if (mounted && _isScanning && stage1Candidates.isEmpty) {
      setState(() {
        _isAnalyzingShot = false;
      });
    }
  }

  void _updateObstaclesUI(List<DetectedObstacle> proofedDetections) {
    if (!mounted || !_isScanning) return;
    
    final acc = ref.read(accessibilityProvider);
    const profile = 'visual';
    final List<DetectedObstacle> verifiedObstacles = [];
    double maxProximity = 0.0;
    List<String> warningsList = [];

    // Accept all indoor and outdoor obstacles with sensitivity threshold >= 25% (0.25)
    for (var obs in proofedDetections) {
      if (obs.score < 0.25) continue; // Lowered from 0.55 to 0.25 for high sensitivity

      final assessment = AccessibilityRiskEngine.assess(obs, profile);
      verifiedObstacles.add(obs);

      final proximity = assessment.estimatedDistanceMeters;
      final proximityIndex = (10.0 - proximity).clamp(0.0, 10.0) / 10.0;
      if (proximityIndex > maxProximity) {
        maxProximity = proximityIndex;
      }

      if (assessment.warningMessage.isNotEmpty) {
        warningsList.add(assessment.warningMessage);
      }
    }

    setState(() {
      _isAnalyzingShot = false;
      _obstacles = verifiedObstacles;
      _simulatedProximity = verifiedObstacles.isNotEmpty ? maxProximity : 0.0;
    });

    if (warningsList.isNotEmpty) {
      final warningsText = warningsList.toSet().join(' และ ');
      announceSpeech(warningsText, acc.voiceEnabled);
    } else if (verifiedObstacles.isNotEmpty) {
      final labels = verifiedObstacles.map((o) => _getThaiLabel(o.label)).toSet().join(', ');
      final distStr = _formatDistanceText(_getEstimatedDistanceMeters(_simulatedProximity));
      announceSpeech('พบ $labels ด้านหน้า ระยะ $distStr', acc.voiceEnabled);
    }

    if (verifiedObstacles.isNotEmpty) {
      HapticService().obstacleDetected();
    }

    // Auto-save high-hazard obstacles to GIS
    final highHazards = verifiedObstacles.where((o) {
      final l = o.label.toLowerCase();
      return l == 'pothole' || l == 'stairs' || l == 'construction' || l == 'crack' || l == 'pole' || l == 'pillar' || l == 'barrier';
    }).toList();

    if (highHazards.isNotEmpty && _simulatedProximity >= 0.25) {
      final now = DateTime.now();
      if (_lastBarrierReportTime == null || now.difference(_lastBarrierReportTime!).inSeconds > 25) {
        _recordBarrierToGis(specificLabel: highHazards.first.label, isManual: false);
      }
    }
  }

  void _stopSimulation() {
    _hapticTimer?.cancel();
    _hapticTimer = null;
    setState(() {
      _simulatedProximity = 0.0;
      _obstacles = [];
      _isScanning = false;
    });
  }

  double _getEstimatedDistanceMeters(double proximity) {
    if (proximity <= 0.05) return 5.0;
    final dist = 0.38 / (proximity.clamp(0.08, 1.0));
    return (dist * 10).round() / 10.0;
  }

  String _formatDistanceText(double meters) {
    if (meters < 1.0) {
      final cm = (meters * 100).round();
      return '$cm ซม.';
    }
    return '${meters.toStringAsFixed(1)} ม.';
  }

  bool _isActionableObstacleOrFacility(String label) {
    final l = label.toLowerCase();
    // Exclude normal pedestrians / background items from spoken voice alerts
    if (l == 'person' || l == 'people' || l == 'pedestrian' || l == 'tree' || l == 'plant' || l == 'grass') {
      return false;
    }
    return true;
  }

  /// บันทึกอุปสรรคลงฐานข้อมูล GIS (PostGIS) เพื่อจดจำตำแหน่งและแชร์ให้ผู้ใช้ทุกคน
  Future<void> _recordBarrierToGis({String? specificLabel, bool isManual = false}) async {
    if (_isSavingBarrier) return;
    _isSavingBarrier = true;
    _lastBarrierReportTime = DateTime.now();

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      Position pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 4),
        );
      } catch (_) {
        pos = (await Geolocator.getLastKnownPosition()) ??
            Position(
              latitude: 14.8818,
              longitude: 102.0245,
              timestamp: DateTime.now(),
              accuracy: 10.0,
              altitude: 0.0,
              altitudeAccuracy: 0.0,
              heading: 0.0,
              headingAccuracy: 0.0,
              speed: 0.0,
              speedAccuracy: 0.0,
            );
      }

      String targetLabel = specificLabel ?? '';
      if (targetLabel.isEmpty) {
        if (_obstacles.isNotEmpty) {
          final priority = _obstacles.where((o) => _isActionableObstacleOrFacility(o.label)).toList();
          targetLabel = priority.isNotEmpty ? priority.first.label : _obstacles.first.label;
        } else {
          targetLabel = 'obstacle';
        }
      }

      final thaiName = _getThaiLabel(targetLabel);
      final success = await ApiClient().reportBarrier(
        type: targetLabel,
        lat: pos.latitude,
        lng: pos.longitude,
        severity: 'high',
        description: 'ตรวจพบ $thaiName โดยกล้อง AI Vision (พิกัด: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)})',
      );

      if (success) {
        if (mounted) {
          final acc = ref.read(accessibilityProvider);
          if (isManual) {
            announceSpeech('บันทึกตำแหน่ง $thaiName ลงระบบแผนที่ส่วนกลางสำเร็จ', acc.voiceEnabled);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.lightGreenAccent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('📍 บันทึกตำแหน่ง $thaiName ลงฐานข้อมูลแผนที่สำเร็จ (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})'),
                    ),
                  ],
                ),
                backgroundColor: Colors.grey[900],
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _isSavingBarrier = false;
        });
      }
    }
  }
  
  Future<void> _toggleFlashlight() async {
    if (_cameraController == null || !_isCameraInitialized) return;
    
    try {
      if (_isFlashlightOn) {
        await _cameraController!.setFlashMode(FlashMode.off);
      } else {
        await _cameraController!.setFlashMode(FlashMode.torch);
      }
      setState(() {
        _isFlashlightOn = !_isFlashlightOn;
      });
    } catch (e) {
      // Ignore
    }
  }

  String _getThaiLabel(String label) {
    switch (label.toLowerCase().trim()) {
      case 'broken_footpath':
        return 'ทางเท้าชำรุด';
      case 'footpath':
        return 'ทางเท้า';
      case 'obstacle':
        return 'สิ่งกีดขวาง';
      case 'tactile_paving':
        return 'ทางสัมผัสเบรลล์บล็อก';
      case 'traffic_light_green':
        return 'สัญญาณไฟเขียว ข้ามได้';
      case 'traffic_light_red':
        return 'สัญญาณไฟแดง หยุดรอ';
      case 'zebra_crossing':
        return 'ทางม้าลาย';
      case 'intersection':
        return 'ทางแยก';
      case 'pillar':
      case 'pole':
      case 'column':
      case 'post':
        return 'เสา';
      case 'fan':
      case 'electric fan':
      case 'wall fan':
        return 'พัดลม';
      case 'wall':
        return 'ผนัง / กำแพง';
      case 'pothole':
      case 'hole':
      case 'pit':
        return 'หลุมบนทางเดิน';
      case 'stairs':
      case 'step':
      case 'steps':
        return 'บันได';
      case 'ramp':
      case 'wheelchair_ramp':
        return 'ทางลาดชัน';
      case 'curb':
        return 'ขอบทางเท้า';
      case 'bench':
        return 'ม้านั่ง';
      case 'door':
        return 'ประตู';
      case 'chair':
        return 'เก้าอี้';
      case 'table':
      case 'dining table':
        return 'โต๊ะ';
      case 'plug':
      case 'socket':
        return 'ปลั๊กไฟ';
      case 'wire':
      case 'cable':
        return 'สายไฟ';
      case 'person':
      case 'people':
      case 'pedestrian':
        return 'คนเดินเท้า';
      case 'car':
        return 'รถยนต์';
      case 'motorcycle':
        return 'รถจักรยานยนต์';
      case 'bicycle':
        return 'รถจักรยาน';
      case 'elevator':
      case 'lift':
        return 'ลิฟต์';
      case 'crosswalk':
        return 'ทางม้าลาย';
      case 'barrier':
      case 'construction':
        return 'สิ่งกีดขวาง / เขตก่อสร้าง';
      case 'plant':
      case 'tree':
        return 'ต้นไม้ / กระถางต้นไม้';
      case 'window':
      case 'glass':
        return 'หน้าต่างกระจก';
      case 'sticker':
        return 'สติกเกอร์ / ป้ายสัญลักษณ์';
      case 'sign':
      case 'signboard':
        return 'ป้ายข้อความ / ป้ายบอกทาง';
      case 'cctv':
      case 'camera':
        return 'กล้องวงจรปิด';
      default:
        return label;
    }
  }

  String _getWarningText() {
    if (_obstacles.isEmpty) {
      return '🟢 ทางสะดวก (ไม่พบสิ่งกีดขวาง)';
    }

    final distM = _getEstimatedDistanceMeters(_simulatedProximity);
    final distStr = _formatDistanceText(distM);

    // Prioritize direct physical hazards (เสา, บันได, หลุม, ทางต่างระดับ, สิ่งกีดขวาง, ยานพาหนะ)
    const priorityLabels = {
      'pillar', 'pole', 'column', 'post',
      'stairs', 'step', 'steps',
      'pothole', 'hole', 'pit',
      'barrier', 'construction',
      'curb', 'uneven ground',
      'chair', 'table', 'bench',
      'car', 'motorcycle', 'bicycle', 'vehicle'
    };

    final priorityObstacles = _obstacles
        .where((o) => priorityLabels.contains(o.label.toLowerCase().trim()))
        .toList();

    final actionable = priorityObstacles.isNotEmpty
        ? priorityObstacles
        : _obstacles.where((o) => !const {'floor', 'ground', 'plant', 'tree', 'person', 'people'}.contains(o.label.toLowerCase().trim())).toList();

    if (actionable.isEmpty) {
      return '🟢 พื้นทางเดินราบรื่น (ปลอดภัย)';
    }

    final uniqueNames = actionable
        .map((obs) => _getThaiLabel(obs.label))
        .toSet()
        .toList();

    final namesSummary = uniqueNames.join(', ');
    final dangerPrefix = distM <= 1.0 ? '🚨 อันตรายระยะประชิด!' : (distM <= 2.0 ? '⚠️ สังเกตพบ' : 'ℹ️ ตรวจพบ');

    return '$dangerPrefix $namesSummary ด้านหน้า (ห่าง $distStr)';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keyboardFocusNode.dispose();
    _hapticTimer?.cancel();
    _boxAnimController.dispose();
    _pulseController.dispose();
    _cameraController?.dispose();
    _visionTrigger.dispose();
    super.dispose();
  }

  Future<void> _captureAndAnalyze(BuildContext context) async {
    final acc = ref.read(accessibilityProvider);
    
    // 1. Get webcam frame from HTML5 video element or native camera
    String? base64Frame = captureFrame();
    
    if (base64Frame == null || base64Frame.isEmpty) {
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        try {
          final xFile = await _cameraController!.takePicture();
          final bytes = await xFile.readAsBytes();
          base64Frame = base64Encode(bytes);
        } catch (_) {}
      }
    }
    
    if (base64Frame == null || base64Frame.isEmpty) {
      announceSpeech('ไม่สามารถบันทึกภาพจากกล้องได้ กรุณาตรวจสอบการเข้าถึงกล้อง', acc.voiceEnabled);
      return;
    }
    
    // 2. Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: acc.highContrast ? Colors.black : Colors.white,
        shape: RoundedRectangleBorder(
          side: acc.highContrast ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
          borderRadius: BorderRadius.circular(16),
        ),
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 24),
            Expanded(
              child: Text(
                'AI กำลังวิเคราะห์รูปภาพสิ่งกีดขวาง...',
                style: TextStyle(color: acc.highContrast ? Colors.white : Colors.black, fontSize: 16 * acc.fontScale),
              ),
            ),
          ],
        ),
      ),
    );
    
    try {
      // 3. Make HTTP request to backend vision endpoint
      final description = await ApiClient().analyzeVisionImage(base64Frame);
      
      // Close loading dialog
      if (mounted) Navigator.pop(context);
      
      // 4. Speak response out loud
      announceSpeech(description, acc.voiceEnabled);
      
      // 5. Show response dialog
      if (mounted) {
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
                Icon(Icons.psychology_rounded, color: acc.highContrast ? Colors.white : AppColors.getPrimary(acc.colorBlind)),
                const SizedBox(width: 8),
                Text('คำอธิบายจาก AI Vision', style: TextStyle(color: acc.highContrast ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 18 * acc.fontScale)),
              ],
            ),
            content: Text(
              description,
              style: TextStyle(color: acc.highContrast ? Colors.white70 : Colors.black87, fontSize: 16 * acc.fontScale),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('ตกลง', style: TextStyle(color: acc.highContrast ? Colors.white : AppColors.getPrimary(acc.colorBlind), fontSize: 16 * acc.fontScale)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.pop(context);
      
      final errorMsg = "ไม่สามารถเชื่อมต่อระบบวิเคราะห์ภาพ กรุณาเปิดใช้งานและตรวจสอบเซิร์ฟเวอร์หลังบ้าน";
      announceSpeech(errorMsg, acc.voiceEnabled);
      
      if (mounted) {
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
                const Icon(Icons.error_outline_rounded, color: Colors.red),
                const SizedBox(width: 8),
                Text('เกิดข้อผิดพลาด', style: TextStyle(color: acc.highContrast ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 18 * acc.fontScale)),
              ],
            ),
            content: Text(
              errorMsg,
              style: TextStyle(color: acc.highContrast ? Colors.white70 : Colors.black87, fontSize: 16 * acc.fontScale),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('ตกลง', style: TextStyle(color: acc.highContrast ? Colors.white : AppColors.getPrimary(acc.colorBlind), fontSize: 16 * acc.fontScale)),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final acc = ref.watch(accessibilityProvider);
    final isHighContrast = acc.highContrast;
    final primaryColor = AppColors.getPrimary(acc.colorBlind, isHighContrast: isHighContrast);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'ตรวจจับสิ่งกีดขวางแบบเรียลไทม์',
          style: TextStyle(fontSize: 20 * acc.fontScale, fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.flip_camera_ios_rounded, color: Colors.yellowAccent),
            tooltip: 'สลับกล้องหน้า/หลัง',
            onPressed: _switchCameraLens,
          ),
          IconButton(
            icon: Icon(_isFlashlightOn ? Icons.flashlight_on : Icons.flashlight_off),
            tooltip: 'เปิด/ปิดไฟฉาย',
            onPressed: _toggleFlashlight,
          ),
          IconButton(
            icon: const Icon(Icons.psychology_rounded),
            tooltip: 'วิเคราะห์รูปภาพด้วย AI',
            onPressed: () => _captureAndAnalyze(context),
          ),
        ],
      ),
      backgroundColor: isHighContrast ? Colors.black : Colors.black87,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!_hasCameraPermission)
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
                  ExcludeSemantics(
                    excluding: true,
                    child: kIsWeb
                        ? const HtmlElementView(viewType: 'webcam-view')
                        : (_isCameraInitialized && _cameraController != null)
                            ? CameraPreview(_cameraController!)
                            : const SizedBox.shrink(),
                  ),
                
                if (_isScanning)
                  ExcludeSemantics(
                    excluding: true,
                    child: CustomPaint(
                      painter: BoundingBoxPainter(
                        obstacles: _obstacles,
                        proximity: _simulatedProximity,
                        isHighContrast: isHighContrast,
                        fontScale: acc.fontScale,
                      ),
                    ),
                  ),
                

                  
                if (_isScanning)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 115,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Confidence Score Badge (ข้อ 10 ของอาจารย์)
                        if (_obstacles.isNotEmpty && _obstacles.any((o) => _isActionableObstacleOrFacility(o.label)))
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isHighContrast ? Colors.black : Colors.blueGrey[900]?.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(8),
                              border: isHighContrast ? Border.all(color: Colors.white54) : null,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.verified_rounded, color: Colors.lightBlueAccent, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  'Confidence: ${(_obstacles.where((o) => _isActionableObstacleOrFacility(o.label)).fold<double>(0.0, (max, o) => o.score > max ? o.score : max) * 100).toStringAsFixed(0)}%  |  ระยะ: ${_formatDistanceText(_getEstimatedDistanceMeters(_simulatedProximity))}',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12 * acc.fontScale,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Quick Button: Save Barrier to Central GIS Map Database
                          if (_obstacles.isNotEmpty && _isScanning)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: ElevatedButton.icon(
                                onPressed: _isSavingBarrier ? null : () => _recordBarrierToGis(isManual: true),
                                icon: _isSavingBarrier
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.add_location_alt_rounded, color: Colors.amberAccent, size: 16),
                                label: Text(
                                  _isSavingBarrier ? 'กำลังบันทึกพิกัด...' : '📌 บันทึกอุปสรรคนี้ลงแผนที่ส่วนกลาง',
                                  style: TextStyle(
                                    fontSize: 12 * acc.fontScale,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black87,
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.amberAccent, width: 1.2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  elevation: 4,
                                ),
                              ),
                            ),

                          // Dynamic Color Warning Card (Green for Safe, Amber/Red for Hazards)
                          Card(
                            color: isHighContrast
                                ? Colors.black
                                : (_obstacles.isEmpty
                                    ? Colors.green[800]?.withOpacity(0.92)
                                    : (_obstacles.any((o) => const {'pillar', 'pole', 'column', 'stairs', 'pothole', 'hole', 'barrier', 'curb', 'car', 'motorcycle'}.contains(o.label.toLowerCase().trim()))
                                        ? (_simulatedProximity >= 0.5 ? Colors.red[900]?.withOpacity(0.92) : Colors.deepOrange[800]?.withOpacity(0.92))
                                        : Colors.teal[800]?.withOpacity(0.92))),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: isHighContrast ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Text(
                                _getWarningText(),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 18 * acc.fontScale,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ),
                  
                if (_isScanning)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Container(
                          height: 16,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: const [
                                Colors.red,
                                Colors.yellow,
                                Colors.green,
                              ],
                              stops: [
                                (1.0 - _simulatedProximity) * 0.5,
                                (1.0 - _simulatedProximity),
                                1.0,
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Semantics(
        button: true,
        label: _isScanning ? 'ปุ่มหยุดสแกนกล้อง' : 'ปุ่มเริ่มสแกนกล้องตรวจจับสิ่งกีดขวาง',
        hint: 'แตะสองครั้งเพื่อ${_isScanning ? "หยุดสแกน" : "เริ่มสแกน"}',
        child: FloatingActionButton.large(
          heroTag: 'main_vision_scan_fab',
          onPressed: _toggleScan,
          backgroundColor: _isScanning ? Colors.red : (isHighContrast ? Colors.white : primaryColor),
          foregroundColor: _isScanning ? Colors.white : (isHighContrast ? Colors.black : Colors.white),
          tooltip: _isScanning ? 'หยุดสแกน' : 'เริ่มสแกน',
          elevation: 10,
          child: Icon(
            _isScanning ? Icons.stop_rounded : Icons.search_rounded,
            size: 48,
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

class BoundingBoxPainter extends CustomPainter {
  final List<DetectedObstacle> obstacles;
  final double proximity;
  final bool isHighContrast;
  final double fontScale;
  
  BoundingBoxPainter({
    required this.obstacles,
    required this.proximity,
    required this.isHighContrast,
    required this.fontScale,
  });

  String _translateLabel(String label) {
    switch (label.toLowerCase().trim()) {
      // Structural
      case 'pillar':
      case 'column':
      case 'pole':
      case 'post':
        return 'เสา';
      case 'wall':
        return 'ผนัง/กำแพง';
      case 'ceiling':
        return 'เพดาน';
      case 'beam':
        return 'คาน';
      case 'door':
        return 'ประตู';
      case 'window':
        return 'หน้าต่าง';

      // Obstacles & Walking Hazards
      case 'stairs':
      case 'step':
      case 'steps':
        return 'บันได';
      case 'pothole':
      case 'hole':
      case 'pit':
        return 'หลุมบนพื้น';
      case 'crack':
        return 'รอยแตกบนทางเดิน';
      case 'curb':
        return 'ขอบทางเท้า';
      case 'barrier':
      case 'construction':
        return 'แผงกั้น/เขตก่อสร้าง';
      case 'water_puddle':
      case 'puddle':
        return 'แอ่งน้ำขัง';

      // Electrical & Wall Fixtures
      case 'fan':
      case 'wall fan':
      case 'electric fan':
      case 'ceiling fan':
        return 'พัดลม';
      case 'socket':
      case 'plug':
      case 'outlet':
        return 'ปลั๊กไฟ';
      case 'switch':
        return 'สวิตช์ไฟ';
      case 'wire':
      case 'cable':
        return 'สายไฟ';
      case 'ac':
      case 'air conditioner':
        return 'เครื่องปรับอากาศ';

      // Furniture & Common Objects
      case 'chair':
        return 'เก้าอี้';
      case 'table':
      case 'dining table':
      case 'desk':
        return 'โต๊ะ';
      case 'bench':
        return 'ม้านั่ง';
      case 'trash_can':
      case 'bin':
        return 'ถังขยะ';
      case 'bottle':
        return 'ขวดน้ำ';
      case 'cup':
      case 'mug':
        return 'แก้วน้ำ';
      case 'sign':
        return 'ป้ายบอกทาง';

      // Accessibility Facilities
      case 'tactile_paving':
      case 'braille_block':
        return 'เบรลล์บล็อก (ทางคนตาบอด)';
      case 'ramp':
      case 'wheelchair_ramp':
        return 'ทางลาดชัน';
      case 'elevator':
      case 'lift':
        return 'ลิฟต์';
      case 'handrail':
        return 'ราวจับ';
      case 'crosswalk':
        return 'ทางม้าลาย';

      // Dynamic / Living Objects
      case 'person':
      case 'people':
      case 'pedestrian':
        return 'คนเดินเท้า';
      case 'car':
        return 'รถยนต์';
      case 'motorcycle':
        return 'รถจักรยานยนต์';
      case 'bicycle':
        return 'รถจักรยาน';
      case 'dog':
      case 'cat':
      case 'animal':
        return 'สัตว์';
      case 'tree':
      case 'plant':
        return 'ต้นไม้';

      default:
        return label;
    }
  }

  Color _getColorForLabel(String label) {
    final lower = label.toLowerCase().trim();
    const redLabels = {
      'pillar', 'column', 'pole', 'post', 'pothole', 'hole', 'pit',
      'stairs', 'step', 'steps', 'crack', 'barrier', 'construction',
      'wire', 'cable', 'car', 'motorcycle', 'bicycle'
    };
    const greenLabels = {
      'tactile_paving', 'braille_block', 'ramp', 'wheelchair_ramp',
      'elevator', 'lift', 'handrail', 'crosswalk', 'sign'
    };

    if (redLabels.contains(lower)) {
      return Colors.red;
    } else if (greenLabels.contains(lower)) {
      return Colors.green;
    } else {
      return Colors.orange;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (obstacles.isEmpty) return;

    // Draw real-time detected objects!
    for (final ob in obstacles) {
      final rect = Rect.fromLTWH(
        ob.x * size.width,
        ob.y * size.height,
        ob.w * size.width,
        ob.h * size.height,
      );
      final translatedLabel = _translateLabel(ob.label);
      final percent = (ob.score * 100).toInt();
      final color = _getColorForLabel(ob.label);
      
      _drawBox(
        canvas,
        size,
        rect,
        '$translatedLabel ($percent%)',
        color,
      );
    }
  }
  
  void _drawBox(Canvas canvas, Size size, Rect rect, String label, Color color) {
    final paint = Paint()
      ..color = isHighContrast ? Colors.white : color
      ..style = PaintingStyle.stroke
      ..strokeWidth = isHighContrast ? 4.0 : 3.0;
      
    canvas.drawRect(rect, paint);
    
    final bgPaint = Paint()
      ..color = isHighContrast ? Colors.black : color.withOpacity(0.8)
      ..style = PaintingStyle.fill;
      
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 14 * fontScale,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    final textBgRect = Rect.fromLTWH(
      rect.left, 
      rect.top - textPainter.height - 4, 
      textPainter.width + 8, 
      textPainter.height + 4
    );
    
    canvas.drawRect(textBgRect, bgPaint);
    textPainter.paint(canvas, Offset(rect.left + 4, rect.top - textPainter.height - 2));
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) {
    return oldDelegate.proximity != proximity || oldDelegate.isHighContrast != isHighContrast || oldDelegate.obstacles != obstacles;
  }
}

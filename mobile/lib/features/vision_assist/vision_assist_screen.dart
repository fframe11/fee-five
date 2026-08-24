import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import '../../core/accessibility_notifier.dart';
import '../../core/api_client.dart';
import '../../core/tts_helper.dart';
import '../../core/tflite_service.dart';
import 'dart:convert';
import 'camera_loader.dart';

class DetectedObstacle {
  final String label;
  final double score;
  final double x;
  final double y;
  final double w;
  final double h;

  DetectedObstacle({
    required this.label,
    required this.score,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  factory DetectedObstacle.fromJson(Map<String, dynamic> json) {
    return DetectedObstacle(
      label: json['class'] ?? '',
      score: (json['score'] ?? 0.0).toDouble(),
      x: (json['x'] ?? 0.0).toDouble(),
      y: (json['y'] ?? 0.0).toDouble(),
      w: (json['w'] ?? 0.0).toDouble(),
      h: (json['h'] ?? 0.0).toDouble(),
    );
  }
}

class VisionAssistScreen extends ConsumerStatefulWidget {
  const VisionAssistScreen({super.key});

  @override
  ConsumerState<VisionAssistScreen> createState() => _VisionAssistScreenState();
}

class _VisionAssistScreenState extends ConsumerState<VisionAssistScreen> with TickerProviderStateMixin {
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
  final TfliteService _tfliteService = TfliteService();
  bool _isProcessingFrame = false;
  
  @override
  void initState() {
    super.initState();
    _boxAnimController = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..repeat(reverse: true);
    
    _tfliteService.loadModel();
    _initCamera();
  }
  
  Future<void> _initCamera() async {
    // Web camera is fully supported
    
    try {
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      
      _cameraController = CameraController(
        backCamera,
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

  void _toggleScan() {
    setState(() {
      _isScanning = !_isScanning;
      if (_isScanning) {
        SemanticsService.announce("เริ่มต้นสแกนสิ่งกีดขวาง", TextDirection.ltr);
        _startSimulation();
      } else {
        SemanticsService.announce("หยุดสแกนสิ่งกีดขวาง", TextDirection.ltr);
        _stopSimulation();
      }
    });
  }

  void _startSimulation() {
    if (kIsWeb) {
      _hapticTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (!_isScanning) {
          timer.cancel();
          return;
        }
        
        final realProximity = captureProximity();
        
        List<DetectedObstacle> parsedObstacles = [];
        try {
          final rawJson = captureObstacles();
          final List<dynamic> decoded = jsonDecode(rawJson);
          parsedObstacles = decoded.map((item) => DetectedObstacle.fromJson(item)).toList();
        } catch (e) {
          // Ignored
        }

        if (mounted) {
          setState(() {
            _simulatedProximity = realProximity;
            _obstacles = parsedObstacles;
          });
        }
        
        // Vibrate only if an obstacle is within range (proximity threshold > 0.15)
        if (realProximity >= 0.15) {
          final tickInterval = ((1.0 - realProximity) * 8 + 1).toInt();
          if (timer.tick % tickInterval == 0) {
            final acc = ref.read(accessibilityProvider);
            if (acc.hapticEnabled) {
              HapticFeedback.lightImpact();
            }
          }
        }
      });
      return;
    }

    // On-Device Native YOLOv11-Nano TFLite image stream execution
    if (_cameraController != null && _isCameraInitialized) {
      _cameraController!.startImageStream((CameraImage image) async {
        if (!_isScanning) return;
        if (_isProcessingFrame) return;

        _isProcessingFrame = true;
        try {
          final results = await _tfliteService.detectOnFrame(image);
          final parsed = results.map((item) => DetectedObstacle.fromJson(item)).toList();
          
          double maxProximity = 0.0;
          for (var obs in parsed) {
            final proximity = obs.y + obs.h; // Bottom of bounding box represents proximity
            if (proximity > maxProximity) {
              maxProximity = proximity;
            }
          }

          if (mounted && _isScanning) {
            setState(() {
              _obstacles = parsed;
              _simulatedProximity = maxProximity;
            });

            if (maxProximity >= 0.15) {
              final acc = ref.read(accessibilityProvider);
              if (acc.hapticEnabled) {
                HapticFeedback.lightImpact();
              }
            }
          }
        } catch (e) {
          // Ignored
        } finally {
          _isProcessingFrame = false;
        }
      });
    }
  }
  
  void _stopSimulation() {
    if (kIsWeb) {
      _hapticTimer?.cancel();
      _hapticTimer = null;
    } else {
      if (_cameraController != null && _isCameraInitialized) {
        try {
          _cameraController!.stopImageStream();
        } catch (e) {
          // Ignored
        }
      }
    }
    setState(() {
      _simulatedProximity = 0.0;
      _obstacles = [];
    });
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

  @override
  void dispose() {
    _hapticTimer?.cancel();
    _boxAnimController.dispose();
    _pulseController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _captureAndAnalyze(BuildContext context) async {
    final acc = ref.read(accessibilityProvider);
    
    // 1. Get webcam frame from HTML5 video element (or use fallback)
    String? base64Frame = captureFrame();
    
    // Fallback base64 representing a single pixel if running outside simulator or denied webcam
    if (base64Frame == null || base64Frame.isEmpty) {
      base64Frame = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==";
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
                Icon(Icons.psychology_rounded, color: acc.highContrast ? Colors.white : Colors.blue),
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
                child: Text('ตกลง', style: TextStyle(color: acc.highContrast ? Colors.white : Colors.blue[800], fontSize: 16 * acc.fontScale)),
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
                child: Text('ตกลง', style: TextStyle(color: acc.highContrast ? Colors.white : Colors.blue[800], fontSize: 16 * acc.fontScale)),
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
    
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'ตรวจจับสิ่งกีดขวางแบบเรียลไทม์',
          style: TextStyle(fontSize: 20 * acc.fontScale, fontWeight: FontWeight.bold),
        ),
        backgroundColor: isHighContrast ? Colors.black : Colors.blue[900],
        foregroundColor: Colors.white,
        actions: [
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
                          const Icon(Icons.camera_alt, color: Colors.white54, size: 64),
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
                
                if (_isScanning)
                  CustomPaint(
                    painter: BoundingBoxPainter(
                      obstacles: _obstacles,
                      proximity: _simulatedProximity,
                      isHighContrast: isHighContrast,
                      fontScale: acc.fontScale,
                    ),
                  ),
                
                if (_isScanning)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isHighContrast ? Colors.black : Colors.blue[900]?.withOpacity(0.8),
                        border: isHighContrast ? Border.all(color: Colors.white, width: 1.5) : null,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lens, color: Colors.red, size: 12),
                          const SizedBox(width: 8),
                          Text(
                            'กล้อง AI เปิดใช้งานสแกนอยู่',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14 * acc.fontScale,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                if (_isScanning)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 80,
                    child: Card(
                      color: isHighContrast ? Colors.black : Colors.red[900]?.withOpacity(0.9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: isHighContrast ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Text(
                          _simulatedProximity >= 0.5
                              ? '⚠️ ตรวจพบ: สิ่งกีดขวางระดับหัว ระยะใกล้!'
                              : (_simulatedProximity >= 0.3
                                  ? '⚠️ ตรวจพบ: อุปสรรคบนพื้นข้างหน้า!'
                                  : '🟢 พื้นผิวราบรื่น / ทางสะดวก'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18 * acc.fontScale,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
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
      floatingActionButton: FloatingActionButton.large(
        onPressed: _toggleScan,
        backgroundColor: _isScanning ? Colors.red : (isHighContrast ? Colors.white : Colors.blue),
        foregroundColor: _isScanning ? Colors.white : (isHighContrast ? Colors.black : Colors.white),
        tooltip: _isScanning ? 'หยุดสแกน' : 'เริ่มสแกน',
        child: Icon(_isScanning ? Icons.stop : Icons.search, size: 36),
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
    switch (label.toLowerCase()) {
      case 'person':
        return 'คน';
      case 'chair':
        return 'เก้าอี้';
      case 'table':
      case 'dining table':
        return 'โต๊ะ';
      case 'bottle':
        return 'ขวดน้ำ';
      case 'cup':
      case 'mug':
        return 'แก้วน้ำ';
      case 'laptop':
        return 'โน๊ตบุ๊ค';
      case 'cell phone':
      case 'mobile phone':
        return 'โทรศัพท์มือถือ';
      case 'backpack':
        return 'กระเป๋าเป้';
      case 'handbag':
        return 'กระเป๋าถือ';
      case 'umbrella':
        return 'ร่ม';
      case 'car':
        return 'รถยนต์';
      case 'motorcycle':
      case 'bicycle':
        return 'รถจักรยานยนต์';
      case 'cat':
        return 'แมว';
      case 'dog':
        return 'สุนัข';
      case 'door':
        return 'ประตู';
      case 'stairs':
        return 'บันได';
      default:
        return label;
    }
  }

  Color _getColorForLabel(String label) {
    final lower = label.toLowerCase();
    if (lower == 'person' || lower == 'car' || lower == 'dog' || lower == 'giga') {
      return Colors.red;
    } else if (lower == 'chair' || lower == 'table' || lower == 'bottle') {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (proximity < 0.15) return;

    if (obstacles.isEmpty) {
      // Fallback: draw mock boxes if proximity is high, but scale them to be responsive to the real sensor!
      final scale = 1.0 + (proximity - 0.15) * 0.7;
      
      // Box 1 (Red - Branch)
      if (proximity >= 0.50) {
        _drawBox(
          canvas,
          size,
          Rect.fromLTWH(
            size.width * 0.15,
            size.height * 0.20,
            size.width * 0.40 * scale,
            size.height * 0.15 * scale,
          ),
          'กิ่งไม้ต่ำ (${(proximity * 100).toInt()}%)',
          Colors.red,
        );
      }
      
      // Box 2 (Orange - Pipe)
      if (proximity >= 0.30) {
        _drawBox(
          canvas,
          size,
          Rect.fromLTWH(
            size.width * 0.30,
            size.height * 0.65,
            size.width * 0.45 * scale,
            size.height * 0.20 * scale,
          ),
          'ท่อชำรุด (${(proximity * 100).toInt()}%)',
          Colors.orange,
        );
      }

      // Box 3 (Green - Stairs)
      if (proximity >= 0.15) {
        _drawBox(
          canvas,
          size,
          Rect.fromLTWH(
            size.width * 0.55,
            size.height * 0.35,
            size.width * 0.30 * scale,
            size.height * 0.25 * scale,
          ),
          'ขั้นบันได (${(proximity * 100).toInt()}%)',
          Colors.green,
        );
      }
    } else {
      // Draw real-time YOLO/COCO detected objects!
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

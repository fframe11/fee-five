import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:pedometer/pedometer.dart';

enum MovementState {
  stationary,
  walking,
  slowWalking,
  turning,
  gpsUncertain
}

class MovementService {
  static final MovementService _instance = MovementService._internal();
  factory MovementService() => _instance;
  MovementService._internal();

  MovementState _currentState = MovementState.stationary;
  MovementState get currentState => _currentState;

  StreamSubscription? _accelSubscription;
  StreamSubscription? _stepSubscription;
  
  int _lastStepCount = 0;
  DateTime _lastStepTime = DateTime.now();

  final List<double> _accelBuffer = [];
  static const int _bufferSize = 10;
  Timer? _stationaryTimer;

  final _stateController = StreamController<MovementState>.broadcast();
  Stream<MovementState> get stateStream => _stateController.stream;

  void startTracking() {
    if (_accelSubscription != null) return;

    try {
      _stepSubscription = Pedometer.stepCountStream.listen((StepCount event) {
        if (_lastStepCount == 0) {
          _lastStepCount = event.steps;
        } else if (event.steps > _lastStepCount) {
          _lastStepCount = event.steps;
          _lastStepTime = DateTime.now();
          _updateState(MovementState.walking);
          
          _stationaryTimer?.cancel();
          _stationaryTimer = Timer(const Duration(seconds: 3), () {
            _checkStationaryFallback();
          });
        }
      }, onError: (error) {
        debugPrint('[MovementService] Pedometer error: $error');
      });
    } catch (_) {}

    _accelSubscription = userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      final magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      
      _accelBuffer.add(magnitude);
      if (_accelBuffer.length > _bufferSize) {
        _accelBuffer.removeAt(0);
      }

      final avgMagnitude = _accelBuffer.reduce((a, b) => a + b) / _accelBuffer.length;
      final secondsSinceLastStep = DateTime.now().difference(_lastStepTime).inSeconds;

      if (avgMagnitude > 1.2) {
        _updateState(MovementState.walking);
        _stationaryTimer?.cancel();
        _stationaryTimer = Timer(const Duration(seconds: 2), () {
           _checkStationaryFallback();
        });
      } else if (avgMagnitude > 0.6) {
        if (_currentState != MovementState.walking) {
          _updateState(MovementState.slowWalking);
        }
      } else if (secondsSinceLastStep > 2) {
        _updateState(MovementState.stationary);
      }
    });
  }

  void _checkStationaryFallback() {
    if (DateTime.now().difference(_lastStepTime).inSeconds >= 2) {
      _updateState(MovementState.stationary);
    }
  }

  void _updateState(MovementState newState) {
    if (_currentState != newState) {
      _currentState = newState;
      _stateController.add(_currentState);
      debugPrint('[MovementService] State changed to: ${_currentState.name}');
    }
  }

  void stopTracking() {
    _accelSubscription?.cancel();
    _accelSubscription = null;
    _stepSubscription?.cancel();
    _stepSubscription = null;
    _stationaryTimer?.cancel();
    _currentState = MovementState.stationary;
  }
}

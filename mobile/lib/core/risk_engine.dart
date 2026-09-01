import '../features/vision_assist/vision_assist_screen.dart' show DetectedObstacle;

enum RiskLevel { low, medium, high }

class RiskAssessment {
  final DetectedObstacle obstacle;
  final double estimatedDistanceMeters;
  final RiskLevel riskLevel;
  final String warningMessage;

  const RiskAssessment({
    required this.obstacle,
    required this.estimatedDistanceMeters,
    required this.riskLevel,
    required this.warningMessage,
  });
}

class AccessibilityRiskEngine {
  /// Estimate the physical distance to an object based on its bounding box y-coordinate and height.
  /// Bounding boxes are normalized between 0.0 and 1.0.
  static double estimateDistance(DetectedObstacle obstacle) {
    // The lower edge of the bounding box represents where the object contacts the ground
    final bottomY = obstacle.y + obstacle.h;
    
    // Simple geometry projection: Objects closer to the camera are lower in the image frame (Y approaches 1.0)
    // Distance (meters) ~ Constant / (bottomY + small_epsilon)
    if (bottomY >= 0.95) return 0.5; // Very close, under 0.5 meters
    if (bottomY <= 0.10) return 10.0; // Far away, over 10 meters
    
    // Estimate distance curve: y = 1.0 -> 0.5m, y = 0.5 -> 3m, y = 0.2 -> 7m
    final distance = 1.8 / (bottomY - 0.05);
    return double.parse(distance.toStringAsFixed(1));
  }

  /// Assess risk based on the user's impairment profile, estimated distance, and obstacle type
  static RiskAssessment assess(DetectedObstacle obstacle, String impairmentProfile) {
    final distance = estimateDistance(obstacle);
    
    RiskLevel risk = RiskLevel.low;
    String warning = "";

    switch (obstacle.label.toLowerCase()) {
      case 'pothole':
        if (distance < 2.0) {
          risk = RiskLevel.high;
          warning = "ระวังหลุมข้างหน้าระยะ $distance เมตร หลีกเลี่ยงด่วน";
        } else if (distance < 4.0) {
          risk = RiskLevel.medium;
          warning = "มีหลุมข้างหน้าห่างไป $distance เมตร";
        }
        break;

      case 'stairs':
        if (impairmentProfile == 'wheelchair') {
          risk = distance < 3.0 ? RiskLevel.high : RiskLevel.medium;
          warning = "มีบันไดข้างหน้ากั้นทางในระยะ $distance เมตร กรุณาใช้ทางลาดหรือลิฟต์แทน";
        } else if (impairmentProfile == 'visual') {
          risk = distance < 2.0 ? RiskLevel.high : RiskLevel.medium;
          warning = "ระวังบันไดต่างระดับข้างหน้าในระยะ $distance เมตร";
        } else {
          warning = "มีบันไดห่างออกไป $distance เมตร";
        }
        break;

      case 'pole':
      case 'pillar':
      case 'column':
        if (impairmentProfile == 'visual') {
          risk = distance < 2.5 ? RiskLevel.high : RiskLevel.medium;
          warning = "ระวังเสาด้านหน้า ระยะ $distance เมตร";
        } else {
          risk = distance < 2.0 ? RiskLevel.medium : RiskLevel.low;
          warning = "มีเสาข้างหน้า ระยะ $distance เมตร";
        }
        break;

      case 'wall':
      case 'building':
        if (distance < 1.2) {
          risk = RiskLevel.high;
          warning = "ระบุกำแพงหรือสิ่งปลูกสร้างด้านหน้า ระยะ $distance เมตร";
        }
        break;

      case 'chair':
      case 'table':
      case 'bench':
        risk = distance < 2.0 ? RiskLevel.medium : RiskLevel.low;
        warning = "พบโต๊ะหรือเก้าอี้ขวางทาง ระยะ $distance เมตร";
        break;

      case 'curb':
      case 'uneven ground':
        risk = RiskLevel.medium;
        warning = "ระวังขอบทางเท้าหรือทางต่างระดับ ระยะ $distance เมตร";
        break;

      case 'wire':
      case 'cable':
        risk = distance < 1.5 ? RiskLevel.medium : RiskLevel.low;
        warning = "ระวังสายไฟกีดขวางด้านหน้า ระยะ $distance เมตร";
        break;

      case 'tree':
      case 'plant':
        risk = distance < 2.0 ? RiskLevel.medium : RiskLevel.low;
        warning = "มีต้นไม้หรือกระถางต้นไม้ด้านหน้า ระยะ $distance เมตร";
        break;

      case 'car':
      case 'motorcycle':
      case 'vehicle':
        risk = distance < 3.5 ? RiskLevel.high : RiskLevel.medium;
        warning = "ระวังยานพาหนะด้านหน้า ระยะ $distance เมตร";
        break;

      case 'ramp':
        if (impairmentProfile == 'wheelchair') {
          warning = "มีทางลาดข้างหน้าห่างไป $distance เมตร";
        } else if (impairmentProfile == 'visual') {
          risk = distance < 2.0 ? RiskLevel.medium : RiskLevel.low;
          warning = "มีทางลาดชันต่างระดับอยู่ข้างหน้า ระยะ $distance เมตร";
        }
        break;

      case 'elevator':
      case 'lift':
        warning = "พบลิฟต์โดยสารทางด้านหน้า ระยะ $distance เมตร";
        break;

      case 'door':
        warning = "มีประตูอยู่ข้างหน้าคุณ ระยะ $distance เมตร";
        break;

      case 'intersection':
        risk = distance < 3.0 ? RiskLevel.high : RiskLevel.medium;
        warning = distance < 3.0 
            ? "อันตรายถึงทางแยกแล้ว ระวังรถซ้ายขวา"
            : "มีทางแยกอยู่ข้างหน้า ระยะ $distance เมตร";
        break;

      case 'zebra_crossing':
        risk = distance < 3.0 ? RiskLevel.high : RiskLevel.medium;
        warning = distance < 3.0
            ? "ถึงทางม้าลายแล้ว ข้ามถนนด้วยความระมัดระวัง"
            : "มีทางม้าลายอยู่ข้างหน้า ระยะ $distance เมตร";
        break;

      default:
        if (distance < 3.0) {
          risk = distance < 1.5 ? RiskLevel.high : RiskLevel.medium;
          warning = "พบสิ่งกีดขวาง (${obstacle.label}) ข้างหน้า ระยะ $distance เมตร";
        }
    }

    return RiskAssessment(
      obstacle: obstacle,
      estimatedDistanceMeters: distance,
      riskLevel: risk,
      warningMessage: warning,
    );
  }
}

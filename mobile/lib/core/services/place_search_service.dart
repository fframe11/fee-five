import 'dart:convert';
import 'package:http/http.dart' as http;
import '../api_client.dart';

class PlaceResult {
  final String name;
  final String displayName;
  final String category;
  final double lat;
  final double lon;

  const PlaceResult({
    required this.name,
    required this.displayName,
    required this.category,
    required this.lat,
    required this.lon,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'display_name': displayName,
    'category': category,
    'lat': lat,
    'lon': lon,
  };
}

class PlaceSearchService {
  static const List<Map<String, dynamic>> _embeddedPlaces = [
    {
      'name': 'อาคารเรียนรวม 1 (B1 / Lecture 1)',
      'display_name': 'อาคารเรียนรวม 1 (B1), มหาวิทยาลัยเทคโนโลยีสุรนารี, นครราชสีมา',
      'category': 'campus',
      'lat': 14.8778,
      'lon': 102.0156,
      'aliases': ['อาคารเรียนรวม 1', 'อาคารเรียนรวม1', 'เรียนรวม 1', 'เรียนรวม1', 'b1', 'lecture 1', 'ตึก b1', 'ตึกเรียนรวม 1', 'อาคาร b1'],
    },
    {
      'name': 'อาคารเรียนรวม 2 (B2 / Lecture 2)',
      'display_name': 'อาคารเรียนรวม 2 (B2), มหาวิทยาลัยเทคโนโลยีสุรนารี, นครราชสีมา',
      'category': 'campus',
      'lat': 14.8765,
      'lon': 102.0148,
      'aliases': ['อาคารเรียนรวม 2', 'อาคารเรียนรวม2', 'เรียนรวม 2', 'เรียนรวม2', 'b2', 'lecture 2', 'ตึก b2', 'ตึกเรียนรวม 2', 'อาคาร b2'],
    },
    {
      'name': 'อาคารสุรพัฒน์ 1 (เทคโนธานี / Technopolis 1)',
      'display_name': 'อาคารสุรพัฒน์ 1, เทคโนธานี, มทส., นครราชสีมา',
      'category': 'campus',
      'lat': 14.8710,
      'lon': 102.0238,
      'aliases': ['สุรพัฒน์ 1', 'สุรพัฒน์1', 'อาคารสุรพัฒน์ 1', 'อาคารสุรพัฒน์1', 'เทคโนธานี 1', 'technopolis 1', 'technopolis'],
    },
    {
      'name': 'อาคารสุรพัฒน์ 2 (เทคโนธานี / Technopolis 2)',
      'display_name': 'อาคารสุรพัฒน์ 2, เทคโนธานี, มทส., นครราชสีมา',
      'category': 'campus',
      'lat': 14.8715,
      'lon': 102.0245,
      'aliases': ['สุรพัฒน์ 2', 'สุรพัฒน์2', 'อาคารสุรพัฒน์ 2', 'อาคารสุรพัฒน์2', 'เทคโนธานี 2', 'technopolis 2'],
    },
    {
      'name': 'อาคารบรรณสารและสื่อการศึกษา (หอสมุด มทส.)',
      'display_name': 'อาคารบรรณสารและสื่อการศึกษา (หอสมุดกลาง), มทส., นครราชสีมา',
      'category': 'campus',
      'lat': 14.8795,
      'lon': 102.0162,
      'aliases': ['หอสมุด', 'บรรณสาร', 'ห้องสมุด มทส', 'ห้องสมุด', 'หอสมุดกลาง', 'library sut', 'sut library'],
    },
    {
      'name': 'อาคารบริหาร (สิริวิทยลักษณ์ / สำนักงานอธิการบดี)',
      'display_name': 'อาคารบริหาร (สิริวิทยลักษณ์), มหาวิทยาลัยเทคโนโลยีสุรนารี',
      'category': 'campus',
      'lat': 14.8812,
      'lon': 102.0122,
      'aliases': ['อาคารบริหาร', 'ตึกบริหาร', 'สิริวิทยลักษณ์', 'สำนักงานอธิการบดี', 'อธิการบดี', 'อาคารสิริวิทยลักษณ์'],
    },
    {
      'name': 'โรงพยาบาลมหาวิทยาลัยเทคโนโลยีสุรนารี (รพ.มทส.)',
      'display_name': 'โรงพยาบาล มทส., ถ.มหาวิทยาลัย, ต.สุรนารี, อ.เมืองนครราชสีมา',
      'category': 'hospital',
      'lat': 14.8912,
      'lon': 102.0085,
      'aliases': ['รพ.มทส', 'รพ มทส', 'โรงพยาบาลมทส', 'โรงพยาบาล มทส', 'โรงพยาบาลมหาวิทยาลัยเทคโนโลยีสุรนารี', 'sut hospital'],
    },
    {
      'name': 'ศูนย์บริการการศึกษา (ตึกทะเบียน มทส. / CES)',
      'display_name': 'ศูนย์บริการการศึกษา (CES), มหาวิทยาลัยเทคโนโลยีสุรนารี',
      'category': 'campus',
      'lat': 14.8808,
      'lon': 102.0130,
      'aliases': ['ศูนย์บริการการศึกษา', 'ทะเบียน', 'ตึกทะเบียน', 'ces', 'ces sut'],
    },
    {
      'name': 'อาคารเฉลิมพระเกียรติ 80 พรรษา',
      'display_name': 'อาคารเฉลิมพระเกียรติ 80 พรรษา, มทส., นครราชสีมา',
      'category': 'campus',
      'lat': 14.8782,
      'lon': 102.0180,
      'aliases': ['80 พรรษา', 'อาคาร 80 พรรษา', 'เฉลิมพระเกียรติ 80 พรรษา', 'อาคารเฉลิมพระเกียรติ 80 พรรษา'],
    },
    {
      'name': 'อาคารวิชาการ 1 (F1)',
      'display_name': 'อาคารวิชาการ 1 (F1), สำนักวิชาวิศวกรรมศาสตร์ มทส.',
      'category': 'campus',
      'lat': 14.8790,
      'lon': 102.0135,
      'aliases': ['วิชาการ 1', 'วิชาการ1', 'f1', 'ตึก f1', 'อาคาร f1', 'อาคารวิชาการ 1'],
    },
    {
      'name': 'อาคารวิชาการ 2 (F2)',
      'display_name': 'อาคารวิชาการ 2 (F2), มทส., นครราชสีมา',
      'category': 'campus',
      'lat': 14.8798,
      'lon': 102.0142,
      'aliases': ['วิชาการ 2', 'วิชาการ2', 'f2', 'ตึก f2', 'อาคาร f2', 'อาคารวิชาการ 2'],
    },
    {
      'name': 'อาคารศูนย์เครื่องมือ 1 (F3)',
      'display_name': 'อาคารเครื่องมือ 1 (F3), มทส., นครราชสีมา',
      'category': 'campus',
      'lat': 14.8802,
      'lon': 102.0148,
      'aliases': ['เครื่องมือ 1', 'เครื่องมือ1', 'f3', 'ตึก f3', 'อาคาร f3', 'อาคารเครื่องมือ 1'],
    },
    {
      'name': 'อาคารศูนย์เครื่องมือ 2 (F4)',
      'display_name': 'อาคารเครื่องมือ 2 (F4), มทส., นครราชสีมา',
      'category': 'campus',
      'lat': 14.8806,
      'lon': 102.0152,
      'aliases': ['เครื่องมือ 2', 'เครื่องมือ2', 'f4', 'ตึก f4', 'อาคาร f4', 'อาคารเครื่องมือ 2'],
    },
    {
      'name': 'อาคารศูนย์เครื่องมือ 3 (F5)',
      'display_name': 'อาคารเครื่องมือ 3 (F5), มทส., นครราชสีมา',
      'category': 'campus',
      'lat': 14.8810,
      'lon': 102.0158,
      'aliases': ['เครื่องมือ 3', 'เครื่องมือ3', 'f5', 'ตึก f5', 'อาคาร f5', 'อาคารเครื่องมือ 3'],
    },
    {
      'name': 'สุรสัมมนาคาร (Surasammanakhan Hotel)',
      'display_name': 'สุรสัมมนาคาร, มหาวิทยาลัยเทคโนโลยีสุรนารี, นครราชสีมา',
      'category': 'campus',
      'lat': 14.8732,
      'lon': 102.0210,
      'aliases': ['สุรสัมมนาคาร', 'โรงแรมมทส', 'โรงแรม มทส', 'surasammanakhan'],
    },
    {
      'name': 'ศูนย์กีฬาและสุขภาพ มทส. (Sports Center)',
      'display_name': 'ศูนย์กีฬาและสุขภาพ, มทส., นครราชสีมา',
      'category': 'campus',
      'lat': 14.8725,
      'lon': 102.0185,
      'aliases': ['ศูนย์กีฬา', 'ศูนย์กีฬามทส', 'สระว่ายน้ำ มทส', 'ยิม มทส', 'sports center'],
    },
    {
      'name': 'หอพักสุรนิเวศ (หอพักนักศึกษา มทส.)',
      'display_name': 'กลุ่มอาคารหอพักสุรนิเวศ, มหาวิทยาลัยเทคโนโลยีสุรนารี',
      'category': 'campus',
      'lat': 14.8750,
      'lon': 102.0205,
      'aliases': ['หอพัก', 'สุรนิเวศ', 'หอใน มทส', 'หอใน', 'หอพักสุรนิเวศ', 'หอพัก มทส'],
    },
    {
      'name': 'ประตู 1 มทส. (ทางเข้าหลัก ถ.มหาวิทยาลัย)',
      'display_name': 'ซุ้มประตู 1 มทส., ถ.มหาวิทยาลัย, นครราชสีมา',
      'category': 'campus',
      'lat': 14.8845,
      'lon': 102.0110,
      'aliases': ['ประตู 1', 'ประตู1', 'ประตู 1 มทส', 'ประตู1 มทส', 'ทางเข้า มทส'],
    },
    {
      'name': 'ประตู 2 มทส. (ประตูสุรนารีวิทยา / เทคโนธานี)',
      'display_name': 'ประตู 2 มทส., ทางเข้าเทคโนธานี, นครราชสีมา',
      'category': 'campus',
      'lat': 14.8690,
      'lon': 102.0280,
      'aliases': ['ประตู 2', 'ประตู2', 'ประตู 2 มทส', 'ประตู2 มทส', 'ประตูเทคโนธานี'],
    },
    {
      'name': 'ประตู 3 มทส. (ประตูโคกกรวด)',
      'display_name': 'ประตู 3 มทส. (ฝั่งโคกกรวด), นครราชสีมา',
      'category': 'campus',
      'lat': 14.8980,
      'lon': 102.0080,
      'aliases': ['ประตู 3', 'ประตู3', 'ประตู 3 มทส', 'ประตูโคกกรวด'],
    },
    {
      'name': 'ประตู 4 มทส. (ประตูโรงพยาบาล มทส.)',
      'display_name': 'ประตู 4 มทส. (ทางเข้า รพ.มทส), นครราชสีมา',
      'category': 'campus',
      'lat': 14.8905,
      'lon': 102.0065,
      'aliases': ['ประตู 4', 'ประตู4', 'ประตู 4 มทส', 'ประตู รพ.มทส'],
    },

    // Major Nakhon Ratchasima / Korat Landmarks
    {
      'name': 'เดอะมอลล์ โคราช (The Mall Korat)',
      'display_name': 'เดอะมอลล์ โคราช, ถ.มิตรภาพ, อ.เมืองนครราชสีมา, 30000',
      'category': 'landmark',
      'lat': 14.9785,
      'lon': 102.0725,
      'aliases': ['เดอะมอลล์', 'เดอะมอลล์ โคราช', 'the mall', 'the mall korat'],
    },
    {
      'name': 'เซ็นทรัล โคราช (Central Korat)',
      'display_name': 'เซ็นทรัล โคราช, ถ.มิตรภาพ, อ.เมืองนครราชสีมา, 30000',
      'category': 'landmark',
      'lat': 14.9965,
      'lon': 102.1155,
      'aliases': ['เซ็นทรัล', 'เซ็นทรัล โคราช', 'central', 'central korat'],
    },
    {
      'name': 'เทอร์มินอล 21 โคราช (Terminal 21 Korat)',
      'display_name': 'เทอร์มินอล 21 โคราช, ถ.มิตรภาพ, อ.เมืองนครราชสีมา, 30000',
      'category': 'landmark',
      'lat': 14.9818,
      'lon': 102.0968,
      'aliases': ['เทอร์มินอล', 'เทอร์มินอล 21', 'terminal 21', 'terminal 21 korat'],
    },
    {
      'name': 'โรงพยาบาลมหาราชนครราชสีมา',
      'display_name': 'โรงพยาบาลมหาราชนครราชสีมา, ถ.ช้างเผือก, อ.เมืองนครราชสีมา',
      'category': 'hospital',
      'lat': 14.9875,
      'lon': 102.1120,
      'aliases': ['รพ.มหาราช', 'มหาราช', 'โรงพยาบาลมหาราช', 'โรงพยาบาลมหาราชนครราชสีมา'],
    },
    {
      'name': 'อนุสาวรีย์ท้าวสุรนารี (ลานย่าโม)',
      'display_name': 'อนุสาวรีย์ท้าวสุรนารี, ถ.ราชดำเนิน, ต.ในเมือง, อ.เมืองนครราชสีมา',
      'category': 'landmark',
      'lat': 14.9740,
      'lon': 102.1008,
      'aliases': ['ย่าโม', 'ลานย่าโม', 'ท้าวสุรนารี', 'อนุสาวรีย์ท้าวสุรนารี'],
    },
    {
      'name': 'สถานีขนส่งผู้โดยสารนครราชสีมา แห่งที่ 2 (บขส.ใหม่)',
      'display_name': 'บขส.ใหม่ โคราช, ถ.มิตรภาพ-หนองคาย, นครราชสีมา',
      'category': 'transit',
      'lat': 14.9912,
      'lon': 102.1050,
      'aliases': ['บขส', 'บขสใหม่', 'บขส.ใหม่', 'สถานีขนส่งโคราช', 'บขส 2'],
    },
    {
      'name': 'สถานีรถไฟนครราชสีมา',
      'display_name': 'สถานีรถไฟนครราชสีมา (หัวรถไฟ), อ.เมืองนครราชสีมา',
      'category': 'transit',
      'lat': 14.9725,
      'lon': 102.0805,
      'aliases': ['สถานีรถไฟ', 'สถานีรถไฟโคราช', 'หัวรถไฟ', 'สถานีรถไฟนครราชสีมา'],
    },
    {
      'name': 'มหาวิทยาลัยเทคโนโลยีสุรนารี (มทส.)',
      'display_name': 'มหาวิทยาลัยเทคโนโลยีสุรนารี, 111 ถ.มหาวิทยาลัย, นครราชสีมา',
      'category': 'campus',
      'lat': 14.8812,
      'lon': 102.0122,
      'aliases': ['มทส', 'มทส.', 'สุรนารี', 'sut', 'suranaree university'],
    },

    // Villages & Communities (หมู่บ้านและชุมชนใกล้เคียง)
    {
      'name': 'หมู่บ้านอยู่ดีเฮาส์ (อยู่ดีเฮ้าส์ มทส.)',
      'display_name': 'หมู่บ้านอยู่ดีเฮ้าส์ (You Dee House), ถ.มหาวิทยาลัย, ต.สุรนารี, อ.เมืองนครราชสีมา',
      'category': 'residential',
      'lat': 14.8885,
      'lon': 102.0285,
      'aliases': [
        'อยู่ดีเฮาส์', 'อยู่ดีเฮ้าส์', 'หมู่บ้านอยู่ดีเฮาส์', 'หมู่บ้านอยู่ดีเฮ้าส์',
        'you dee house', 'udee house', 'u-dee house', 'อยู่ดีเฮ้าส์ มทส', 'อยู่ดีเฮาส์ มทส'
      ],
    },
    {
      'name': 'หมู่บ้านสุรสวัสดิ์',
      'display_name': 'หมู่บ้านสุรสวัสดิ์, ต.สุรนารี, อ.เมืองนครราชสีมา, นครราชสีมา',
      'category': 'residential',
      'lat': 14.9125,
      'lon': 102.0680,
      'aliases': ['หมู่บ้านสุรสวัสดิ์', 'สุรสวัสดิ์', 'ชุมชนสุรสวัสดิ์', 'surasawat', 'surasawat village'],
    },
    {
      'name': 'หมู่บ้านสุรสวัสดิ์ (ประตูทางเข้า)',
      'display_name': 'ประตูทางเข้าหมู่บ้านสุรสวัสดิ์, ต.สุรนารี, อ.เมืองนครราชสีมา',
      'category': 'residential',
      'lat': 14.9085,
      'lon': 102.0715,
      'aliases': ['ทางเข้าหมู่บ้านสุรสวัสดิ์', 'ป้อมยามสุรสวัสดิ์'],
    },
    {
      'name': 'หมู่บ้านสุรนารีวิลล์',
      'display_name': 'หมู่บ้านสุรนารีวิลล์, ต.สุรนารี, อ.เมืองนครราชสีมา',
      'category': 'residential',
      'lat': 14.8940,
      'lon': 102.0420,
      'aliases': ['สุรนารีวิลล์', 'หมู่บ้านสุรนารีวิลล์', 'suranaree ville'],
    },
    {
      'name': 'หมู่บ้านการเคหะแห่งชาติ นครราชสีมา (เคหะเซฟวัน)',
      'display_name': 'การเคหะฯ นครราชสีมา, ถ.มิตรภาพ, ต.ในเมือง, อ.เมืองนครราชสีมา',
      'category': 'residential',
      'lat': 14.9450,
      'lon': 102.0480,
      'aliases': ['เคหะ', 'เคหะโคราช', 'เคหะเซฟวัน', 'การเคหะ', 'หมู่บ้านการเคหะ'],
    },
    {
      'name': 'หมู่บ้านราชพฤกษ์ ประโดก',
      'display_name': 'หมู่บ้านราชพฤกษ์, ต.หมื่นไวย, อ.เมืองนครราชสีมา',
      'category': 'residential',
      'lat': 14.9910,
      'lon': 102.0950,
      'aliases': ['ราชพฤกษ์', 'หมู่บ้านราชพฤกษ์'],
    },
    {
      'name': 'หมู่บ้านสราญสิริ โคราช',
      'display_name': 'หมู่บ้านสราญสิริ, ถ.บายพาส, ต.ปรุใหญ่, อ.เมืองนครราชสีมา',
      'category': 'residential',
      'lat': 14.9210,
      'lon': 102.0350,
      'aliases': ['สราญสิริ', 'หมู่บ้านสราญสิริ'],
    },
    {
      'name': 'หมู่บ้านโฮมการ์เด้นวิลล์ สุรนารายณ์',
      'display_name': 'หมู่บ้านโฮมการ์เด้นวิลล์, ถ.สุรนารายณ์, ต.จอหอ, อ.เมืองนครราชสีมา',
      'category': 'residential',
      'lat': 15.0120,
      'lon': 102.1250,
      'aliases': ['โฮมการ์เด้นวิลล์', 'โฮมการ์เด้น', 'home garden ville'],
    },

    // SUT Gates & Facilities (ประตูและจุดสำคัญ มทส.)
    {
      'name': 'ประตู 1 มทส. (ประตูหลัก / Main Gate)',
      'display_name': 'ประตู 1 (ทางเข้าหลัก ถ.มหาวิทยาลัย), มหาวิทยาลัยเทคโนโลยีสุรนารี',
      'category': 'transit',
      'lat': 14.8985,
      'lon': 102.0150,
      'aliases': ['ประตู 1', 'ประตู1', 'ประตูใหญ่ มทส', 'ประตูหน้า มทส', 'gate 1 sut'],
    },
    {
      'name': 'ประตู 2 มทส. (ประตูสุรนารี / ทางไป รพ.มทส.)',
      'display_name': 'ประตู 2 มทส., ถ.มหาวิทยาลัย, ต.สุรนารี, นครราชสีมา',
      'category': 'transit',
      'lat': 14.8930,
      'lon': 102.0060,
      'aliases': ['ประตู 2', 'ประตู2', 'ประตู รพ.มทส', 'gate 2 sut'],
    },
    {
      'name': 'ประตู 3 มทส. (ประตูกัลปพฤกษ์ / ทางไป ถ. 304)',
      'display_name': 'ประตู 3 (กัลปพฤกษ์), มหาวิทยาลัยเทคโนโลยีสุรนารี',
      'category': 'transit',
      'lat': 14.8620,
      'lon': 102.0220,
      'aliases': ['ประตู 3', 'ประตู3', 'ประตูกัลปพฤกษ์', 'gate 3 sut'],
    },
    {
      'name': 'ประตู 4 มทส. (ประตูเทคโนธานี)',
      'display_name': 'ประตู 4 (เทคโนธานี), มหาวิทยาลัยเทคโนโลยีสุรนารี',
      'category': 'transit',
      'lat': 14.8680,
      'lon': 102.0310,
      'aliases': ['ประตู 4', 'ประตู4', 'gate 4 sut'],
    },
    {
      'name': 'อาคารวิชาการ 1-2 (F1-F2 มทส.)',
      'display_name': 'อาคารวิชาการ 1 และ 2 (F1, F2), สำนักวิชาวิทยาศาสตร์และวิศวกรรมศาสตร์, มทส.',
      'category': 'campus',
      'lat': 14.8785,
      'lon': 102.0140,
      'aliases': ['f1', 'f2', 'ตึก f1', 'ตึก f2', 'อาคารวิชาการ 1', 'อาคาร f1'],
    },
    {
      'name': 'อาคารวิชาการ 3-4 (F3-F4 มทส.)',
      'display_name': 'อาคารวิชาการ 3 และ 4 (F3, F4), สำนักวิชาเทคโนโลยีการเกษตร, มทส.',
      'category': 'campus',
      'lat': 14.8770,
      'lon': 102.0135,
      'aliases': ['f3', 'f4', 'ตึก f3', 'ตึก f4', 'อาคาร f3'],
    },
    {
      'name': 'อาคารวิชาการ 5-6 (F5-F6 มทส.)',
      'display_name': 'อาคารวิชาการ 5 และ 6 (F5, F6), สำนักวิชาแพทยศาสตร์และพยาบาลศาสตร์, มทส.',
      'category': 'campus',
      'lat': 14.8755,
      'lon': 102.0130,
      'aliases': ['f5', 'f6', 'ตึก f5', 'ตึก f6', 'อาคาร f5'],
    },
    {
      'name': 'อาคารศูนย์เครื่องมือวิทยาศาสตร์และเทคโนโลยี (F9 มทส.)',
      'display_name': 'ศูนย์เครื่องมือ F9, มหาวิทยาลัยเทคโนโลยีสุรนารี',
      'category': 'campus',
      'lat': 14.8745,
      'lon': 102.0150,
      'aliases': ['f9', 'ตึก f9', 'ศูนย์เครื่องมือ', 'อาคาร f9'],
    },
    {
      'name': 'อาคารศูนย์ความเป็นเลิศทางการแพทย์ (F12 มทส.)',
      'display_name': 'อาคาร F12, มหาวิทยาลัยเทคโนโลยีสุรนารี',
      'category': 'campus',
      'lat': 14.8730,
      'lon': 102.0160,
      'aliases': ['f12', 'ตึก f12', 'อาคาร f12'],
    },
    {
      'name': 'กลุ่มหอพักนักศึกษา สุรนิเวศ (S1-S18)',
      'display_name': 'กลุ่มหอพักสุรนิเวศน์ (S1 - S18), มทส., นครราชสีมา',
      'category': 'lodging',
      'lat': 14.8720,
      'lon': 102.0190,
      'aliases': ['หอพัก มทส', 'สุรนิเวศ', 'หอพักสุรนิเวศ', 'หอใน มทส', 'หอพักนักศึกษา', 's1', 's2', 's3', 's4', 's5', 's6', 's7', 's8', 's9', 's10', 's11', 's12', 's13', 's14', 's15', 's16', 's17', 's18'],
    },
    {
      'name': '7-Eleven หน้า มทส. ประตู 1 (เซเว่นหน้ามอ)',
      'display_name': '7-Eleven สาขาหน้ามหาวิทยาลัยเทคโนโลยีสุรนารี (ประตู 1), ต.สุรนารี',
      'category': 'shop',
      'lat': 14.9010,
      'lon': 102.0155,
      'aliases': ['7-eleven หน้ามทส', 'เซเว่นหน้ามทส', 'เซเว่นหน้ามอ', 'เซเว่นประตู 1', '7-11 sut', 'เซเว่น มทส'],
    },
    {
      'name': '7-Eleven หน้า มทส. ประตู 4 (เซเว่นเทคโนธานี)',
      'display_name': '7-Eleven สาขาประตู 4 เทคโนธานี มทส., ต.สุรนารี',
      'category': 'shop',
      'lat': 14.8685,
      'lon': 102.0320,
      'aliases': ['เซเว่นประตู 4', 'เซเว่นเทคโนธานี', '7-eleven ประตู 4'],
    },
    {
      'name': 'ตลาดร่วมใจ มทส. (ไนท์มาร์เก็ต มทส.)',
      'display_name': 'ตลาดร่วมใจ (ลานกิจกรรมหน้าหอพักสุรนิเวศ), มทส., นครราชสีมา',
      'category': 'shop',
      'lat': 14.8735,
      'lon': 102.0185,
      'aliases': ['ตลาดร่วมใจ', 'ตลาดมทส', 'ไนท์มทส', 'ตลาดนัดมทส'],
    },

    // Bangkok Transit Hubs
    {
      'name': 'BTS สยาม (Siam Station)',
      'display_name': 'สถานีรถไฟฟ้า BTS สยาม, ถ.พระราม 1, ปทุมวัน, กรุงเทพฯ',
      'category': 'transit',
      'lat': 13.7456,
      'lon': 100.5348,
      'aliases': ['bts สยาม', 'บีทีเอส สยาม', 'สยาม', 'siam bts', 'bts siam'],
    },
    {
      'name': 'BTS หมอชิต / MRT สวนจตุจักร',
      'display_name': 'สถานีรถไฟฟ้า BTS หมอชิต, ถ.พหลโยธิน, จตุจักร, กรุงเทพฯ',
      'category': 'transit',
      'lat': 13.8025,
      'lon': 100.5538,
      'aliases': ['bts หมอชิต', 'หมอชิต', 'จตุจักร', 'mo chit bts'],
    },
    {
      'name': 'สนามบินดอนเมือง (Don Mueang Airport - DMK)',
      'display_name': 'ท่าอากาศยานดอนเมือง, ถ.วิภาวดีรังสิต, ดอนเมือง, กรุงเทพฯ',
      'category': 'transit',
      'lat': 13.9126,
      'lon': 100.6068,
      'aliases': ['ดอนเมือง', 'สนามบินดอนเมือง', 'dmk', 'don mueang'],
    },
    {
      'name': 'สนามบินสุวรรณภูมิ (Suvarnabhumi Airport - BKK)',
      'display_name': 'ท่าอากาศยานสุวรรณภูมิ, อ.บางพลี, จ.สมุทรปราการ',
      'category': 'transit',
      'lat': 13.6900,
      'lon': 100.7501,
      'aliases': ['สุวรรณภูมิ', 'สนามบินสุวรรณภูมิ', 'bkk', 'suvarnabhumi'],
    },
  ];

  static Future<List<PlaceResult>> searchPlaces(String query, {double? userLat, double? userLon}) async {
    final cleanQ = query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (cleanQ.isEmpty) return [];

    final List<PlaceResult> results = [];
    final Set<String> addedNames = {};

    void addResult(String name, String dName, String category, double lat, double lon) {
      if (lat != 0.0 && lon != 0.0 && !addedNames.contains(name)) {
        addedNames.add(name);
        results.add(PlaceResult(
          name: name,
          displayName: dName,
          category: category,
          lat: lat,
          lon: lon,
        ));
      }
    }

    // 1. Embedded High Precision Search
    for (var item in _embeddedPlaces) {
      final name = item['name'] as String;
      final dName = item['display_name'] as String;
      final category = item['category'] as String;
      final lat = (item['lat'] as num).toDouble();
      final lon = (item['lon'] as num).toDouble();
      final aliases = (item['aliases'] as List<dynamic>?)?.cast<String>() ?? [];

      bool matches = name.toLowerCase().contains(cleanQ) ||
          dName.toLowerCase().contains(cleanQ) ||
          aliases.any((a) => a.toLowerCase().contains(cleanQ) || cleanQ.contains(a.toLowerCase()));

      final noSpaceQuery = cleanQ.replaceAll(' ', '');
      final noSpaceName = name.replaceAll(' ', '').toLowerCase();
      if (!matches && (noSpaceName.contains(noSpaceQuery) || aliases.any((a) => a.replaceAll(' ', '').toLowerCase().contains(noSpaceQuery)))) {
        matches = true;
      }

      if (matches) {
        addResult(name, dName, category, lat, lon);
      }
    }

    // 2. Query Backend Places AI & GIS Search (/api/v1/places/search)
    try {
      final baseUrl = ApiClient().baseUrl;
      String backendUrl = '$baseUrl/api/v1/places/search?q=' + Uri.encodeComponent(query);
      if (userLat != null && userLon != null && userLat != 0.0) {
        backendUrl += '&lat=$userLat&lon=$userLon';
      }

      final bResp = await http.get(
        Uri.parse(backendUrl),
        headers: {'User-Agent': 'TAM-AccessibilityApp/1.0'},
      ).timeout(const Duration(seconds: 3));

      if (bResp.statusCode == 200) {
        final bData = jsonDecode(bResp.body);
        final bPlaces = bData['places'] as List<dynamic>?;
        if (bPlaces != null) {
          for (var p in bPlaces) {
            final pName = p['name'] as String? ?? '';
            final pDName = p['display_name'] as String? ?? pName;
            final pCat = p['category'] as String? ?? 'general';
            final pLat = double.tryParse(p['lat'].toString()) ?? 0.0;
            final pLon = double.tryParse(p['lon'].toString()) ?? 0.0;
            addResult(pName, pDName, pCat, pLat, pLon);
          }
        }
      }
    } catch (_) {}

    // 3. Direct Online Geocoding via SerpApi Google Maps (Fallback)
    if (results.length < 3) {
      try {
        const serpapiKey = String.fromEnvironment('SERPAPI_API_KEY', defaultValue: '');
        if (serpapiKey.isNotEmpty) {
          String serpUrl = 'https://serpapi.com/search.json?engine=google_maps&q=' + Uri.encodeComponent(query) + '&google_domain=google.co.th&hl=th&gl=th&api_key=' + serpapiKey;
          if (userLat != null && userLon != null && userLat != 0.0) {
            serpUrl += '&ll=@$userLat,$userLon,14z';
          }

          final resp = await http.get(
            Uri.parse(serpUrl),
            headers: {'User-Agent': 'TAM-AccessibilityApp/1.0'},
          ).timeout(const Duration(seconds: 4));

          if (resp.statusCode == 200) {
            final Map<String, dynamic> data = jsonDecode(utf8.decode(resp.bodyBytes));
            final localResults = data['local_results'] as List<dynamic>?;
            if (localResults != null) {
              for (var item in localResults) {
                final title = item['title'] as String? ?? '';
                final addr = item['address'] as String? ?? '';
                final display = addr.isNotEmpty && !addr.contains(title) ? '$title, $addr' : (addr.isNotEmpty ? addr : title);
                final coords = item['gps_coordinates'] as Map<String, dynamic>? ?? {};
                final lat = double.tryParse(coords['latitude']?.toString() ?? '0') ?? 0.0;
                final lon = double.tryParse(coords['longitude']?.toString() ?? '0') ?? 0.0;
                
                final types = (item['types'] as List<dynamic>?)?.cast<String>() ?? [(item['type'] as String? ?? 'general')];
                final typesStr = types.join(' ').toLowerCase();
                String cat = 'general';
                if (typesStr.contains('university') || typesStr.contains('school')) {
                  cat = 'campus';
                } else if (typesStr.contains('hospital') || typesStr.contains('clinic')) {
                  cat = 'hospital';
                } else if (typesStr.contains('transit') || typesStr.contains('station') || typesStr.contains('subway') || typesStr.contains('bts') || typesStr.contains('mrt')) {
                  cat = 'transit';
                } else if (typesStr.contains('mall') || typesStr.contains('shop') || typesStr.contains('market') || typesStr.contains('store')) {
                  cat = 'shop';
                } else if (typesStr.contains('restaurant') || typesStr.contains('cafe') || typesStr.contains('food')) {
                  cat = 'restaurant';
                }

                addResult(title, display, cat, lat, lon);
              }
            }
          }
        }
      } catch (_) {}
    }

    // 4. Direct AI Geocoder Fallback (Resolves any local village, subdivision, cafe, or building in Thailand)
    if (results.isEmpty) {
      try {
        const groqKey = String.fromEnvironment(
          'GROQ_API_KEY',
          defaultValue: '',
        );
        if (groqKey.isEmpty) return results;
        final groqUrl = Uri.parse('https://api.groq.com/openai/v1/chat/completions');
        final prompt = "You are a Thailand GIS Places Geocoder. Return real GPS coordinates for '$query' near lat ${userLat ?? 14.8818}, lon ${userLon ?? 102.0245} (Nakhon Ratchasima / Thailand).\n"
            "Format: {\"places\": [{\"name\": \"หมู่บ้าน...\", \"display_name\": \"...\", \"category\": \"residential\", \"lat\": 14.9125, \"lon\": 102.0680}]}";

        final resp = await http.post(
          groqUrl,
          headers: {
            'Authorization': 'Bearer $groqKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': 'llama-3.3-70b-versatile',
            'messages': [
              {'role': 'user', 'content': prompt}
            ],
            'temperature': 0.1,
            'response_format': {'type': 'json_object'},
          }),
        ).timeout(const Duration(seconds: 4));

        if (resp.statusCode == 200) {
          final resJson = jsonDecode(utf8.decode(resp.bodyBytes));
          final rawContent = resJson['choices'][0]['message']['content'] ?? '{}';
          final parsed = jsonDecode(rawContent);
          final pList = parsed['places'] as List<dynamic>?;
          if (pList != null) {
            for (var p in pList) {
              final pName = p['name'] as String? ?? '';
              final pDName = p['display_name'] as String? ?? pName;
              final pCat = p['category'] as String? ?? 'general';
              final pLat = double.tryParse(p['lat'].toString()) ?? 0.0;
              final pLon = double.tryParse(p['lon'].toString()) ?? 0.0;
              addResult(pName, pDName, pCat, pLat, pLon);
            }
          }
        }
      } catch (_) {}
    }

    return results;
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 't_DanhSachLichChon.dart';

import 'package:flutter/foundation.dart' show kIsWeb;

String getBaseUrl() {
  if (kIsWeb) {
    return 'http://localhost:5001/';
  } else {
    return 'http://10.0.2.2:5001/';
  }
}

/// Mô hình khung giờ từ [start] → [end]
class TimeRange {
  final TimeOfDay start;
  final TimeOfDay end;
  TimeRange({required this.start, required this.end});
}

/// Chuyển "T3" → weekday (1=Thứ Hai ... 7=Chủ Nhật)
int weekdayFromLabel(String label) {
  label = label.trim().toUpperCase();
  if (label.startsWith('T')) {
    final n = int.tryParse(label.substring(1));
    if (n != null && n >= 2 && n <= 7) return n - 1;
  }
  throw FormatException('Không đọc được thứ: $label');
}

/// Tách "T3:07:30-11:30;T6:13:00-17:00" → map weekday→List<TimeRange>
Map<int, List<TimeRange>> parseLichLamViec(String raw) {
  final out = <int, List<TimeRange>>{};
  for (final part in raw.split(';')) {
    final p = part.trim();
    if (p.isEmpty) continue;
    final kv = p.split(':');
    if (kv.length < 2) continue;
    int wd;
    try {
      wd = weekdayFromLabel(kv[0]);
    } catch (_) {
      continue;
    }
    final times = kv.sublist(1).join(':').split('-');
    if (times.length != 2) continue;
    final sh = times[0].split(':'), eh = times[1].split(':');
    final start = TimeOfDay(hour: int.parse(sh[0]), minute: int.parse(sh[1]));
    final end = TimeOfDay(hour: int.parse(eh[0]), minute: int.parse(eh[1]));
    out.putIfAbsent(wd, () => []).add(TimeRange(start: start, end: end));
  }
  return out;
}

Future<List<String>> _fetchLichKham(int bacSiId, DateTime ngay) async {
  final dateStr =
      "${ngay.year}-${ngay.month.toString().padLeft(2, '0')}-${ngay.day.toString().padLeft(2, '0')}";
  final url =
      "${getBaseUrl()}api/LichKham/BacSiNgay?maBacSi=$bacSiId&ngay=$dateStr";
  final resp = await http.get(Uri.parse(url));
  if (resp.statusCode == 200) {
    final List times = jsonDecode(resp.body);
    // Lấy ra giờ:phút từ thời gian (trả về '2025-06-10T07:30:00')
    return times
        .map((t) {
          final time = DateTime.parse(t);
          return "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
        })
        .toList()
        .cast<String>();
  }
  return [];
}

/// Chia khung giờ thành các slot = 1h
List<TimeRange> splitHourly(TimeRange r) {
  final slots = <TimeRange>[];
  var curr = r.start.hour * 60 + r.start.minute;
  final end = r.end.hour * 60 + r.end.minute;
  while (curr + 60 <= end) {
    final sH = curr ~/ 60, sM = curr % 60;
    final eT = curr + 60;
    slots.add(
      TimeRange(
        start: TimeOfDay(hour: sH, minute: sM),
        end: TimeOfDay(hour: eT ~/ 60, minute: eT % 60),
      ),
    );
    curr += 60;
  }
  return slots;
}

/// Gộp chuỗi ngày + giờ thành lịch làm việc giống định dạng cũ
String _combineSchedule(String ngay, String gio) {
  final days = ngay.split(';').map((e) => e.trim()).toList();
  final slots = gio.split(';').map((e) => e.trim()).toList();
  final parts = <String>[];
  for (var i = 0; i < days.length && i < slots.length; i++) {
    parts.add("${days[i]}:${slots[i]}");
  }
  return parts.join(';');
}

class Doctor {
  final String id;
  final String name;
  final String specialty;
  final String lichLamViec;
  late final Map<int, List<TimeRange>> schedule = parseLichLamViec(lichLamViec);

  Doctor({
    required this.id,
    required this.name,
    required this.specialty,
    required this.lichLamViec,
  });
}

class ChonChuyenKhoaScreen extends StatefulWidget {
  final Map<String, dynamic> hoSo;
  final int userId;
  final List<Map<String, dynamic>> selectedBookings;

  const ChonChuyenKhoaScreen({
    super.key,
    required this.hoSo,
    required this.userId,
    required this.selectedBookings,
  });

  @override
  State<ChonChuyenKhoaScreen> createState() => _ChonChuyenKhoaScreenState();
}

class _ChonChuyenKhoaScreenState extends State<ChonChuyenKhoaScreen> {
  List<Map<String, dynamic>> chuyenKhoaList = [];
  bool loadingCK = true;
  String? errCK;
  String? selectedCK;

  List<Doctor> doctors = [];
  bool loadingDocs = true;
  String? errDocs;

  // --- Chọn ngày + slot ---
  DateTime? selectedDate;
  List<Doctor> availDocs = [];
  Map<Doctor, List<TimeRange>> docSlots = {};

  // *** Chỉ chọn 1 bác sĩ và 1 khung giờ ***
  Doctor? selectedDoctor;
  String? selectedSlot;

  // Danh sách tạm để lưu lịch đặt
  late List<Map<String, dynamic>> selectedBookings;

  List<Map<String, dynamic>> leaveRequests = [];

  List<Map<String, dynamic>> availableSlots = [];
  Map<String, dynamic>? selectedSlotInfo;

  @override
  void initState() {
    super.initState();
    selectedBookings = widget.selectedBookings;
    _loadChuyenKhoa();
    _loadDoctors();
    _fetchLeaveRequests();
  }

  /// Tải danh sách chuyên khoa
  Future<void> _loadChuyenKhoa() async {
    setState(() {
      loadingCK = true;
      errCK = null;
    });
    try {
      final resp = await http.get(Uri.parse("${getBaseUrl()}api/ChuyenKhoa"));
      if (resp.statusCode == 200) {
        final js = jsonDecode(resp.body) as List;
        chuyenKhoaList =
            js
                .whereType<Map<String, dynamic>>()
                .where((m) => m.containsKey("tenChuyenKhoa"))
                .where((m) => (m['daXoa'] == false || m['daXoa'] == null))
                .map(
                  (m) => {"tenChuyenKhoa": m["tenChuyenKhoa"], "gia": m["gia"]},
                )
                .toList();
        print(chuyenKhoaList);
      }
    } catch (e) {
      errCK = "Không thể kết nối: $e";
    }
    setState(() {
      loadingCK = false;
    });
  }

  /// Tải danh sách bác sĩ
  Future<void> _loadDoctors() async {
    setState(() {
      loadingDocs = true;
      errDocs = null;
    });
    try {
      final resp = await http.get(Uri.parse("${getBaseUrl()}api/BacSi"));
      if (resp.statusCode == 200) {
        final js = jsonDecode(resp.body) as List;
        doctors =
            js.whereType<Map<String, dynamic>>().map((m) {
              return Doctor(
                id: m["maBacSi"].toString(),
                name: m["hoVaTen"] as String? ?? "",
                specialty: (m["chuyenKhoa"]?["tenChuyenKhoa"] as String?) ?? "",
                lichLamViec: _combineSchedule(
                  m["ngayLamViec"],
                  m["khungGioLamViec"],
                ),
              );
            }).toList();
      }
    } catch (e) {
      errDocs = "Không thể kết nối: $e";
    }
    setState(() {
      loadingDocs = false;
    });
  }

  Future<void> _fetchLeaveRequests() async {
    try {
      final url = '${getBaseUrl()}api/NghiPhepBacSi';
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as List;
        setState(() {
          leaveRequests =
              data
                  .where(
                    (e) => e['trangThai'] == 'Đã duyệt',
                  ) // Chỉ lấy nghỉ đã duyệt
                  .cast<Map<String, dynamic>>()
                  .toList();
        });
      }
    } catch (e) {
      print('Lỗi lấy đơn nghỉ phép: $e');
    }
  }

  bool isDoctorOnLeave(Doctor doc, DateTime date) {
    final bacSiId = int.parse(doc.id);
    for (var leave in leaveRequests) {
      if (leave['maBacSi'] == bacSiId) {
        DateTime start = DateTime.parse(leave['ngayBatDau']);
        DateTime end = DateTime.parse(leave['ngayKetThuc']);
        DateTime checkDay = DateTime(date.year, date.month, date.day);
        start = DateTime(start.year, start.month, start.day);
        end = DateTime(end.year, end.month, end.day);
        if (checkDay.isAtSameMomentAs(start) ||
            checkDay.isAtSameMomentAs(end) ||
            (checkDay.isAfter(start) && checkDay.isBefore(end))) {
          return true; // bác sĩ nghỉ ngày đó
        }
      }
    }
    return false; // bác sĩ không nghỉ ngày đó
  }

  /// Chọn chuyên khoa
  void _pickChuyenKhoa() {
    if (loadingCK) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Đang tải chuyên khoa...")));
      return;
    }
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text("Chọn chuyên khoa"),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: chuyenKhoaList.length,
                itemBuilder: (_, i) {
                  final ck = chuyenKhoaList[i];
                  final isSelected = selectedCK == ck["tenChuyenKhoa"];
                  return ListTile(
                    title: Text(
                      ck["tenChuyenKhoa"],
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    trailing: Text(
                      "${ck["gia"]} đ",
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        selectedCK = ck["tenChuyenKhoa"];
                        selectedDate = null;
                        availDocs.clear();
                        docSlots.clear();
                        selectedDoctor = null;
                        selectedSlot = null;
                      });
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ),
    );
  }

  /// Chọn ngày
  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) {
      setState(() {
        selectedDate = d;
        selectedDoctor = null;
        selectedSlot = null;
      });
      await _loadAvailableSlots();
    }
  }

  /// Tải slot còn trống của bác sĩ
  Future<void> _loadAvailableSlots() async {
    availableSlots.clear();
    if (selectedCK == null || selectedDate == null) return;
    final wd = selectedDate!.weekday;
    final List<Doctor> ckDocs =
        doctors.where((doc) {
          return doc.specialty == selectedCK &&
              (doc.schedule[wd]?.isNotEmpty ?? false) &&
              !isDoctorOnLeave(doc, selectedDate!); // loại bác sĩ nghỉ
        }).toList();

    final Map<String, List<Doctor>> slotToDoctors = {};

    for (var doc in ckDocs) {
      final booked = await _fetchLichKham(int.parse(doc.id), selectedDate!);
      final ranges = doc.schedule[wd] ?? [];
      final slots = ranges.expand(splitHourly).toList();
      for (var r in slots) {
        final slotStart =
            "${r.start.hour.toString().padLeft(2, '0')}:${r.start.minute.toString().padLeft(2, '0')}";
        if (!booked.contains(slotStart)) {
          final slotLabel =
              "${r.start.hour.toString().padLeft(2, '0')}:${r.start.minute.toString().padLeft(2, '0')} - "
              "${r.end.hour.toString().padLeft(2, '0')}:${r.end.minute.toString().padLeft(2, '0')}";
          slotToDoctors.putIfAbsent(slotLabel, () => []).add(doc);
        }
      }
    }

    // Tạo danh sách slot, mỗi slot có số lượng bác sĩ còn trống
    availableSlots =
        slotToDoctors.entries
            .where((e) => e.value.isNotEmpty)
            .map(
              (e) => {
                "slotLabel": e.key,
                "doctors": e.value, // List<Doctor>
                "count": e.value.length,
              },
            )
            .toList();

    setState(() {});
  }

  /// Xác nhận
  void _confirm() async {
    if (selectedCK == null ||
        selectedDate == null ||
        selectedSlotInfo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Vui lòng chọn chuyên khoa, ngày và khung giờ!"),
        ),
      );
      return;
    }

    // Chọn bác sĩ có số lịch ít nhất trong slot này
    List<Doctor> slotDoctors = List<Doctor>.from(selectedSlotInfo!["doctors"]);
    Doctor? chosenDoctor;
    int minLich = 99999;
    for (var doc in slotDoctors) {
      final booked = await _fetchLichKham(int.parse(doc.id), selectedDate!);
      if (booked.length < minLich) {
        minLich = booked.length;
        chosenDoctor = doc;
      }
    }
    if (chosenDoctor == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Slot này đã hết chỗ!")));
      return;
    }

    final bookingData = {
      "hoSoId": widget.hoSo["id"],
      "tenHoSo": widget.hoSo["ten"],
      "chuyenKhoa": selectedCK,
      "gia":
          chuyenKhoaList.firstWhere(
            (ck) => ck["tenChuyenKhoa"] == selectedCK,
          )["gia"],
      "ngayKham":
          "${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}",
      "bacSiId": chosenDoctor.id,
      "bacSiTen": chosenDoctor.name,
      "khungGio": selectedSlotInfo!["slotLabel"],
    };

    // Lấy giờ bắt đầu của lịch mới
    final newStart = selectedSlotInfo!["slotLabel"].split('-')[0].trim();
    final newDate =
        "${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}";

    // Kiểm tra trùng lịch
    final isTrung = selectedBookings.any((lich) {
      if (lich["ngayKham"] != newDate) return false;
      // Lấy giờ bắt đầu của lịch đã chọn
      final existStart = lich["khungGio"].split('-')[0].trim();
      // Nếu giờ bắt đầu trùng
      if (existStart == newStart) return true;
      // Nếu giờ bắt đầu của lịch mới nằm trong khung giờ đã chọn
      final existStartTime = TimeOfDay(
        hour: int.parse(existStart.split(':')[0]),
        minute: int.parse(existStart.split(':')[1]),
      );
      final existEnd = lich["khungGio"].split('-')[1].trim();
      final existEndTime = TimeOfDay(
        hour: int.parse(existEnd.split(':')[0]),
        minute: int.parse(existEnd.split(':')[1]),
      );
      final newStartTime = TimeOfDay(
        hour: int.parse(newStart.split(':')[0]),
        minute: int.parse(newStart.split(':')[1]),
      );
      // Nếu giờ bắt đầu mới nằm trong khoảng đã đặt
      final existStartMinutes =
          existStartTime.hour * 60 + existStartTime.minute;
      final existEndMinutes = existEndTime.hour * 60 + existEndTime.minute;
      final newStartMinutes = newStartTime.hour * 60 + newStartTime.minute;
      return newStartMinutes >= existStartMinutes &&
          newStartMinutes < existEndMinutes;
    });

    if (isTrung) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Bạn đã có lịch trùng khung giờ này!")),
      );
      return;
    }

    // Nếu không trùng thì thêm vào danh sách
    selectedBookings.add(bookingData);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => DanhSachLichChuaThanhToanScreen(
              hoSo: widget.hoSo,
              userId: widget.userId,
              ngayChon: selectedDate,
              selectedBookings: selectedBookings,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Chọn chuyên khoa",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF0165FC),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Chuyên khoa
            const Text(
              "Chọn chuyên khoa:",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _pickChuyenKhoa,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.blue,
              ),
              child: Text(
                selectedCK != null ? selectedCK! : "Chọn chuyên khoa",
              ),
            ),
            if (selectedCK != null) ...[
              const SizedBox(height: 8),
              Text(
                "Giá khám: ${chuyenKhoaList.firstWhere((ck) => ck["tenChuyenKhoa"] == selectedCK)["gia"]} đ",
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Ngày
            const Text(
              "Chọn ngày khám:",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _pickDate,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.blue,
              ),
              child: Text(
                selectedDate != null
                    ? "${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}"
                    : "Chọn ngày",
              ),
            ),
            const SizedBox(height: 20),
            if (selectedDate != null && availableSlots.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  "Không có lịch trống cho ngày này. Vui lòng chọn ngày khác.",
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

            if (availableSlots.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Chọn khung giờ khám:",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...availableSlots.map(
                    (slot) => ListTile(
                      title: Text(slot["slotLabel"]),
                      subtitle: Text("Còn ${slot["count"]} bác sĩ trống"),
                      leading: Radio<Map<String, dynamic>>(
                        value: slot,
                        groupValue: selectedSlotInfo,
                        onChanged: (val) {
                          setState(() {
                            selectedSlotInfo = val;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 16),

            // Xác nhận
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0165FC),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  "Xác nhận đặt lịch",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

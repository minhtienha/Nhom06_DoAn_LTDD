import 'package:doan_nhom06/GiaoDien_BenhNhan/t_TaoMoiHoSoBenhNhan.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:doan_nhom06/GiaoDien_BenhNhan/t_DatLichKhamChuyenKhoa.dart';
import 'package:doan_nhom06/GiaoDien_BenhNhan/t_ChonBacSiKham.dart';

import 'package:flutter/foundation.dart' show kIsWeb;

String getBaseUrl() {
  if (kIsWeb) {
    return 'http://localhost:5001/';
  } else {
    return 'http://10.0.2.2:5001/';
  }
}

class ChonHoSoScreen extends StatefulWidget {
  final int userId;
  final String bookingType; // "ChuyenKhoa" hoặc "BacSi"
  const ChonHoSoScreen({
    super.key,
    required this.userId,
    required this.bookingType,
  });

  @override
  State<ChonHoSoScreen> createState() => _ChonHoSoScreenState();
}

class _ChonHoSoScreenState extends State<ChonHoSoScreen> {
  List<Map<String, dynamic>> danhSachHoSo = [];
  bool isLoading = true;
  String? errMessage;

  @override
  void initState() {
    super.initState();
    _loadHoSo();
  }

  Future<void> _loadHoSo() async {
    try {
      final resp = await http.get(
        Uri.parse('${getBaseUrl()}api/HoSoBenhNhan/NguoiDung/${widget.userId}'),
      );

      if (resp.statusCode == 200) {
        // 1. Giải mã thành List
        final List jsonList = jsonDecode(resp.body) as List;

        // 2. Map từng phần tử thành Map<String,dynamic>
        danhSachHoSo =
            jsonList.map((item) {
              final parsed =
                  DateTime.tryParse(item["ngaySinh"] ?? "") ?? DateTime.now();
              return {
                "id": item["maHoSo"],
                "ten": item["hoVaTen"],
                "ngaySinh": DateFormat("dd/MM/yyyy").format(parsed),
                "moiQuanHe": item["moiQuanHe"],
              };
            }).toList();
      } else {
        errMessage = "Server trả về lỗi ${resp.statusCode}";
      }
    } catch (e) {
      errMessage = "Không thể kết nối: $e";
    }

    setState(() {
      isLoading = false;
    });
  }

  void _navigateToNextScreen(Map<String, dynamic> hoSo) {
    if (widget.bookingType == "ChuyenKhoa") {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => ChonChuyenKhoaScreen(
                hoSo: hoSo,
                userId: widget.userId,
                selectedBookings: [],
              ),
        ),
      );
    } else if (widget.bookingType == "BacSi") {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => ChonBacSiScreen(
                hoSo: hoSo,
                userId: widget.userId,
                selectedBookings: [],
              ),
        ),
      );
    } else {
      print("Lỗi: bookingType không hợp lệ!");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Chọn hồ sơ đặt khám",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        backgroundColor: const Color(0xFF0165FC),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : errMessage != null
              ? Center(
                child: Text(
                  errMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              )
              : danhSachHoSo.isEmpty
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Colors.blue,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Bạn chưa có hồ sơ bệnh nhân nào.",
                      style: TextStyle(fontSize: 16, color: Colors.blue),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) => TaoHoSoBenhNhanScreen(
                                  maNguoiDung: widget.userId,
                                ),
                          ),
                        ).then((value) {
                          setState(() {});
                        });
                      },
                      icon: const Icon(
                        Icons.person_add_alt,
                        color: Colors.white,
                      ),
                      label: const Text(
                        "Tạo hồ sơ mới",
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0165FC),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              )
              : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: danhSachHoSo.length,
                itemBuilder: (context, index) {
                  final hoSo = danhSachHoSo[index];
                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      leading: const Icon(
                        Icons.person,
                        color: Colors.blueAccent,
                        size: 36,
                      ),
                      title: Text(
                        hoSo["ten"],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        "Ngày sinh: ${hoSo["ngaySinh"]}\nQuan hệ: ${hoSo["moiQuanHe"]}",
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.arrow_forward,
                          color: Colors.blueAccent,
                        ),
                        onPressed: () => _navigateToNextScreen(hoSo),
                      ),
                    ),
                  );
                },
              ),
    );
  }
}

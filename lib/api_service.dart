import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = "https://crabbing-bunt-crispy.ngrok-free.dev";

  Future<Map<String, dynamic>> verifyFace(File image) async {
    var request = http.MultipartRequest("POST", Uri.parse("$baseUrl/verify"));

    request.files.add(await http.MultipartFile.fromPath("photo", image.path));

    final response = await request.send();

    final body = await response.stream.bytesToString();

    return jsonDecode(body);
  }
}

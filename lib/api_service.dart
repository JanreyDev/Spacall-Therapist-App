import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

class ApiService {
  // Use 10.0.2.2 for Android emulator, localhost for web/desktop
  static String get baseUrl {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000/api';
    }
    return 'http://localhost:8000/api';
  }

  Future<Map<String, dynamic>> loginEntry(String mobileNumber) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/entry'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'mobile_number': mobileNumber}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to login: ${response.body}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  Future<Map<String, dynamic>> verifyOtp(
    String mobileNumber,
    String otp,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/verify-otp'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'mobile_number': mobileNumber, 'otp': otp}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Invalid OTP');
      }
    } catch (e) {
      throw Exception('Verification failed: $e');
    }
  }

  Future<Map<String, dynamic>> registerProfile({
    required String mobileNumber,
    required String firstName,
    required String lastName,
    required String gender,
    required String dob,
    required String pin,
    required dynamic profilePhoto,
    required dynamic idCardPhoto,
    required dynamic idSelfiePhoto,
    String role = 'therapist',
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/auth/register-profile'),
      );

      request.headers['Accept'] = 'application/json';
      request.fields['mobile_number'] = mobileNumber;
      request.fields['first_name'] = firstName;
      request.fields['last_name'] = lastName;
      request.fields['gender'] = gender;
      request.fields['date_of_birth'] = dob;
      request.fields['pin'] = pin;
      request.fields['role'] = role;

      // Helper to add file
      Future<void> addFile(String field, dynamic file) async {
        if (file == null) return;
        if (file is XFile) {
          if (kIsWeb) {
            final bytes = await file.readAsBytes();
            request.files.add(
              http.MultipartFile.fromBytes(field, bytes, filename: file.name),
            );
          } else {
            request.files.add(
              await http.MultipartFile.fromPath(field, file.path),
            );
          }
        } else if (file is String) {
          request.files.add(await http.MultipartFile.fromPath(field, file));
        }
      }

      await addFile('profile_photo', profilePhoto);
      await addFile('id_card_photo', idCardPhoto);
      await addFile('id_selfie_photo', idSelfiePhoto);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(
          error['message'] ??
              error['errors']?.toString() ??
              'Registration failed',
        );
      }
    } catch (e) {
      throw Exception('Registration Error: $e');
    }
  }

  Future<Map<String, dynamic>> updateLocation({
    required String token,
    required double latitude,
    required double longitude,
    bool isOnline = true,
  }) async {
    try {
      final url = '$baseUrl/therapist/location';
      print('Calling API: POST $url');
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'latitude': latitude,
          'longitude': longitude,
          'is_online': isOnline,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to update location: ${response.body}');
      }
    } catch (e) {
      throw Exception('Location Update Error: $e');
    }
  }

  Future<Map<String, dynamic>> getNearbyBookings({
    required String token,
    double? latitude,
    double? longitude,
  }) async {
    try {
      String url = '$baseUrl/therapist/nearby-bookings';
      if (latitude != null && longitude != null) {
        url += '?latitude=$latitude&longitude=$longitude';
      }
      print('Calling API: GET $url');
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to fetch nearby bookings: ${response.body}');
      }
    } catch (e) {
      throw Exception('Fetch Bookings Error: $e');
    }
  }

  Future<Map<String, dynamic>> updateBookingStatus({
    required String token,
    required int bookingId,
    required String status,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/bookings/$bookingId/status'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'status': status}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to update booking status: ${response.body}');
      }
    } catch (e) {
      throw Exception('Status Update Error: $e');
    }
  }
}

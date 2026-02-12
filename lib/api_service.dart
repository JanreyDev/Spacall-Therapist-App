import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:laravel_echo/laravel_echo.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';

class PusherChannelWrapper {
  final String name;
  final Map<String, List<Function(dynamic)>> _bindings = {};

  PusherChannelWrapper(this.name);

  void bind(String event, Function callback) {
    if (!_bindings.containsKey(event)) {
      _bindings[event] = [];
    }
    _bindings[event]!.add((data) => callback(data));
  }

  void unbind(String event) {
    _bindings.remove(event);
  }

  void handleEvent(String event, dynamic data) {
    if (_bindings.containsKey(event)) {
      for (var callback in _bindings[event]!) {
        callback(data);
      }
    }
  }
}

class EchoPusherClient {
  final PusherChannelsFlutter pusher;
  final Map<String, PusherChannelWrapper> channels = {};

  EchoPusherClient(this.pusher);

  void disconnect() => pusher.disconnect();

  Future<void> connect() => pusher.connect();

  PusherChannelWrapper subscribe(String channelName) {
    pusher.subscribe(channelName: channelName);
    if (!channels.containsKey(channelName)) {
      channels[channelName] = PusherChannelWrapper(channelName);
    }
    return channels[channelName]!;
  }

  void unsubscribe(String channelName) {
    pusher.unsubscribe(channelName: channelName);
    channels.remove(channelName);
  }

  void handleEvent(PusherEvent event) {
    if (channels.containsKey(event.channelName)) {
      channels[event.channelName]!.handleEvent(event.eventName, event.data);
    }
  }
}

class ApiService {
  static String get baseUrl {
    return 'https://api.spacall.ph/api';
  }

  static String? normalizePhotoUrl(String? url) {
    if (url == null || url.isEmpty) return null;

    if (url.startsWith('http')) {
      if (url.contains('localhost') ||
          url.contains('127.0.0.1') ||
          url.contains('10.0.2.2')) {
        return url
            .replaceAll('http://localhost', 'https://api.spacall.ph')
            .replaceAll('http://127.0.0.1', 'https://api.spacall.ph')
            .replaceAll('http://10.0.2.2', 'https://api.spacall.ph');
      }
      return url;
    }

    String path = url.startsWith('/') ? url : '/$url';
    if (!path.startsWith('/storage/')) {
      path = '/storage$path';
    }

    return 'https://api.spacall.ph$path';
  }

  Echo? _echo;

  Future<void> initEcho(String token, int providerId) async {
    if (_echo != null) return;

    final pusher = PusherChannelsFlutter.getInstance();

    final echoClient = EchoPusherClient(pusher);

    try {
      await pusher.init(
        apiKey: 'spacallkey',
        cluster: 'mt1',
        useTLS: true,
        host: 'api.spacall.ph',
        wssPort: 443,
        onEvent: (event) {
          echoClient.handleEvent(event);
        },
        onAuthorizer: (channelName, socketId, options) async {
          final authUrl = '${baseUrl.replaceAll('/api', '')}/broadcasting/auth';
          final response = await http.post(
            Uri.parse(authUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'socket_id': socketId,
              'channel_name': channelName,
            }),
          );
          return jsonDecode(response.body);
        },
      );
    } catch (e) {
      print("Pusher init error: $e");
    }

    await pusher.connect();

    _echo = Echo(client: echoClient, broadcaster: EchoBroadcasterType.Pusher);

    print('Echo initialized for therapist.$providerId');
  }

  void listenForBookings(int providerId, Function(dynamic) onBookingReceived) {
    if (_echo == null) return;

    _echo!.private('therapist.$providerId').listen('.BookingRequested', (e) {
      print('Real-time booking received: $e');
      onBookingReceived(e['booking']);
    });
  }

  void disconnectEcho() {
    _echo?.disconnect();
    _echo = null;
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
    required dynamic idCardBackPhoto,
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
      await addFile('id_card_back_photo', idCardBackPhoto);
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

  Future<Map<String, dynamic>> getActiveRequests({
    required String token,
  }) async {
    try {
      final url = '$baseUrl/therapist/active-requests';
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
        throw Exception('Failed to fetch active requests: ${response.body}');
      }
    } catch (e) {
      throw Exception('Fetch Requests Error: $e');
    }
  }

  Future<Map<String, dynamic>> getCurrentBookings({
    required String token,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/bookings'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to fetch bookings: ${response.body}');
      }
    } catch (e) {
      throw Exception('Bookings Fetch Error: $e');
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

  Future<Map<String, dynamic>> loginPin(String mobileNumber, String pin) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login-pin'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'mobile_number': mobileNumber, 'pin': pin}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Login failed');
      }
    } catch (e) {
      throw Exception('Login Error: $e');
    }
  }

  Future<Map<String, dynamic>> getBookingStatus(
    int bookingId,
    String token,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/bookings/$bookingId/track'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to fetch booking status: ${response.body}');
      }
    } catch (e) {
      throw Exception('Status Fetch Error: $e');
    }
  }

  Future<void> deleteAccount(String token) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/auth/account'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to delete account: ${response.body}');
      }
    } catch (e) {
      throw Exception('Delete Account Error: $e');
    }
  }

  Future<Map<String, dynamic>> getProfile(String token) async {
    try {
      final url = '$baseUrl/therapist/profile';
      print('Calling API: GET $url'); // Debug Log
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Profile response status: ${response.statusCode}'); // Debug Log
      print('Profile response body: ${response.body}'); // Debug Log

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to fetch profile: ${response.body}');
      }
    } catch (e) {
      throw Exception('Profile Fetch Error: $e');
    }
  }
}

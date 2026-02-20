import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:laravel_echo/laravel_echo.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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
          final authUrl =
              '${baseUrl.replaceFirst(RegExp(r'/api$'), '')}/broadcasting/auth';
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

  void listenForBookingUpdates(
    int bookingId,
    Function(dynamic) onBookingUpdated,
  ) {
    if (_echo == null) return;

    _echo!.private('booking.$bookingId').listen('.BookingStatusUpdated', (e) {
      print('Real-time booking update received: $e');
      onBookingUpdated(e['booking']);
    });
  }

  void listenForBookingMessages(
    int bookingId,
    Function(dynamic) onMessageReceived,
  ) {
    if (_echo == null) return;

    _echo!.private('booking.$bookingId').listen('.MessageSent', (e) {
      print('Real-time message received: $e');
      onMessageReceived(e['message']);
    });
  }

  void listenForSupportMessages(
    int sessionId,
    Function(dynamic) onMessageReceived,
  ) {
    if (_echo == null) return;

    print('Subscribing to support.session.$sessionId');
    _echo!.private('support.session.$sessionId').listen('.SupportMessageSent', (
      e,
    ) {
      print('Real-time support message received: $e');
      onMessageReceived(e['message']);
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
    String? middleName,
    required String lastName,
    required String gender,
    required String dob,
    required String pin,
    required dynamic profilePhoto,
    required dynamic idCardPhoto,
    required dynamic idCardBackPhoto,
    required dynamic idSelfiePhoto,
    String role = 'therapist',
    String? customerTier,
    String? storeName,
    double? latitude,
    double? longitude,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/auth/register-profile'),
      );

      request.headers['Accept'] = 'application/json';
      request.fields['mobile_number'] = mobileNumber;
      request.fields['first_name'] = firstName;
      if (middleName != null && middleName.isNotEmpty) {
        request.fields['middle_name'] = middleName;
      }
      request.fields['last_name'] = lastName;
      request.fields['gender'] = gender;
      request.fields['date_of_birth'] = dob;
      request.fields['pin'] = pin;
      request.fields['role'] = role;

      if (customerTier != null) {
        request.fields['customer_tier'] = customerTier;
      }
      if (storeName != null) {
        request.fields['store_name'] = storeName;
      }
      if (latitude != null) {
        request.fields['latitude'] = latitude.toString();
      }
      if (longitude != null) {
        request.fields['longitude'] = longitude.toString();
      }

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

      if (response.statusCode == 200 || response.statusCode == 201) {
        try {
          return jsonDecode(response.body);
        } catch (e) {
          throw Exception('Failed to parse response: ${response.body}');
        }
      } else {
        String errorMessage = 'Registration failed (${response.statusCode})';
        try {
          final error = jsonDecode(response.body);
          errorMessage =
              error['message'] ??
              error['errors']?.toString() ??
              'Registration failed';
        } catch (_) {
          if (response.body.isNotEmpty) {
            errorMessage = 'Server Error: ${response.body}';
          }
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      throw Exception('Registration Error: $e');
    }
  }

  Future<Map<String, dynamic>> uploadProfileImage({
    required String token,
    required String type,
    required dynamic imageFile,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/auth/upload-photo'),
      );

      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json';
      request.fields['type'] = type;

      if (imageFile is String) {
        request.files.add(
          await http.MultipartFile.fromPath('image', imageFile),
        );
      } else {
        request.files.add(
          await http.MultipartFile.fromPath('image', imageFile.path),
        );
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(
          'Upload failed (${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Image Upload Error: $e');
    }
  }

  Future<Map<String, dynamic>> updateLocation({
    required String token,
    required double latitude,
    required double longitude,
    bool? isOnline,
  }) async {
    try {
      final url = '$baseUrl/therapist/location';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'latitude': latitude,
          'longitude': longitude,
          if (isOnline != null) 'is_online': isOnline,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        String msg = 'Failed to update location';
        try {
          final err = jsonDecode(response.body);
          msg = err['message'] ?? msg;
        } catch (_) {}
        throw Exception(msg);
      }
    } catch (e) {
      throw Exception('Location Update Error: $e');
    }
  }

  Future<Map<String, dynamic>> deposit({
    required String token,
    required double amount,
    required String method,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/wallet/deposit'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'amount': amount, 'method': method}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to deposit: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> withdraw({
    required String token,
    required double amount,
    required String method,
    required String accountDetails,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/wallet/withdraw'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'amount': amount,
        'method': method,
        'account_details': accountDetails,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to withdraw: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> getNearbyBookings({
    required String token,
    double? latitude,
    double? longitude,
    String? bookingType,
  }) async {
    try {
      String url = '$baseUrl/therapist/nearby-bookings';
      List<String> params = [];
      if (latitude != null && longitude != null) {
        params.add('latitude=$latitude');
        params.add('longitude=$longitude');
      }
      if (bookingType != null) {
        params.add('booking_type=$bookingType');
      }
      if (params.isNotEmpty) {
        url += '?${params.join('&')}';
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

  Future<Map<String, dynamic>> submitVipApplication({
    required String token,
    required String nickname,
    required int age,
    String? address,
    required int experience,
    required String skills,
    required String bio,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/therapist/apply-vip'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'nickname': nickname,
          'age': age,
          'address': address,
          'experience': experience,
          'skills': skills,
          'bio': bio,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Application failed: ${response.body}');
      }
    } catch (e) {
      throw Exception('VIP Application Error: $e');
    }
  }

  Future<Map<String, dynamic>> getDashboardStats(String token) async {
    try {
      final url = '$baseUrl/therapist/dashboard-stats';
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
        throw Exception('Failed to load dashboard stats');
      }
    } catch (e) {
      throw Exception('Dashboard Stats Error: $e');
    }
  }

  Future<Map<String, dynamic>> getActiveRequests({
    required String token,
    String? bookingType,
  }) async {
    try {
      String url = '$baseUrl/therapist/active-requests';
      if (bookingType != null) {
        url += '?booking_type=$bookingType';
      }
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

  Future<void> logout(String token) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/logout'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Logout failed: ${response.body}');
      }
    } catch (e) {
      throw Exception('Logout Error: $e');
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

  Future<Map<String, dynamic>> updateUserProfile({
    required String token,
    String? firstName,
    String? lastName,
    String? nickname,
    String? dateOfBirth,
    String? email,
    String? gender,
    dynamic imageFile,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/auth/update-profile'),
      );

      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json';

      if (firstName != null) request.fields['first_name'] = firstName;
      if (lastName != null) request.fields['last_name'] = lastName;
      if (nickname != null) request.fields['nickname'] = nickname;
      if (dateOfBirth != null) request.fields['date_of_birth'] = dateOfBirth;
      if (email != null) request.fields['email'] = email;
      if (gender != null) request.fields['gender'] = gender;

      if (imageFile != null) {
        if (imageFile is String) {
          request.files.add(
            await http.MultipartFile.fromPath('image', imageFile),
          );
        } else {
          request.files.add(
            await http.MultipartFile.fromPath('image', imageFile.path),
          );
        }
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        dynamic error;
        try {
          error = jsonDecode(response.body);
        } catch (_) {
          throw Exception('Update failed (HTTP ${response.statusCode})');
        }
        throw Exception(error['message'] ?? 'Failed to update profile');
      }
    } catch (e) {
      throw Exception('Update failed: $e');
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

  Future<Map<String, dynamic>> getChatMessages(
    int bookingId,
    String token,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/bookings/$bookingId/messages'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load messages');
      }
    } catch (e) {
      throw Exception('Chat Fetch Error: $e');
    }
  }

  Future<Map<String, dynamic>> sendChatMessage(
    int bookingId,
    String token,
    String content,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/bookings/$bookingId/messages'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'content': content}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to send message: ${response.body}');
      }
    } catch (e) {
      throw Exception('Chat Send Error: $e');
    }
  }

  Future<Map<String, dynamic>> getSupportSession(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/support/session'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get support session: ${response.body}');
      }
    } catch (e) {
      throw Exception('Support Session Error: $e');
    }
  }

  Future<Map<String, dynamic>> getSupportMessages(
    String token,
    int sessionId,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/support/sessions/$sessionId/messages'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load support messages');
      }
    } catch (e) {
      throw Exception('Support Fetch Error: $e');
    }
  }

  Future<Map<String, dynamic>> sendSupportMessage(
    String token,
    int sessionId,
    String content,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/support/sessions/$sessionId/messages'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'content': content}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to send support message: ${response.body}');
      }
    } catch (e) {
      throw Exception('Support Send Error: $e');
    }
  }

  Future<List<LatLng>> getRoute(LatLng origin, LatLng destination) async {
    const String apiKey = 'AIzaSyB0ufRgcg6WC7icyKzGUp7IeJmaciZVXFw';
    final String url =
        'https://maps.googleapis.com/maps/api/directions/json?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&key=$apiKey';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'OK') {
          final String encodedPolyline =
              data['routes'][0]['overview_polyline']['points'];
          return _decodePolyline(encodedPolyline);
        } else {
          throw Exception('Directions API error: ${data['status']}');
        }
      } else {
        throw Exception('Failed to fetch directions');
      }
    } catch (e) {
      debugPrint('Error fetching directions: $e');
      return [];
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }
}

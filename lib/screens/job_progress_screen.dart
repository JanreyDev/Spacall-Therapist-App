import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../api_service.dart';
import '../chat_provider.dart';
import '../widgets/luxury_success_modal.dart';
import '../widgets/luxury_error_modal.dart';

const goldColor = Color(0xFFD4AF37);

class JobProgressScreen extends StatefulWidget {
  final Map<String, dynamic> booking;
  final String token;

  const JobProgressScreen({
    super.key,
    required this.booking,
    required this.token,
  });

  @override
  State<JobProgressScreen> createState() => _JobProgressScreenState();
}

class _JobProgressScreenState extends State<JobProgressScreen> {
  final ApiService _apiService = ApiService();
  GoogleMapController? _mapController;
  LatLng? _currentPosition;
  late String _currentStatus;
  bool _isLoading = false;
  Timer? _locationTimer;
  Timer? _chatRefreshTimer;
  late bool _isStoreBooking;

  late LatLng _clientLocation;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  int? _currentUserId;
  Timer? _countdownTimer;
  int _remainingSeconds = 0;
  bool _timerStarted = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _alertShown = false;
  BitmapDescriptor? _clientMarkerIcon;
  Set<Polyline> _polylines = {};
  List<dynamic> _routeSteps = [];
  String _totalDistance = '';
  String _totalDuration = '';
  int _currentStepIndex = 0;
  String _selectedTravelMode = 'driving';
  bool _avoidTolls = false;
  bool _avoidHighways = false;
  bool _avoidFerries = false;

  Future<void> _loadClientMarkerIcon() async {
    final customer = widget.booking['customer'] ?? {};
    final url = ApiService.normalizePhotoUrl(customer['profile_photo_url']);
    if (url == null) return;

    try {
      final icon = await _createCircularMarkerIcon(url);
      if (mounted) {
        setState(() {
          _clientMarkerIcon = icon;
        });
      }
    } catch (e) {
      debugPrint('Error loading client marker icon: $e');
    }
  }

  Future<BitmapDescriptor> _createCircularMarkerIcon(String url) async {
    final Completer<ui.Image> completer = Completer();
    final NetworkImage networkImage = NetworkImage(url);
    final ImageStream stream = networkImage.resolve(ImageConfiguration.empty);

    stream.addListener(
      ImageStreamListener((ImageInfo info, bool _) {
        completer.complete(info.image);
      }),
    );

    final ui.Image image = await completer.future;

    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    const double size = 120.0;
    const double radius = size / 2;

    // Draw background circle (border)
    final Paint borderPaint = Paint()
      ..color = goldColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(radius, radius), radius, borderPaint);

    // Draw inner circle for clipping
    final Path clipPath = Path()
      ..addOval(
        Rect.fromCircle(
          center: const Offset(radius, radius),
          radius: radius - 4,
        ),
      );
    canvas.clipPath(clipPath);

    // Draw the image
    final double imageWidth = image.width.toDouble();
    final double imageHeight = image.height.toDouble();
    final double scale =
        size / (imageWidth < imageHeight ? imageWidth : imageHeight);
    final double nw = imageWidth * scale;
    final double nh = imageHeight * scale;
    final double left = (size - nw) / 2;
    final double top = (size - nh) / 2;

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, imageWidth, imageHeight),
      Rect.fromLTWH(left, top, nw, nh),
      Paint(),
    );

    final ui.Image markerImage = await pictureRecorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final ByteData? byteData = await markerImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    final Uint8List uint8List = byteData!.buffer.asUint8List();

    return BitmapDescriptor.fromBytes(uint8List);
  }

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.booking['status'];
    _isStoreBooking = widget.booking['booking_type'] == 'in_store';
    final loc = widget.booking['location'];

    if (loc != null && loc['latitude'] != null && loc['longitude'] != null) {
      _clientLocation = LatLng(
        double.parse(loc['latitude'].toString()),
        double.parse(loc['longitude'].toString()),
      );
    } else {
      // Default to 0,0 if location is missing (should not happen with loaded booking)
      _clientLocation = const LatLng(0, 0);
      debugPrint('Warning: Booking location data is missing!');
    }

    if (!_isStoreBooking) {
      _startTracking();
    }
    _fetchLatestStatus();
    _startChatPolling();
    _loadClientMarkerIcon();
    // Fetch initial chat messages and user ID
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        try {
          final profile = await _apiService.getProfile(widget.token);
          if (mounted) {
            // Note: API returns { user: {...}, provider: {...} }
            final user = profile['user'];
            final provider = profile['provider'];
            final providerId = provider?['id'];

            setState(() {
              _currentUserId = user?['id'];
            });

            if (providerId != null) {
              await _apiService.initEcho(widget.token, providerId);
              _initializeRealTimeEvents();
            } else {
              debugPrint(
                '[JobProgressScreen] ❌ No providerId found in profile!',
              );
            }

            Provider.of<ChatProvider>(
              context,
              listen: false,
            ).fetchMessages(widget.booking['id'], widget.token);
          }
        } catch (e) {
          debugPrint('Error fetching profile for chat: $e');
        }
      }
    });
  }

  void _initializeRealTimeEvents() {
    // Listen for Messages
    _apiService.listenForBookingMessages(widget.booking['id'], (messageData) {
      if (mounted) {
        Provider.of<ChatProvider>(
          context,
          listen: false,
        ).addMessage(messageData);
        _scrollToBottom();
      }
    });

    // Listen for Status Updates
    _apiService.listenForBookingUpdates(widget.booking['id'], (bookingData) {
      debugPrint('[REALTIME THERAPIST] Full Booking Data: $bookingData');
      if (mounted) {
        setState(() {
          _currentStatus = bookingData['status'];
          // Sync updated booking data for timer refresh
          if (bookingData['duration_minutes'] != null) {
            widget.booking['duration_minutes'] =
                bookingData['duration_minutes'];
          }
          if (bookingData['started_at'] != null) {
            widget.booking['started_at'] = bookingData['started_at'];
          }
        });

        // Trigger timer refresh if in progress
        if (_currentStatus == 'in_progress') {
          final rawBooking = bookingData['duration_minutes'];
          final rawService = bookingData['service']?['duration_minutes'];
          debugPrint(
            '[TIMER THERAPIST] Recalculating (Realtime) - rawBooking: $rawBooking, rawService: $rawService',
          );
          final raw = rawBooking ?? rawService;
          final mins = raw is int
              ? raw
              : int.tryParse(raw?.toString() ?? '') ?? 60;
          final startedAt = bookingData['started_at']?.toString();
          _startCountdown(mins, startedAt: startedAt);
        }
      }
    });
  }

  void _scrollToBottom() {
    if (_chatScrollController.hasClients) {
      _chatScrollController.animateTo(
        _chatScrollController.position.maxScrollExtent + 100,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _fetchLatestStatus() async {
    try {
      final data = await _apiService.getBookingStatus(
        widget.booking['id'],
        widget.token,
      );
      if (mounted) {
        debugPrint('[POLL THERAPIST] Full Status Data: $data');
        setState(() {
          _currentStatus = data['booking_status'];
        });
        // If already in_progress (e.g. app restarted), sync timer from started_at
        if (data['booking_status'] == 'in_progress') {
          final booking = data['booking'] as Map<String, dynamic>?;
          final rawBooking = booking?['duration_minutes'];
          final rawService = booking?['service']?['duration_minutes'];
          debugPrint(
            '[TIMER THERAPIST] Recalculating (Poll) - rawBooking: $rawBooking, rawService: $rawService',
          );
          final raw = rawBooking ?? rawService;
          final mins = raw is int
              ? raw
              : int.tryParse(raw?.toString() ?? '') ?? 60;
          final startedAt = booking?['started_at']?.toString();
          _startCountdown(mins, startedAt: startedAt);
        }
      }
    } catch (e) {
      debugPrint('Error fetching latest status: $e');
    }
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _chatRefreshTimer?.cancel();
    _countdownTimer?.cancel();
    _messageController.dispose();
    _chatScrollController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _startCountdown(int durationMinutes, {String? startedAt}) {
    debugPrint(
      '[TIMER THERAPIST] Starting countdown: $durationMinutes mins, startedAt: $startedAt',
    );
    final totalSeconds = durationMinutes * 60;
    int initialRemaining = totalSeconds;

    // If we have the actual start time, compute elapsed to stay in sync
    if (startedAt != null) {
      try {
        final startTime = DateTime.parse(startedAt).toLocal();
        final elapsed = DateTime.now().difference(startTime).inSeconds;
        debugPrint('[TIMER THERAPIST] Current Local Time: ${DateTime.now()}');
        debugPrint('[TIMER THERAPIST] Parsed Start Time: $startTime');
        debugPrint('[TIMER THERAPIST] Elapsed Seconds: $elapsed');
        initialRemaining = (totalSeconds - elapsed).clamp(0, totalSeconds);
      } catch (e) {
        debugPrint('[TIMER THERAPIST] Error parsing startedAt: $e');
      }
    }

    debugPrint('[TIMER THERAPIST] Final initialRemaining: $initialRemaining');

    // Optimization: Only restart if something changed significantly
    if (_timerStarted && (_remainingSeconds - initialRemaining).abs() < 5) {
      debugPrint('[TIMER THERAPIST] Skipping restart - diff too small');
      return;
    }

    debugPrint('[TIMER THERAPIST] Restarting timer now...');
    _countdownTimer?.cancel();

    setState(() {
      _timerStarted = true;
      _remainingSeconds = initialRemaining;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;

          // 2-Minute Warning Logic (120 seconds)
          // Window: 120 to 115 seconds
          if (_remainingSeconds <= 120 &&
              _remainingSeconds >= 115 &&
              !_alertShown) {
            _playAlert();
            _showTwoMinuteWarningDialog();
            _alertShown = true;
          }
        } else {
          // Timer finished - Auto-complete
          if (mounted && _currentStatus == 'in_progress') {
            _updateStatus('completed');
          }
          timer.cancel();
        }
      });
    });
  }

  Future<void> _playAlert() async {
    try {
      // Loop sound 3 times
      for (int i = 0; i < 3; i++) {
        await _audioPlayer.play(
          UrlSource(
            'https://actions.google.com/sounds/v1/alarms/beep_short.ogg',
          ),
        );
        await Future.delayed(const Duration(seconds: 1));
      }
    } catch (e) {
      debugPrint("Error playing sound: $e");
    }
  }

  void _showTwoMinuteWarningDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Row(
          children: [
            Icon(Icons.timer_outlined, color: Colors.redAccent),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                "2 Minutes Remaining",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: const Text(
          "The session has 2 minutes remaining. Please prepare to conclude.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              "OK",
              style: TextStyle(
                color: Color(0xFFD4AF37),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent),
        ),
      ),
    );
  }

  String _formatCountdown(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _startChatPolling() {
    _chatRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        Provider.of<ChatProvider>(
          context,
          listen: false,
        ).fetchMessages(widget.booking['id'], widget.token);
      }
    });
  }

  void _startTracking() {
    _updateLocation();
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _updateLocation();
    });
  }

  Future<void> _updateLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
        });

        if (_currentStatus == 'en_route' || _currentStatus == 'accepted') {
          _fetchRoute();
        }

        // Update location on backend
        await _apiService.updateLocation(
          token: widget.token,
          latitude: position.latitude,
          longitude: position.longitude,
          isOnline: true,
        );

        if (_mapController != null && _currentPosition != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLng(_currentPosition!),
          );
        }
      }
    } catch (e) {
      print('Location update error: $e');
    }
  }

  Future<void> _updateStatus(String status) async {
    setState(() => _isLoading = true);
    try {
      await _apiService.updateBookingStatus(
        token: widget.token,
        bookingId: widget.booking['id'],
        status: status,
      );

      // Force immediate location update for accurate ETA
      _updateLocation();

      setState(() {
        _currentStatus = status;
        _isLoading = false;
      });
      // Start countdown when service begins
      if (status == 'in_progress') {
        final rawBooking = widget.booking['duration_minutes'];
        final rawService = widget.booking['service']?['duration_minutes'];
        final raw = rawBooking ?? rawService;
        final durationMinutes = raw is int
            ? raw
            : int.tryParse(raw?.toString() ?? '') ?? 60;
        // Use now() as startedAt since we just triggered the status change
        _startCountdown(
          durationMinutes,
          startedAt: DateTime.now().toIso8601String(),
        );
      }
      if (status == 'completed' ||
          status == 'cancelled' ||
          status == 'arrived') {
        if (mounted) Navigator.pop(context, 'switch_to_sessions');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showDialog(
        context: context,
        builder: (context) => LuxuryErrorModal(
          title: 'ERROR',
          message: e.toString().replaceAll('Exception: ', ''),
          onConfirm: () => Navigator.of(context).pop(),
        ),
      );
    }
  }

  Future<void> _fetchRoute() async {
    if (_currentPosition == null) return;
    if (_currentStatus != 'en_route' && _currentStatus != 'accepted') {
      setState(() => _polylines = {});
      return;
    }

    final details = await _apiService.getRouteDetails(
      _currentPosition!,
      _clientLocation,
      mode: _selectedTravelMode,
      avoidTolls: _avoidTolls,
      avoidHighways: _avoidHighways,
      avoidFerries: _avoidFerries,
    );

    if (mounted && details.isNotEmpty) {
      setState(() {
        final List<LatLng> points = details['points'] != null
            ? List<LatLng>.from(details['points'])
            : [];
        _routeSteps = details['steps'] ?? [];
        _totalDistance = details['distance'] ?? '';
        _totalDuration = details['duration'] ?? '';
        _currentStepIndex = 0; // Reset for simplicity, could be optimized later

        _polylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            points: points,
            color: const Color(0xFF2196F3), // Bright Blue for road line
            width: 8,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
        };
      });
    }
  }

  void _showChatModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.chat_bubble_outline,
                  color: goldColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'CHAT WITH CLIENT',
                  style: TextStyle(
                    color: goldColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(color: Colors.white10),
            Expanded(
              child: Consumer<ChatProvider>(
                builder: (context, chatProvider, child) {
                  return Column(
                    children: [
                      Expanded(
                        child: chatProvider.isLoading
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: goldColor,
                                ),
                              )
                            : ListView.builder(
                                controller: _chatScrollController,
                                padding: const EdgeInsets.all(24),
                                itemCount: chatProvider.messages.length,
                                itemBuilder: (context, index) {
                                  final msg = chatProvider.messages[index];
                                  final bool isMe =
                                      msg.senderId == _currentUserId;
                                  return _buildChatMessage(msg.content, isMe);
                                },
                              ),
                      ),
                      Container(
                        padding: EdgeInsets.only(
                          left: 24,
                          right: 24,
                          top: 12,
                          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _messageController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Type a message...',
                                  hintStyle: const TextStyle(
                                    color: Colors.white24,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.05),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(30),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              decoration: const BoxDecoration(
                                color: goldColor,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                icon: const Icon(
                                  Icons.send,
                                  color: Colors.black,
                                  size: 20,
                                ),
                                onPressed: () {
                                  if (_messageController.text.isNotEmpty) {
                                    chatProvider.sendMessage(
                                      widget.booking['id'],
                                      widget.token,
                                      _messageController.text,
                                    );
                                    _messageController.clear();
                                    _scrollToBottom();
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // If en_route, show Map. Otherwise (arrived, in_progress), show details.
    // ALWAYS hide map for store bookings
    bool showMap =
        !_isStoreBooking &&
        (_currentStatus == 'en_route' || _currentStatus == 'accepted');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          showMap ? 'JOB PROGRESS' : 'SESSION DETAILS',
          style: const TextStyle(
            color: goldColor,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: goldColor),
      ),
      body: Stack(
        children: [
          if (showMap)
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _clientLocation,
                zoom: 14,
              ),
              onMapCreated: (controller) => _mapController = controller,
              myLocationEnabled: true,
              polylines: _polylines,
              markers: {
                if (_currentPosition != null)
                  Marker(
                    markerId: const MarkerId('therapist'),
                    position: _currentPosition!,
                    infoWindow: const InfoWindow(title: 'Your Location'),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueYellow,
                    ),
                  ),
                Marker(
                  markerId: const MarkerId('client'),
                  position: _clientLocation,
                  infoWindow: const InfoWindow(title: 'Client Location'),
                  icon:
                      _clientMarkerIcon ??
                      BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueAzure,
                      ),
                ),
              },
            )
          else
            _buildDetailsView(goldColor),

          if (showMap)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 20,
                      offset: Offset(0, -5),
                    ),
                  ],
                ),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 32,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(child: _buildInfoRow()),
                          const SizedBox(width: 12),
                          // Chat Button
                          IconButton(
                            onPressed: _showChatModal,
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: goldColor.withOpacity(0.1),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: goldColor.withOpacity(0.3),
                                ),
                              ),
                              child: const Icon(
                                Icons.chat_bubble_outline,
                                color: goldColor,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (!showMap || _currentStatus != 'accepted')
                        _buildActionButton(),
                    ],
                  ),
                ),
              ),
            ),
          if (showMap) ...[
            if (_currentStatus == 'accepted')
              Positioned(
                left: 0,
                right: 0,
                bottom: 0, // Dock to bottom
                child: _buildPreTripOverlay(),
              ),
            if (_currentStatus == 'en_route') ...[
              _buildNavigationOverlay(),
              _buildTripInfoOverlay(),
            ],
          ],
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: goldColor)),
        ],
      ),
    );
  }

  Widget _buildDetailsView(Color goldColor) {
    final customer = widget.booking['customer'] ?? {};
    final service = widget.booking['service'] ?? {};
    final location = widget.booking['location'] ?? {};

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Section - Centered Luxury Card with Action Button
          // Backlit Royal Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xFF1E1E1E), const Color(0xFF121212)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: goldColor.withOpacity(0.12), width: 1),
              boxShadow: [
                BoxShadow(
                  color: goldColor.withOpacity(0.04),
                  blurRadius: 40,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: goldColor.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                    ),
                    CircleAvatar(
                      radius: 35,
                      backgroundColor: const Color(0xFF121212),
                      backgroundImage: () {
                        final normalized = ApiService.normalizePhotoUrl(
                          customer['profile_photo_url'],
                        );
                        return normalized != null
                            ? NetworkImage(normalized)
                            : null;
                      }(),
                      child:
                          ApiService.normalizePhotoUrl(
                                customer['profile_photo_url'],
                              ) ==
                              null
                          ? const Icon(
                              Icons.person,
                              size: 35,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ],
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer['middle_name'] != null &&
                                customer['middle_name'].toString().isNotEmpty
                            ? '${customer['first_name']} ${customer['middle_name']} ${customer['last_name']}'
                            : '${customer['first_name'] ?? 'Guest'} ${customer['last_name'] ?? ''}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: goldColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: goldColor.withOpacity(0.2)),
                        ),
                        child: Text(
                          _getFriendlyStatus(),
                          style: TextStyle(
                            color: goldColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 7,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: _buildActionButton()),
          const SizedBox(height: 32),

          // Countdown Timer (only when in_progress)
          if (_currentStatus == 'in_progress') ...[
            _buildCountdownTimer(),
            const SizedBox(height: 32),
          ],

          // Service Details Header
          Padding(
            padding: EdgeInsets.zero,
            child: Row(
              children: [
                Container(
                  width: 2,
                  height: 12,
                  decoration: BoxDecoration(
                    color: goldColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'SERVICE DETAILS',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 10,
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          // Service Details Card (Screenshot Style)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E).withOpacity(0.5),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailItem(
                  Icons.spa_outlined,
                  'Service Name',
                  service['name'] ?? 'Luxury Treatment',
                  goldColor,
                ),
                const Divider(color: Colors.white10, height: 28),
                Row(
                  children: [
                    Expanded(
                      child: _buildDetailItem(
                        Icons.calendar_today_outlined,
                        'Schedule',
                        _formatDate(
                          widget.booking['scheduled_at'] ??
                              widget.booking['created_at'],
                        ),
                        goldColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDetailItem(
                        Icons.access_time,
                        'Duration',
                        () {
                          final raw =
                              widget.booking['duration_minutes'] ??
                              service['duration_minutes'];
                          final mins = raw is int
                              ? raw
                              : int.tryParse(raw?.toString() ?? '') ?? 60;
                          return '${mins}m';
                        }(),
                        goldColor,
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white10, height: 28),
                _buildDetailItem(
                  Icons.location_on_outlined,
                  'Location',
                  location['address'] ?? 'Customer Location',
                  goldColor,
                ),
                const Divider(color: Colors.white10, height: 28),
                _buildDetailItem(
                  Icons.notes_rounded,
                  'NOTES',
                  widget.booking['customer_notes']?.toString().isNotEmpty ==
                          true
                      ? widget.booking['customer_notes']
                      : 'No special instructions',
                  goldColor,
                ),
                const Divider(color: Colors.white10, height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOTAL AMOUNT',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontSize: 10,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          NumberFormat.currency(
                            symbol: '₱',
                            decimalDigits: 2,
                          ).format(
                            double.tryParse(
                                  widget.booking['total_amount']
                                          ?.toString()
                                          .replaceAll(RegExp(r'[^0-9.]'), '') ??
                                      '0',
                                ) ??
                                0,
                          ),
                          style: TextStyle(
                            color: goldColor,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // Back Button
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context, 'switch_to_sessions'),
              child: Text(
                'BACK TO SESSIONS',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    try {
      DateTime dt = DateTime.parse(date.toString());
      return "${dt.day}/${dt.month}/${dt.year} at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return date.toString();
    }
  }

  String _getFriendlyStatus() {
    switch (_currentStatus) {
      case 'arrived':
        return 'READY TO START';
      case 'in_progress':
        return 'SESSION ACTIVE';
      case 'completed':
        return 'COMPLETED';
      default:
        return _currentStatus.replaceAll('_', ' ').toUpperCase();
    }
  }

  Widget _buildDetailItem(
    IconData icon,
    String label,
    String value,
    Color accentColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: accentColor.withOpacity(0.5)),
            const SizedBox(width: 8),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow() {
    final customer = widget.booking['customer'] ?? {};

    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: goldColor,
          backgroundImage: () {
            final normalized = ApiService.normalizePhotoUrl(
              customer['profile_photo_url'],
            );
            return normalized != null ? NetworkImage(normalized) : null;
          }(),
          child:
              ApiService.normalizePhotoUrl(customer['profile_photo_url']) ==
                  null
              ? const Icon(Icons.person, color: Colors.black)
              : null,
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                customer['middle_name'] != null &&
                        customer['middle_name'].toString().isNotEmpty
                    ? '${customer['first_name']} ${customer['middle_name']} ${customer['last_name']}'
                    : '${customer['first_name'] ?? 'Client'} ${customer['last_name'] ?? ''}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _getFriendlyStatus(),
                style: TextStyle(
                  color: goldColor.withOpacity(0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton() {
    String text = '';
    String nextStatus = '';

    switch (_currentStatus) {
      case 'accepted':
        if (_isStoreBooking) {
          text = 'START SESSION';
          nextStatus = 'in_progress';
        } else {
          text = 'START TRIP';
          nextStatus = 'en_route';
        }
        break;
      case 'en_route':
        text = 'I HAVE ARRIVED';
        nextStatus = 'arrived';
        break;
      case 'arrived':
        text = 'START SERVICE';
        nextStatus = 'in_progress';
        break;
      case 'in_progress':
        text = 'COMPLETE SERVICE';
        nextStatus = 'completed';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      height: 58,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            goldColor.withOpacity(0.8),
            goldColor,
            goldColor.withOpacity(0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: goldColor.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: -2,
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: () => _updateStatus(nextStatus),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildChatMessage(String text, bool isMe) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            constraints: const BoxConstraints(maxWidth: 250),
            decoration: BoxDecoration(
              color: isMe ? goldColor : Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMe ? 16 : 0),
                bottomRight: Radius.circular(isMe ? 0 : 16),
              ),
            ),
            child: Text(
              text,
              style: TextStyle(
                color: isMe ? Colors.black : Colors.white,
                fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isMe ? 'You' : 'Client',
            style: const TextStyle(color: Colors.white24, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildCountdownTimer() {
    final isTimeUp = _remainingSeconds == 0 && _timerStarted;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: goldColor.withOpacity(0.15), width: 1),
        boxShadow: [
          BoxShadow(
            color: isTimeUp
                ? Colors.redAccent.withOpacity(0.05)
                : goldColor.withOpacity(0.03),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TIME REMAINING',
                style: TextStyle(
                  color: goldColor.withOpacity(0.4),
                  fontSize: 11,
                  letterSpacing: 2.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isTimeUp ? "TIME'S UP" : _formatCountdown(_remainingSeconds),
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: isTimeUp ? Colors.redAccent : Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.w200, // Thinner for modern luxury look
                  letterSpacing: -1,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (isTimeUp ? Colors.redAccent : goldColor).withOpacity(
                0.05,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isTimeUp ? Icons.timer_off_outlined : Icons.timer_outlined,
              color: isTimeUp ? Colors.redAccent : goldColor,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripInfoOverlay() {
    if (_totalDistance.isEmpty && _totalDuration.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      bottom: 240,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: goldColor.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_totalDuration.isNotEmpty)
              Text(
                _totalDuration,
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            if (_totalDistance.isNotEmpty)
              Text(
                _totalDistance,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  void _onTravelModeChanged(String newMode) {
    if (_selectedTravelMode != newMode) {
      setState(() {
        _selectedTravelMode = newMode;
        // Optionally show loading while route updates
        _totalDistance = '...';
        _totalDuration = '...';
      });
      _fetchRoute();
    }
  }

  Widget _buildPreTripOverlay() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title and Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _selectedTravelMode == 'driving'
                      ? 'Car'
                      : _selectedTravelMode == 'bicycling'
                      ? 'Two-wheeler'
                      : 'Walking',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Route Options/Filter button
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.tune,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: _showRouteOptionsModal,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Close button (Optional/Mock)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: () {
                          // Could implement minimize/close logic later
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Vehicle Options Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildGoogleMapsModeOption(Icons.directions_car, 'driving'),
                const SizedBox(width: 24),
                _buildGoogleMapsModeOption(Icons.two_wheeler, 'bicycling'),
                const SizedBox(width: 24),
                _buildGoogleMapsModeOption(Icons.directions_walk, 'walking'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(color: Colors.white24, height: 1),
          // ETA and Distance Info
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: _totalDuration.isNotEmpty
                            ? _totalDuration
                            : '...',
                        style: TextStyle(
                          color:
                              _selectedTravelMode == 'driving' ||
                                  _selectedTravelMode == 'bicycling'
                              ? const Color(
                                  0xFFE5C07B,
                                ) // Gold-ish for driving/biking like in maps
                              : const Color(0xFF4CAF50), // Green for walking
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      TextSpan(
                        text:
                            ' (${_totalDistance.isNotEmpty ? _totalDistance : "..."})',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 20,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Fastest route now due to traffic conditions',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _updateStatus('en_route'),
                    icon: const Icon(Icons.navigation, color: Colors.black),
                    label: const Text(
                      'START JOURNEY',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: goldColor, // Apply app theme gold color
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showRouteOptionsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Route Options',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text(
                      'Avoid tolls',
                      style: TextStyle(color: Colors.white),
                    ),
                    activeColor: const Color(0xFF81D4FA),
                    value: _avoidTolls,
                    onChanged: (val) {
                      setState(() => _avoidTolls = val);
                      setModalState(() => _avoidTolls = val);
                      _onTravelModeChanged(
                        _selectedTravelMode,
                      ); // triggers refresh
                    },
                  ),
                  SwitchListTile(
                    title: const Text(
                      'Avoid highways',
                      style: TextStyle(color: Colors.white),
                    ),
                    activeColor: const Color(0xFF81D4FA),
                    value: _avoidHighways,
                    onChanged: (val) {
                      setState(() => _avoidHighways = val);
                      setModalState(() => _avoidHighways = val);
                      _onTravelModeChanged(
                        _selectedTravelMode,
                      ); // triggers refresh
                    },
                  ),
                  SwitchListTile(
                    title: const Text(
                      'Avoid ferries',
                      style: TextStyle(color: Colors.white),
                    ),
                    activeColor: const Color(0xFF81D4FA),
                    value: _avoidFerries,
                    onChanged: (val) {
                      setState(() => _avoidFerries = val);
                      setModalState(() => _avoidFerries = val);
                      _onTravelModeChanged(
                        _selectedTravelMode,
                      ); // triggers refresh
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildGoogleMapsModeOption(IconData icon, String mode) {
    final isSelected = _selectedTravelMode == mode;
    return GestureDetector(
      onTap: () => _onTravelModeChanged(mode),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? const Color(0xFF81D4FA) : Colors.white54,
                size: 20,
              ),
              const SizedBox(width: 8),
              if (_totalDuration.isNotEmpty)
                Text(
                  _totalDuration, // In a real app we'd fetch all 3 ETAs at once, but for now we show current
                  style: TextStyle(
                    color: isSelected
                        ? const Color(0xFF81D4FA)
                        : Colors.white54,
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                  ),
                )
              else
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white54,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (isSelected)
            Container(
              height: 3,
              width: 40,
              decoration: const BoxDecoration(
                color: Color(0xFF81D4FA),
                borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
              ),
            )
          else
            const SizedBox(height: 3),
        ],
      ),
    );
  }

  Widget _buildNavigationOverlay() {
    if (_routeSteps.isEmpty || _currentStepIndex >= _routeSteps.length) {
      return const SizedBox.shrink();
    }

    final step = _routeSteps[_currentStepIndex];
    final instruction = _stripHtml(step['html_instructions'] ?? '');
    final distance = step['distance']?['text'] ?? '';
    final maneuver = step['maneuver'] ?? '';

    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF004D40), // Dark Google Maps green
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(_getManeuverIcon(maneuver), color: Colors.white, size: 40),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    instruction,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (distance.isNotEmpty)
                    Text(
                      'Then in $distance',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _stripHtml(String htmlString) {
    RegExp exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);
    return htmlString.replaceAll(exp, '');
  }

  IconData _getManeuverIcon(String maneuver) {
    switch (maneuver) {
      case 'turn-slight-left':
      case 'turn-left':
        return Icons.turn_left;
      case 'turn-slight-right':
      case 'turn-right':
        return Icons.turn_right;
      case 'turn-sharp-left':
        return Icons.turn_sharp_left;
      case 'turn-sharp-right':
        return Icons.turn_sharp_right;
      case 'uturn-left':
      case 'uturn-right':
        return Icons.u_turn_left;
      case 'merge':
        return Icons.merge;
      case 'roundabout-left':
      case 'roundabout-right':
        return Icons.roundabout_right;
      case 'straight':
        return Icons.straight;
      case 'ramp-left':
      case 'ramp-right':
        return Icons.ramp_right;
      default:
        return Icons.navigation;
    }
  }
}

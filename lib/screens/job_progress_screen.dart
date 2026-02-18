import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../api_service.dart';
import '../chat_provider.dart';
import '../widgets/luxury_success_modal.dart';

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
    // Fetch initial chat messages and user ID
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        try {
          final profile = await _apiService.getProfile(widget.token);
          if (mounted) {
            setState(() {
              _currentUserId = profile['user']['id'];
            });

            // Initialize Echo for therapist
            final user = profile['user'];
            final providers = user?['providers'] as List?;
            final providerId = (providers != null && providers.isNotEmpty)
                ? providers[0]['id']
                : null;

            if (providerId != null) {
              await _apiService.initEcho(widget.token, providerId);
              // Start listening AFTER Echo is ready
              _initializeRealTimeEvents();
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
      if (mounted) {
        setState(() {
          _currentStatus = bookingData['status'];
        });
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
        setState(() {
          _currentStatus = data['booking_status'];
        });
        // If already in_progress (e.g. app restarted), sync timer from started_at
        if (data['booking_status'] == 'in_progress' && !_timerStarted) {
          final booking = data['booking'] as Map<String, dynamic>?;
          final rawBooking = booking?['duration_minutes'];
          final rawService = booking?['service']?['duration_minutes'];
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
    super.dispose();
  }

  void _startCountdown(int durationMinutes, {String? startedAt}) {
    if (_timerStarted) return;
    final totalSeconds = durationMinutes * 60;
    int initialRemaining = totalSeconds;

    // If we have the actual start time, compute elapsed to stay in sync
    if (startedAt != null) {
      try {
        final startTime = DateTime.parse(startedAt).toLocal();
        final elapsed = DateTime.now().difference(startTime).inSeconds;
        initialRemaining = (totalSeconds - elapsed).clamp(0, totalSeconds);
      } catch (_) {}
    }

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
        } else {
          timer.cancel();
        }
      });
    });
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
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
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
        builder: (context) => LuxurySuccessModal(
          isError: true,
          title: 'ERROR',
          message: e.toString().replaceAll('Exception: ', ''),
          onConfirm: () => Navigator.of(context).pop(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFD4AF37);

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
              markers: {
                Marker(
                  markerId: const MarkerId('client'),
                  position: _clientLocation,
                  infoWindow: const InfoWindow(title: 'Client Location'),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueAzure,
                  ),
                ),
                if (_currentPosition != null)
                  Marker(
                    markerId: const MarkerId('therapist'),
                    position: _currentPosition!,
                    infoWindow: const InfoWindow(title: 'Your Location'),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueYellow,
                    ),
                  ),
              },
            )
          else
            _buildDetailsView(goldColor),

          if (showMap)
            DraggableScrollableSheet(
              initialChildSize: 0.8,
              minChildSize: 0.22,
              maxChildSize: 0.9,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 20,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(24),
                    children: [
                      // Handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Client Info & Status Row
                      _buildInfoRow(),
                      const SizedBox(height: 24),

                      // Primary Action Button
                      _buildActionButton(),
                      const SizedBox(height: 32),

                      const Divider(color: Colors.white10, height: 1),
                      const SizedBox(height: 32),

                      // Chat Section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'CHAT WITH CLIENT',
                            style: TextStyle(
                              color: Color(0xFFD4AF37),
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'LIVE',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Chat Area
                      Consumer<ChatProvider>(
                        builder: (context, chatProvider, child) {
                          return Container(
                            height: 350,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.05),
                              ),
                            ),
                            child: Column(
                              children: [
                                Expanded(
                                  child: chatProvider.isLoading
                                      ? const Center(
                                          child: CircularProgressIndicator(
                                            color: Color(0xFFD4AF37),
                                          ),
                                        )
                                      : ListView.builder(
                                          controller: _chatScrollController,
                                          itemCount:
                                              chatProvider.messages.length,
                                          itemBuilder: (context, index) {
                                            final msg =
                                                chatProvider.messages[index];
                                            final bool isMe =
                                                msg.senderId == _currentUserId;
                                            return _buildChatMessage(
                                              msg.content,
                                              isMe,
                                            );
                                          },
                                        ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _messageController,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                          ),
                                          decoration: const InputDecoration(
                                            hintText: 'Type a message...',
                                            hintStyle: TextStyle(
                                              color: Colors.white24,
                                            ),
                                            border: InputBorder.none,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.send,
                                          color: Color(0xFFD4AF37),
                                          size: 20,
                                        ),
                                        onPressed: () {
                                          if (_messageController
                                              .text
                                              .isNotEmpty) {
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
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 400),
                    ],
                  ),
                );
              },
            ),
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
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Section - Centered Luxury Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF3A3A3A), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 10,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: goldColor,
                    boxShadow: [
                      BoxShadow(
                        color: goldColor.withOpacity(0.3),
                        blurRadius: 15,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey[900],
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
                            size: 50,
                            color: Colors.white54,
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  customer['middle_name'] != null &&
                          customer['middle_name'].toString().isNotEmpty
                      ? '${customer['first_name']} ${customer['middle_name']} ${customer['last_name']}'
                      : '${customer['first_name'] ?? 'Guest'} ${customer['last_name'] ?? ''}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: goldColor,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Text(
                    _getFriendlyStatus(),
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),

          // Countdown Timer (only when in_progress)
          if (_currentStatus == 'in_progress') ...[
            _buildCountdownTimer(),
            const SizedBox(height: 30),
          ],

          Text(
            'SERVICE DETAILS',
            style: TextStyle(
              color: const Color(0xFF505050),
              fontSize: 11,
              letterSpacing: 2.0,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          _buildDetailItem(
            Icons.spa,
            'Service',
            service['name'] ?? 'Luxury Treatment',
          ),
          _buildDetailItem(Icons.access_time, 'Duration', () {
            final raw =
                widget.booking['duration_minutes'] ??
                service['duration_minutes'];
            final mins = raw is int
                ? raw
                : int.tryParse(raw?.toString() ?? '') ?? 60;
            return '$mins Minutes Session';
          }()),
          if (widget.booking['scheduled_at'] != null)
            _buildDetailItem(
              Icons.calendar_today,
              'Scheduled',
              _formatDate(widget.booking['scheduled_at']),
            ),
          _buildDetailItem(
            Icons.payments,
            'Amount Due',
            '₱${widget.booking['total_amount'] ?? '0.00'}',
          ),
          _buildDetailItem(
            Icons.location_on,
            'Location',
            location['address'] ?? 'Customer Location',
          ),
          if (widget.booking['customer_notes'] != null &&
              widget.booking['customer_notes'].toString().isNotEmpty)
            _buildDetailItem(
              Icons.menu,
              'Notes',
              widget.booking['customer_notes'],
            ),

          const SizedBox(height: 40),

          // Control Buttons
          _buildActionButton(),
          const SizedBox(height: 16),
          const SizedBox(height: 24),
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

  Widget _buildDetailItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFD4AF37), size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF4A4A4A),
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow() {
    final customer = widget.booking['customer'] ?? {};
    final location = widget.booking['location'] ?? {};

    return Row(
      children: [
        const CircleAvatar(radius: 25, child: Icon(Icons.person)),
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
                location['address'] ?? 'Client Location',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              'STATUS',
              style: TextStyle(color: Colors.grey, fontSize: 10),
            ),
            Text(
              _currentStatus.toUpperCase(),
              style: const TextStyle(
                color: Color(0xFFD4AF37),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton() {
    String text = '';
    String nextStatus = '';
    const goldColor = Color(0xFFD4AF37);

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

    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: () => _updateStatus(nextStatus),
        style: ElevatedButton.styleFrom(
          backgroundColor: goldColor,
          foregroundColor: Colors.black,
          elevation: 10,
          shadowColor: goldColor.withOpacity(0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _buildChatMessage(String text, bool isMe) {
    const goldColor = Color(0xFFD4AF37);
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
    const goldColor = Color(0xFFD4AF37);
    final service = widget.booking['service'] ?? {};
    final rawBooking = widget.booking['duration_minutes'];
    final rawService = service['duration_minutes'];
    final rawDuration = rawBooking ?? rawService;
    final durationMinutes = rawDuration is int
        ? rawDuration
        : int.tryParse(rawDuration?.toString() ?? '') ?? 60;
    final totalSeconds = durationMinutes * 60;
    final isTimeUp = _remainingSeconds == 0 && _timerStarted;
    final progress = totalSeconds > 0 ? _remainingSeconds / totalSeconds : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isTimeUp
              ? Colors.red.withOpacity(0.5)
              : goldColor.withOpacity(0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: isTimeUp
                ? Colors.red.withOpacity(0.1)
                : goldColor.withOpacity(0.05),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'SESSION TIMER',
            style: TextStyle(
              color: goldColor.withOpacity(0.7),
              fontSize: 11,
              letterSpacing: 2.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 160,
            height: 160,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background ring
                SizedBox(
                  width: 160,
                  height: 160,
                  child: CircularProgressIndicator(
                    value: 1.0,
                    strokeWidth: 8,
                    color: Colors.white.withOpacity(0.05),
                  ),
                ),
                // Progress ring
                SizedBox(
                  width: 160,
                  height: 160,
                  child: CircularProgressIndicator(
                    value: progress.toDouble(),
                    strokeWidth: 8,
                    strokeCap: StrokeCap.round,
                    color: isTimeUp ? Colors.red : goldColor,
                  ),
                ),
                // Time display
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          isTimeUp
                              ? "TIME'S\nUP"
                              : _formatCountdown(_remainingSeconds),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isTimeUp ? Colors.red : Colors.white,
                            fontSize: isTimeUp ? 20 : 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: isTimeUp ? 1.0 : 2,
                            height: 1.1,
                          ),
                        ),
                      ),
                      if (!isTimeUp)
                        Text(
                          'REMAINING',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontSize: 9,
                            letterSpacing: 1.5,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '$durationMinutes MIN SESSION',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 11,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../api_service.dart';
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
  late bool _isStoreBooking;

  late LatLng _clientLocation;

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
      }
    } catch (e) {
      debugPrint('Error fetching latest status: $e');
    }
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
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
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 10,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildInfoRow(),
                    const SizedBox(height: 20),
                    _buildActionButton(),
                  ],
                ),
              ),
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
                    backgroundImage: customer['profile_photo_url'] != null
                        ? NetworkImage(
                            ApiService.normalizePhotoUrl(
                              customer['profile_photo_url'],
                            )!,
                          )
                        : null,
                    child: customer['profile_photo_url'] == null
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
                  '${customer['first_name'] ?? 'Guest'} ${customer['last_name'] ?? ''}',
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
                '${customer['first_name'] ?? 'Client'} ${customer['last_name'] ?? ''}',
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
}

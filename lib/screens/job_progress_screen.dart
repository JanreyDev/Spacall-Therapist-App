import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../api_service.dart';

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

  late LatLng _clientLocation;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.booking['status'];
    final loc = widget.booking['location'];
    _clientLocation = LatLng(
      double.parse(loc['latitude'].toString()),
      double.parse(loc['longitude'].toString()),
    );
    _startTracking();
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
      if (status == 'completed' || status == 'cancelled') {
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update status: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFD4AF37);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Job Progress'),
        backgroundColor: Colors.black,
        foregroundColor: goldColor,
      ),
      body: Stack(
        children: [
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
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A1A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
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

  Widget _buildInfoRow() {
    final customer = widget.booking['customer'];
    return Row(
      children: [
        const CircleAvatar(radius: 25, child: Icon(Icons.person)),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${customer['first_name']} ${customer['last_name']}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                widget.booking['location']['address'],
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
    Color color = Colors.green;

    switch (_currentStatus) {
      case 'accepted':
        text = 'START TRIP';
        nextStatus = 'en_route';
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
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

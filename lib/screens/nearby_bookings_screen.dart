import 'package:flutter/material.dart';
import '../api_service.dart';

class NearbyBookingsScreen extends StatefulWidget {
  final String token;

  const NearbyBookingsScreen({super.key, required this.token});

  @override
  State<NearbyBookingsScreen> createState() => _NearbyBookingsScreenState();
}

class _NearbyBookingsScreenState extends State<NearbyBookingsScreen> {
  final _apiService = ApiService();
  List<dynamic> _bookings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchBookings();
  }

  Future<void> _fetchBookings() async {
    setState(() => _isLoading = true);
    try {
      // For development/web, ensure we have a location record
      await _apiService.updateLocation(
        token: widget.token,
        latitude: 14.5995,
        longitude: 120.9842,
      );

      final response = await _apiService.getNearbyBookings(token: widget.token);
      setState(() {
        _bookings = response['bookings'];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
      setState(() => _isLoading = false);
    }
  }

  Future<void> _acceptBooking(int bookingId) async {
    try {
      await _apiService.updateBookingStatus(
        token: widget.token,
        bookingId: bookingId,
        status: 'accepted',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Booking accepted!')));
      _fetchBookings(); // Refresh list
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Available Jobs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchBookings,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _bookings.isEmpty
          ? const Center(child: Text('No nearby jobs found.'))
          : ListView.builder(
              itemCount: _bookings.length,
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final booking = _bookings[index];
                final customer = booking['customer'];
                final service = booking['service'];
                final location = booking['location'];

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              service['name'],
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '₱${booking['total_amount']}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const Divider(),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.person),
                          title: Text(
                            "${customer['first_name']} ${customer['last_name']}",
                          ),
                          subtitle: Text(location['address']),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => _acceptBooking(booking['id']),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Accept Job'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

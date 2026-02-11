import 'package:flutter/material.dart';
import '../api_service.dart';
import '../widgets/luxury_success_modal.dart';
import 'job_progress_screen.dart';

class NearbyBookingsScreen extends StatefulWidget {
  final String token;
  final bool isTab;

  const NearbyBookingsScreen({
    super.key,
    required this.token,
    this.isTab = false,
  });

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
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.getNearbyBookings(token: widget.token);
      if (!mounted) return;
      setState(() {
        _bookings = response['bookings'];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => LuxurySuccessModal(
          isError: true,
          title: 'ERROR',
          message: e.toString().replaceAll('Exception: ', ''),
          onConfirm: () => Navigator.of(context).pop(),
        ),
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _acceptBooking(int bookingId) async {
    try {
      final response = await _apiService.updateBookingStatus(
        token: widget.token,
        bookingId: bookingId,
        status: 'accepted',
      );
      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => LuxurySuccessModal(
          title: 'SUCCESS',
          message: 'Booking ACCEPTED! You can now start your journey.',
          onConfirm: () {
            debugPrint('Acceptance modal: continuing to map...');
            Navigator.of(dialogContext).pop(); // Close modal
            Navigator.push(
              context, // Use screen context
              MaterialPageRoute(
                builder: (context) => JobProgressScreen(
                  booking: response['booking'],
                  token: widget.token,
                ),
              ),
            ).then((result) {
              if (result == 'switch_to_sessions') {
                Navigator.pop(context, 'switch_to_sessions');
              }
              _fetchBookings();
            });
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
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

    final content = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _bookings.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.explore_off_outlined,
                  size: 64,
                  color: Colors.grey.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No nearby jobs found',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          )
        : RefreshIndicator(
            onRefresh: _fetchBookings,
            child: ListView.builder(
              itemCount: _bookings.length,
              padding: const EdgeInsets.all(24),
              itemBuilder: (context, index) {
                final booking = _bookings[index];
                final customer = booking['customer'];
                final service = booking['service'];
                final location = booking['location'];

                return Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: goldColor.withOpacity(0.2)),
                  ),
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
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: goldColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: Colors.white10),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline,
                            size: 16,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "${customer['first_name']} ${customer['last_name']}",
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              location['address'],
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFB8860B), goldColor],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ElevatedButton(
                          onPressed: () => _acceptBooking(booking['id']),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Accept Job',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );

    if (widget.isTab) {
      return Padding(padding: const EdgeInsets.only(top: 40), child: content);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Jobs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchBookings,
          ),
        ],
      ),
      body: content,
    );
  }
}

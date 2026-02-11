import 'package:flutter/material.dart';
import '../api_service.dart';
import 'job_progress_screen.dart';

class ActiveRequestsScreen extends StatefulWidget {
  final String token;

  const ActiveRequestsScreen({super.key, required this.token});

  @override
  State<ActiveRequestsScreen> createState() => _ActiveRequestsScreenState();
}

class _ActiveRequestsScreenState extends State<ActiveRequestsScreen> {
  final _apiService = ApiService();
  List<dynamic> _requests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  Future<void> _fetchRequests() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.getActiveRequests(token: widget.token);
      setState(() {
        _requests = response['bookings'];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      _showLuxuryDialog(
        e.toString().replaceAll('Exception: ', ''),
        isError: true,
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleStatusUpdate(int bookingId, String status) async {
    try {
      final response = await _apiService.updateBookingStatus(
        token: widget.token,
        bookingId: bookingId,
        status: status,
      );

      if (!mounted) return;

      if (status == 'accepted') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => JobProgressScreen(
              booking: response['booking'],
              token: widget.token,
            ),
          ),
        );
      } else {
        _showLuxuryDialog('Booking ${status.toUpperCase()}!');
        _fetchRequests(); // Refresh list
      }
    } catch (e) {
      if (!mounted) return;
      _showLuxuryDialog(
        e.toString().replaceAll('Exception: ', ''),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Direct Booking Requests'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchRequests,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No new direct requests.'),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _requests.length,
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final booking = _requests[index];
                final customer = booking['customer'];
                final service = booking['service'];
                final location = booking['location'];

                return Card(
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'VIP DIRECT REQUEST',
                                style: TextStyle(
                                  color: Colors.blue,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
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
                        const SizedBox(height: 12),
                        Text(
                          service['name'],
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Divider(),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            child: Icon(Icons.person),
                          ),
                          title: Text(
                            "${customer['first_name']} ${customer['last_name']}",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(location['address']),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _handleStatusUpdate(
                                  booking['id'],
                                  'cancelled',
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.all(16),
                                  side: const BorderSide(color: Colors.red),
                                  foregroundColor: Colors.red,
                                ),
                                child: const Text('Decline'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _handleStatusUpdate(
                                  booking['id'],
                                  'accepted',
                                ),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.all(16),
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Accept'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showLuxuryDialog(String message, {bool isError = false}) {
    const goldColor = Color(0xFFD4AF37);
    showDialog(
      context: context,
      barrierDismissible: !isError,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: (isError ? Colors.redAccent : goldColor).withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.check_circle_outline,
                color: isError ? Colors.redAccent : goldColor,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                isError ? 'ERROR' : 'SUCCESS',
                style: const TextStyle(
                  color: goldColor,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: isError
                          ? [
                              Colors.redAccent.withOpacity(0.8),
                              Colors.redAccent,
                            ]
                          : [
                              const Color(0xFFB8860B),
                              goldColor,
                              const Color(0xFFFFD700),
                            ],
                    ),
                  ),
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'CONTINUE',
                      style: TextStyle(
                        color: isError ? Colors.white : Colors.black,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../api_service.dart';
import 'job_progress_screen.dart';

class ActiveRequestsScreen extends StatefulWidget {
  final String token;
  final bool isTab;

  const ActiveRequestsScreen({
    super.key,
    required this.token,
    this.isTab = false,
  });

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
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.getActiveRequests(token: widget.token);
      if (!mounted) return;
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
        Navigator.pushReplacement(
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
    final content = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _requests.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.notifications_none_rounded,
                  size: 64,
                  color: Colors.grey.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No new direct requests',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          )
        : RefreshIndicator(
            onRefresh: _fetchRequests,
            child: ListView.builder(
              itemCount: _requests.length,
              padding: const EdgeInsets.all(24),
              itemBuilder: (context, index) {
                final booking = _requests[index];
                final customer = booking['customer'];
                final service = booking['service'];
                final location = booking['location'];

                return Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFFD4AF37).withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD4AF37).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'VIP DIRECT',
                              style: TextStyle(
                                color: Color(0xFFD4AF37),
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                          Text(
                            '₱${booking['total_amount']}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD4AF37),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        service['name'],
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => _handleStatusUpdate(
                                booking['id'],
                                'cancelled',
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red.shade300,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                              child: const Text('Decline'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFB8860B),
                                    Color(0xFFD4AF37),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ElevatedButton(
                                onPressed: () => _handleStatusUpdate(
                                  booking['id'],
                                  'accepted',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Accept',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                        ],
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
        title: const Text('Direct Requests'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchRequests,
          ),
        ],
      ),
      body: content,
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

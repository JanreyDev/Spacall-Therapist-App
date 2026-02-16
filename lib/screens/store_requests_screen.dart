import 'package:flutter/material.dart';
import '../api_service.dart';
import '../widgets/luxury_success_modal.dart';
import 'job_progress_screen.dart';

class StoreRequestsScreen extends StatefulWidget {
  final String token;
  final bool isTab;
  final Function(int)? onTabSwitch;

  const StoreRequestsScreen({
    super.key,
    required this.token,
    this.isTab = false,
    this.onTabSwitch,
  });

  @override
  State<StoreRequestsScreen> createState() => _StoreRequestsScreenState();
}

class _StoreRequestsScreenState extends State<StoreRequestsScreen> {
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
      final response = await _apiService.getActiveRequests(
        token: widget.token,
        bookingType: 'in_store',
      );
      if (!mounted) return;
      setState(() {
        _requests = response['bookings'];
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

  Future<void> _handleStatusUpdate(int bookingId, String status) async {
    try {
      final response = await _apiService.updateBookingStatus(
        token: widget.token,
        bookingId: bookingId,
        status: status,
      );

      if (!mounted) return;

      if (status == 'accepted') {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => LuxurySuccessModal(
            title: 'SUCCESS',
            message: 'Appointment CONFIRMED! Client is expecting you.',
            onConfirm: () {
              Navigator.of(dialogContext).pop();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => JobProgressScreen(
                    booking: response['booking'],
                    token: widget.token,
                  ),
                ),
              ).then((result) {
                if (result == 'switch_to_sessions') {
                  if (widget.isTab && widget.onTabSwitch != null) {
                    widget.onTabSwitch!(0); // Redirect to Home as requested
                  } else {
                    Navigator.pop(context, 'switch_to_sessions');
                  }
                }
                _fetchRequests();
              });
            },
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (dialogContext) => LuxurySuccessModal(
            title: 'SUCCESS',
            message: 'Appointment ${status.toUpperCase()}!',
            onConfirm: () {
              Navigator.of(dialogContext).pop();
              _fetchRequests();
            },
          ),
        );
      }
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

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    try {
      DateTime dt = DateTime.parse(date.toString());
      return "${dt.day}/${dt.month}/${dt.year} at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return date.toString();
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
                  Icons.storefront_outlined,
                  size: 64,
                  color: Colors.grey.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No store appointments',
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
                              'STORE APPOINTMENT',
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
                            (customer['middle_name'] != null &&
                                    customer['middle_name']
                                        .toString()
                                        .isNotEmpty)
                                ? "${customer['first_name']} ${customer['middle_name']} ${customer['last_name']}"
                                : "${customer['first_name']} ${customer['last_name']}",
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
                      if (booking['scheduled_at'] != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today_outlined,
                              size: 16,
                              color: Color(0xFFD4AF37),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Scheduled: ${_formatDate(booking['scheduled_at'])}",
                              style: const TextStyle(
                                color: Color(0xFFD4AF37),
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
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
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Store Appointments'),
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
}

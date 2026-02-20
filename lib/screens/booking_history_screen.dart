import 'package:flutter/material.dart';
import 'dart:async';
import '../api_service.dart';
import 'package:intl/intl.dart';
import 'job_progress_screen.dart';

class BookingHistoryScreen extends StatefulWidget {
  final String token;
  final bool showAppBar;

  const BookingHistoryScreen({
    super.key,
    required this.token,
    this.showAppBar = true,
  });

  @override
  State<BookingHistoryScreen> createState() => _BookingHistoryScreenState();
}

class _BookingHistoryScreenState extends State<BookingHistoryScreen> {
  final ApiService _apiService = ApiService();
  List<dynamic> _currentBookings = [];
  List<dynamic> _historyBookings = [];
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchBookings();
    _startPolling();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted) {
        _fetchBookings();
      }
    });
  }

  Future<void> _fetchBookings() async {
    try {
      final data = await _apiService.getCurrentBookings(token: widget.token);
      if (mounted) {
        setState(() {
          _currentBookings = data['current'] ?? [];
          _historyBookings = data['history'] ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching bookings: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFD4AF37);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Session History'),
              backgroundColor: Colors.black,
              foregroundColor: goldColor,
            )
          : null,
      body: _isLoading && _currentBookings.isEmpty && _historyBookings.isEmpty
          ? const Center(child: CircularProgressIndicator(color: goldColor))
          : RefreshIndicator(
              onRefresh: _fetchBookings,
              color: goldColor,
              child: _buildBody(goldColor),
            ),
    );
  }

  Widget _buildBody(Color goldColor) {
    if (_currentBookings.isEmpty && _historyBookings.isEmpty) {
      return ListView(
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.3),
          const Icon(Icons.history_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'No sessions found',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      children: [
        _buildHeader(goldColor),
        const SizedBox(height: 32),
        if (_currentBookings.isNotEmpty) ...[
          _buildSectionHeader('CURRENT SESSIONS', goldColor),
          const SizedBox(height: 12),
          ..._currentBookings.map((b) => _buildBookingCard(b, true)),
          const SizedBox(height: 24),
        ],
        _buildSectionHeader('SESSION HISTORY', goldColor),
        const SizedBox(height: 12),
        if (_historyBookings.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                'No past sessions',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ..._historyBookings.map((b) => _buildBookingCard(b, false)),
      ],
    );
  }

  Widget _buildHeader(Color goldColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "MY SESSIONS",
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              "Session History",
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: goldColor.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: goldColor.withOpacity(0.2)),
          ),
          child: Icon(Icons.history_rounded, color: goldColor, size: 28),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, Color goldColor) {
    return Text(
      title,
      style: TextStyle(
        color: goldColor,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildBookingCard(dynamic booking, bool isCurrent) {
    const goldColor = Color(0xFFD4AF37);
    final serviceName = booking['service']['name'];
    final statusText = _getStatusText(booking['status']);
    final dateStr = booking['created_at'];
    final date = DateTime.parse(dateStr);
    final formattedDate = DateFormat('MMM dd, yyyy - hh:mm a').format(date);
    final cust = booking['customer'];
    final customer = cust != null
        ? (cust['middle_name'] != null &&
                  cust['middle_name'].toString().isNotEmpty
              ? "${cust['first_name']} ${cust['middle_name']} ${cust['last_name']}"
              : "${cust['first_name']} ${cust['last_name']}")
        : "Customer Not Found";

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: goldColor.withOpacity(0.3), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: goldColor.withOpacity(0.05),
            blurRadius: 15,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  serviceName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _getStatusColor(booking['status']).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusText.toUpperCase(),
                  style: TextStyle(
                    color: _getStatusColor(booking['status']),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.person_outline, size: 16, color: goldColor),
              const SizedBox(width: 8),
              Text(customer, style: const TextStyle(color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.access_time, size: 16, color: goldColor),
              const SizedBox(width: 8),
              Text(
                formattedDate,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                NumberFormat.currency(symbol: '₱', decimalDigits: 2).format(
                  double.tryParse(
                        booking['total_amount']?.toString().replaceAll(
                              RegExp(r'[^0-9.]'),
                              '',
                            ) ??
                            '0',
                      ) ??
                      0,
                ),
                style: const TextStyle(
                  color: goldColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (isCurrent)
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => JobProgressScreen(
                          booking: booking,
                          token: widget.token,
                        ),
                      ),
                    ).then((_) => _fetchBookings());
                  },
                  child: const Text(
                    'VIEW PROGRESS',
                    style: TextStyle(color: Colors.blue),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      case 'accepted':
      case 'en_route':
        return Colors.blue;
      case 'arrived':
      case 'in_progress':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'accepted':
        return 'BOOKING ACCEPTED';
      case 'en_route':
        return 'EN ROUTE';
      case 'arrived':
        return 'ARRIVED';
      case 'in_progress':
        return 'IN PROGRESS';
      case 'completed':
        return 'COMPLETED';
      case 'cancelled':
        return 'CANCELLED';
      default:
        return status.replaceAll('_', ' ').toUpperCase();
    }
  }
}

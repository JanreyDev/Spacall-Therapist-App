import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class BookingDetailsModal extends StatelessWidget {
  final Map<String, dynamic> booking;

  const BookingDetailsModal({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFD4AF37);
    const backgroundColor = Color(0xFF1A1A1A);
    const cardColor = Color(0xFF242424);

    final customer = booking['customer'] ?? {};
    final service = booking['service'] ?? {};
    final location = booking['location'] ?? {};
    final metadata = booking['metadata'] ?? {};

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: goldColor.withOpacity(0.2), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [goldColor.withOpacity(0.1), Colors.transparent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'BOOKING DETAILS',
                      style: TextStyle(
                        color: goldColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Service Info
                    _buildSectionHeader('SERVICE'),
                    _buildInfoCard(cardColor, [
                      _buildDetailRow(
                        Icons.spa_outlined,
                        'Service',
                        service['name'] ?? 'N/A',
                        goldColor,
                      ),
                      _buildDetailRow(
                        Icons.timer_outlined,
                        'Duration',
                        '${service['duration_minutes'] ?? '60'} mins',
                        null,
                      ),
                      _buildDetailRow(
                        Icons.payments_outlined,
                        'Total Amount',
                        NumberFormat.currency(
                          symbol: '₱',
                          decimalDigits: 2,
                        ).format(
                          double.tryParse(
                                booking['total_amount']?.toString().replaceAll(
                                      RegExp(r'[^0-9.]'),
                                      '',
                                    ) ??
                                    '0',
                              ) ??
                              0,
                        ),
                        goldColor,
                      ),
                    ]),

                    const SizedBox(height: 24),

                    // Customer Info
                    _buildSectionHeader('CUSTOMER'),
                    _buildInfoCard(cardColor, [
                      _buildDetailRow(
                        Icons.person_outline,
                        'Name',
                        "${customer['first_name'] ?? ''} ${customer['last_name'] ?? ''}"
                            .trim(),
                        null,
                      ),
                      if (customer['gender'] != null)
                        _buildDetailRow(
                          Icons.wc_outlined,
                          'Gender',
                          customer['gender'].toString().toUpperCase(),
                          null,
                        ),
                    ]),

                    const SizedBox(height: 24),

                    // Location Info
                    _buildSectionHeader('LOCATION'),
                    _buildInfoCard(cardColor, [
                      _buildDetailRow(
                        Icons.location_on_outlined,
                        'Address',
                        location['address'] ?? 'N/A',
                        null,
                        isLong: true,
                      ),
                      if (location['notes'] != null &&
                          location['notes'].toString().isNotEmpty)
                        _buildDetailRow(
                          Icons.note_alt_outlined,
                          'Directions',
                          location['notes'],
                          null,
                          isLong: true,
                        ),
                    ]),

                    const SizedBox(height: 24),

                    // Preferences / Metadata
                    if (metadata.isNotEmpty || booking['notes'] != null) ...[
                      _buildSectionHeader('PREFERENCES'),
                      _buildInfoCard(cardColor, [
                        if (metadata['intensity'] != null)
                          _buildDetailRow(
                            Icons.speed_outlined,
                            'Intensity',
                            metadata['intensity'].toString(),
                            null,
                          ),
                        if (metadata['therapist_gender'] != null)
                          _buildDetailRow(
                            Icons.face_outlined,
                            'Preferred Gender',
                            metadata['therapist_gender']
                                .toString()
                                .toUpperCase(),
                            null,
                          ),
                        if (booking['notes'] != null &&
                            booking['notes'].toString().isNotEmpty)
                          _buildDetailRow(
                            Icons.edit_note_outlined,
                            'Client Notes',
                            booking['notes'],
                            null,
                            isLong: true,
                          ),
                      ]),
                    ],

                    if (booking['scheduled_at'] != null) ...[
                      const SizedBox(height: 24),
                      _buildSectionHeader('SCHEDULE'),
                      _buildInfoCard(cardColor, [
                        _buildDetailRow(
                          Icons.calendar_today_outlined,
                          'Date/Time',
                          _formatDate(booking['scheduled_at']),
                          goldColor,
                        ),
                      ]),
                    ],

                    const SizedBox(height: 32),

                    // Action Button (Close)
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: goldColor,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'CLOSE',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.white.withOpacity(0.4),
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildInfoCard(Color color, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: children.asMap().entries.map((entry) {
          int index = entry.key;
          Widget child = entry.value;
          return Column(
            children: [
              child,
              if (index < children.length - 1)
                const Divider(color: Colors.white10, height: 24),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String label,
    String value,
    Color? valueColor, {
    bool isLong = false,
  }) {
    return Row(
      crossAxisAlignment: isLong
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: const Color(0xFFD4AF37).withOpacity(0.7)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: valueColor ?? Colors.white.withOpacity(0.9),
                  fontSize: 14,
                  fontWeight: valueColor != null
                      ? FontWeight.bold
                      : FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    try {
      DateTime dt = DateTime.parse(date.toString());
      return DateFormat('MMM dd, yyyy - hh:mm a').format(dt);
    } catch (e) {
      return date.toString();
    }
  }
}

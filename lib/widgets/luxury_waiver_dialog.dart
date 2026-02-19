import 'package:flutter/material.dart';
import 'dart:ui';

class LuxuryWaiverDialog extends StatefulWidget {
  final VoidCallback onAccepted;

  const LuxuryWaiverDialog({super.key, required this.onAccepted});

  @override
  State<LuxuryWaiverDialog> createState() => _LuxuryWaiverDialogState();
}

class _LuxuryWaiverDialogState extends State<LuxuryWaiverDialog> {
  bool _isAccepted = false;
  final ScrollController _scrollController = ScrollController();

  static const Color goldColor = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent dismissing without accepting
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: goldColor.withOpacity(0.5), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: goldColor.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.gavel_outlined,
                      color: goldColor,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "WELCOME TO SPACALL",
                            style: TextStyle(
                              color: goldColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Therapist Terms & Agreements",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Flexible(
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionTitle("1. INDEPENDENT CONTRACTOR"),
                        _buildParagraph(
                          "You acknowledge that you are an independent contractor and not an employee of Spacall. You are responsible for your own taxes, insurance, and equipment.",
                        ),
                        _buildSectionTitle("2. PROFESSIONAL CONDUCT"),
                        _buildParagraph(
                          "You agree to maintain the highest standards of professionalism, hygiene, and ethics. Any reports of misconduct will result in immediate suspension pending investigation.",
                        ),
                        _buildSectionTitle("3. SAFETY & SECURITY"),
                        _buildParagraph(
                          "You agree to follow all safety protocols. Spacall tracks location for safety purposes during active bookings only.",
                        ),
                        _buildSectionTitle("4. COMMISSION & PAYMENTS"),
                        _buildParagraph(
                          "Commissions are deducted automatically. Payouts are processed according to the platform schedule.",
                        ),
                        _buildSectionTitle("5. LIABILITY"),
                        _buildParagraph(
                          "You agree to indemnify and hold harmless Spacall from any claims arising from your provision of services.",
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.redAccent.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  "By proceeding, you confirm you have read and understood these terms.",
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
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
              ),

              // Footer
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(24),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: goldColor.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isAccepted = !_isAccepted;
                        });
                      },
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: _isAccepted
                                  ? goldColor
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _isAccepted ? goldColor : Colors.white54,
                                width: 2,
                              ),
                            ),
                            child: _isAccepted
                                ? const Icon(
                                    Icons.check,
                                    size: 16,
                                    color: Colors.black,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "I agree to the Terms & Conditions",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isAccepted ? widget.onAccepted : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: goldColor,
                          disabledBackgroundColor: Colors.white12,
                          foregroundColor: Colors.black,
                          elevation: _isAccepted ? 5 : 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          "ACCESS DASHBOARD",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            color: _isAccepted ? Colors.black : Colors.white30,
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

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: goldColor,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildParagraph(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withOpacity(0.8),
        fontSize: 14,
        height: 1.5,
      ),
    );
  }
}

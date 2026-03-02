import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme_provider.dart';
import '../api_service.dart';
import '../widgets/luxury_success_modal.dart';

class WithdrawScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final double currentBalance;

  const WithdrawScreen({
    super.key,
    required this.userData,
    required this.currentBalance,
  });

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _accountNameController = TextEditingController();
  final TextEditingController _accountNumberController =
      TextEditingController();

  String _selectedMethod = 'GCash';
  bool _isSubmitting = false;
  late double _balance;

  final List<Map<String, dynamic>> _payoutMethods = [
    {
      'name': 'GCash',
      'icon': Icons.account_balance_wallet_rounded,
      'color': Color(0xFF007DFE),
    },
    {
      'name': 'Maya',
      'icon': Icons.account_balance_wallet_outlined,
      'color': Color(0xFF00FF41),
    },
    {
      'name': 'Bank Transfer',
      'icon': Icons.account_balance_rounded,
      'color': Color(0xFFEBC14F),
    },
    {
      'name': 'Paymongo',
      'icon': Icons.bolt_rounded,
      'color': Color(0xFF6A0DAD),
    },
  ];

  @override
  void initState() {
    super.initState();
    _balance = widget.currentBalance;
  }

  Future<void> _handleWithdraw() async {
    final amount =
        double.tryParse(_amountController.text.replaceAll(',', '')) ?? 0.0;
    final accName = _accountNameController.text.trim();
    final accNum = _accountNumberController.text.trim();

    if (amount <= 0) {
      _showError('Please enter a valid amount');
      return;
    }

    if (amount > _balance) {
      _showError('Insufficient balance');
      return;
    }

    if (accName.isEmpty || accNum.isEmpty) {
      _showError('Please complete account details');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final response = await _apiService.withdraw(
        token: widget.userData['token'],
        amount: amount,
        method: _selectedMethod,
        accountDetails: 'Name: $accName\nAccount: $accNum',
      );

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        if (response['balance'] != null) {
          _balance =
              double.tryParse(response['balance'].toString()) ??
              (_balance - amount);
        } else {
          _balance -= amount;
        }
      });

      showDialog(
        context: context,
        builder: (context) => LuxurySuccessModal(
          title: 'WITHDRAWAL SUBMITTED',
          message:
              'Your request for ₱${NumberFormat('#,##0.00').format(amount)} has been received and is being processed.',
          buttonText: 'DONE',
          onConfirm: () {
            Navigator.of(context).pop(); // Close modal
            Navigator.of(context).pop(true); // Return to home with success flag
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showError(
        'Withdrawal failed: ${e.toString().replaceAll("Exception: ", "")}',
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final goldColor = themeProvider.goldColor;

    return Scaffold(
      backgroundColor: themeProvider.backgroundColor,
      body: Stack(
        children: [
          // Background Gradient
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: goldColor.withOpacity(0.05),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: goldColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'WITHDRAW FUNDS',
                        style: GoogleFonts.outfit(
                          color: goldColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),

                        // Balance Card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                goldColor.withOpacity(0.15),
                                Colors.transparent,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: goldColor.withOpacity(0.1),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'AVAILABLE BALANCE',
                                style: TextStyle(
                                  color: goldColor.withOpacity(0.5),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '₱${NumberFormat('#,##0.00').format(_balance)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -1,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 40),

                        // Amount Input
                        Text(
                          'AMOUNT TO WITHDRAW',
                          style: TextStyle(
                            color: goldColor.withOpacity(0.3),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.05),
                            ),
                          ),
                          child: TextField(
                            controller: _amountController,
                            keyboardType: TextInputType.number,
                            style: TextStyle(
                              color: goldColor,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                            ),
                            decoration: InputDecoration(
                              hintText: '0.00',
                              hintStyle: TextStyle(color: Colors.white12),
                              prefixText: '₱ ',
                              prefixStyle: TextStyle(
                                color: goldColor,
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                              ),
                              border: InputBorder.none,
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Method Selection
                        Text(
                          'SELECT PAYOUT METHOD',
                          style: TextStyle(
                            color: goldColor.withOpacity(0.3),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 100,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _payoutMethods.length,
                            itemBuilder: (context, index) {
                              final method = _payoutMethods[index];
                              final isSelected =
                                  _selectedMethod == method['name'];
                              return GestureDetector(
                                onTap: () => setState(
                                  () => _selectedMethod = method['name'],
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  width: 100,
                                  margin: const EdgeInsets.only(right: 12),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? method['color'].withOpacity(0.15)
                                        : Colors.white.withOpacity(0.02),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: isSelected
                                          ? method['color'].withOpacity(0.5)
                                          : Colors.white.withOpacity(0.05),
                                      width: 2,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        method['icon'],
                                        color: isSelected
                                            ? method['color']
                                            : Colors.white38,
                                        size: 28,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        method['name'],
                                        style: TextStyle(
                                          color: isSelected
                                              ? Colors.white
                                              : Colors.white38,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 40),

                        // Account Details Card
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.02),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.05),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'RECEIVING ACCOUNT',
                                style: TextStyle(
                                  color: goldColor.withOpacity(0.5),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(height: 24),
                              _buildTextField(
                                controller: _accountNameController,
                                label: 'Account Full Name',
                                icon: Icons.person_outline_rounded,
                                goldColor: goldColor,
                              ),
                              const SizedBox(height: 24),
                              _buildTextField(
                                controller: _accountNumberController,
                                label: _selectedMethod == 'Bank Transfer'
                                    ? 'Bank Account Number'
                                    : 'Mobile Number',
                                icon: Icons.credit_card_rounded,
                                goldColor: goldColor,
                                isNumeric: _selectedMethod != 'Bank Transfer',
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 40),

                        // Action Button
                        GestureDetector(
                          onTap: _isSubmitting ? null : _handleWithdraw,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: double.infinity,
                            height: 64,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: _isSubmitting
                                    ? [
                                        Colors.grey.shade900,
                                        Colors.grey.shade800,
                                      ]
                                    : [goldColor, const Color(0xFFC5A03F)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: _isSubmitting
                                  ? []
                                  : [
                                      BoxShadow(
                                        color: goldColor.withOpacity(0.3),
                                        blurRadius: 20,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                            ),
                            child: Center(
                              child: _isSubmitting
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'CONFIRM WITHDRAWAL',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 2.0,
                                      ),
                                    ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color goldColor,
    bool isNumeric = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white24, size: 16),
            const SizedBox(width: 8),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: Colors.white24,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
        TextField(
          controller: controller,
          keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          cursorColor: goldColor,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: goldColor.withOpacity(0.5)),
            ),
          ),
        ),
      ],
    );
  }
}

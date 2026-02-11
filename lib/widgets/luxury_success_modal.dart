import 'package:flutter/material.dart';

class LuxurySuccessModal extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onConfirm;
  final String buttonText;
  final bool isError;

  const LuxurySuccessModal({
    super.key,
    required this.title,
    required this.message,
    required this.onConfirm,
    this.buttonText = 'CONTINUE',
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFD4AF37);
    const backgroundColor = Color(0xFF1E1E1E);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: (isError ? Colors.redAccent : goldColor).withOpacity(0.2),
            width: 1,
          ),
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
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError ? Colors.redAccent : goldColor,
              size: 80,
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                color: isError ? Colors.redAccent : goldColor,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: LinearGradient(
                    colors: isError
                        ? [Colors.redAccent.withOpacity(0.8), Colors.redAccent]
                        : [
                            const Color(0xFFB8860B),
                            goldColor,
                            const Color(0xFFFFD700),
                          ],
                  ),
                ),
                child: ElevatedButton(
                  onPressed: onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: isError ? Colors.white : Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    buttonText,
                    style: const TextStyle(
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
    );
  }
}

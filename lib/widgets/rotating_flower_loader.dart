import 'package:flutter/material.dart';

class RotatingFlowerLoader extends StatefulWidget {
  final double size;
  const RotatingFlowerLoader({super.key, this.size = 60});

  @override
  State<RotatingFlowerLoader> createState() => _RotatingFlowerLoaderState();
}

class _RotatingFlowerLoaderState extends State<RotatingFlowerLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Image.asset(
        'assets/images/flower.png',
        width: widget.size,
        height: widget.size,
        errorBuilder: (context, error, stackTrace) {
          return Icon(
            Icons.filter_vintage,
            color: const Color(0xFFD4AF37),
            size: widget.size,
          );
        },
      ),
    );
  }
}

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class SafeNetworkImage extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final String? fallbackUrl;

  const SafeNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.fallbackUrl,
  });

  @override
  State<SafeNetworkImage> createState() => _SafeNetworkImageState();
}

class _SafeNetworkImageState extends State<SafeNetworkImage> {
  Uint8List? _bytes;
  String? _error;
  bool _loading = true;
  String? _currentUrl;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _fetchImage();
  }

  @override
  void didUpdateWidget(SafeNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _currentUrl = widget.url;
      _fetchImage();
    }
  }

  Future<void> _fetchImage({bool isFallback = false}) async {
    if (!mounted) return;
    final urlToFetch = isFallback
        ? (widget.fallbackUrl ?? widget.url)
        : _currentUrl!;

    setState(() {
      _loading = true;
      _error = null;
    });

    int attempts = 0;
    const maxAttempts = 2;

    while (attempts < maxAttempts) {
      try {
        final response = await http
            .get(Uri.parse(urlToFetch))
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          if (mounted) {
            setState(() {
              _bytes = response.bodyBytes;
              _loading = false;
            });
          }
          return;
        } else {
          throw Exception('HTTP ${response.statusCode}');
        }
      } catch (e) {
        attempts++;
        print('[SAFE IMG] Attempt $attempts failed for $urlToFetch: $e');

        if (attempts >= maxAttempts) {
          if (!isFallback &&
              widget.fallbackUrl != null &&
              widget.fallbackUrl != widget.url) {
            print(
              '[SAFE IMG] Primary failed, trying fallback: ${widget.fallbackUrl}',
            );
            return _fetchImage(isFallback: true);
          }

          if (mounted) {
            setState(() {
              _error = e.toString();
              _loading = false;
            });
          }
        } else {
          await Future.delayed(Duration(seconds: 1 * attempts));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return widget.placeholder ??
          Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
                ),
              ),
            ),
          );
    }

    if (_error != null || _bytes == null) {
      return widget.errorWidget ??
          Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.image_not_supported_outlined,
                  color: Colors.white.withOpacity(0.2),
                  size: 32,
                ),
              ],
            ),
          );
    }

    return Image.memory(
      _bytes!,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
    );
  }
}

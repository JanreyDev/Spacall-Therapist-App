import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/currency_formatter.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../api_service.dart';
import '../theme_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'consolidated_requests_screen.dart';
import 'package:intl/intl.dart';

import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'job_progress_screen.dart';
import 'booking_history_screen.dart';
import 'account_screen.dart';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';
import 'store_staff_screen.dart';
import 'transaction_history_screen.dart';
import '../widgets/luxury_success_modal.dart';
import '../widgets/luxury_waiver_dialog.dart';

class WelcomeScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const WelcomeScreen({super.key, required this.userData});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with WidgetsBindingObserver {
  final ApiService _apiService = ApiService();
  bool _isOnline = false;
  bool _isToggling = false;
  DateTime? _lastToggleTime;
  String _currentAddress = 'Not set';
  int _directRequestCount = 0;
  int _nearbyRequestCount = 0;
  int _storeRequestCount = 0;
  Map<String, dynamic>? _ongoingBooking;
  Timer? _pollingTimer;
  Timer? _monitorPaymentTimer;
  int _selectedIndex = 0;
  Position? _currentPosition;
  int? _lastNearbyBookingId;

  int? _lastDirectBookingId;
  final Set<int> _notifiedBookingIds = {};
  int? _activeBookingDialogId; // Track the currently open booking notification
  double _walletBalance = 0.00;
  String _verificationStatus = 'pending'; // pending, verified, rejected
  String _currency = '₱';

  // Dashboard Stats
  int _sessions = 0;
  String _rating = '5.0';
  double _earningsToday = 0.0;
  List<dynamic> _transactions = [];
  bool _isTransactionsLoading = true;
  // Store specific

  int get _totalRequestCount =>
      _directRequestCount + _nearbyRequestCount + _storeRequestCount;

  bool _hasShownInitialBalanceWarning = false;

  @override
  void initState() {
    super.initState();
    print("WelcomeScreen initialized - Dynamic Dashboard");

    // Initialize balance from userData if available to prevent 0.00 flash
    final user = widget.userData['user'];
    if (user != null && user['wallet_balance'] != null) {
      final rawBalance = user['wallet_balance'].toString().replaceAll(
        RegExp(r'[^0-9.]'),
        '',
      );
      _walletBalance = double.tryParse(rawBalance) ?? 0.00;
    }

    _startPolling();
    // Initialize WebSocket immediately — do NOT wait for GPS/toggleOnline
    _initRealtimeListeners();
    // Check for waiver acceptance
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _checkWaiver();
    });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[WelcomeScreen] App resumed — Refreshing profile and wallet');
      _fetchProfile();
      _fetchDashboardStats();
      _fetchTransactions();
    }
  }

  void _initRealtimeListeners() {
    var provider = widget.userData['provider'];
    if (provider == null && widget.userData['user'] != null) {
      provider = widget.userData['user']['provider'];
    }

    // Support for list of providers if backend returns it that way
    if (provider == null &&
        widget.userData['user']?['providers'] is List &&
        (widget.userData['user']['providers'] as List).isNotEmpty) {
      provider = widget.userData['user']['providers'][0];
    }

    if (provider == null || provider['id'] == null) {
      debugPrint(
        '[WS] ❌ Provider is null — WebSocket NOT initialized! Relying on polling only.',
      );
      return;
    }

    final providerId = provider['id'];
    final token = widget.userData['token'];
    debugPrint('[WS] ✅ Starting WebSocket for provider ID: $providerId');

    _apiService
        .initEcho(
          token,
          providerId,
          onConnected: () {
            // Runs INSIDE onConnectionEstablished — fully connected guaranteed.
            // This fixes a release-mode timing issue where subscribe() was called
            // before dart_pusher_channels internals were ready (AOT runs much faster).
            debugPrint(
              '[WelcomeScreen] onConnected — subscribing channels for provider $providerId',
            );
            _apiService.listenForBookings(providerId, (booking) {
              if (!mounted) return;
              debugPrint(
                '[WelcomeScreen] 🔔 REAL-TIME BookingRequested received!',
              );

              final bookingId = booking is Map<String, dynamic>
                  ? booking['id']
                  : null;
              if (bookingId != null) {
                if (_notifiedBookingIds.contains(bookingId)) {
                  debugPrint(
                    '[WelcomeScreen] Already notified for $bookingId, skipping.',
                  );
                  return;
                }
                _lastDirectBookingId = bookingId;
              }

              // Dynamically determine if it's direct based on assignment_type or provider_id
              bool dynamicIsDirect = false;
              if (booking is Map<String, dynamic>) {
                dynamicIsDirect =
                    booking['assignment_type'] == 'direct_request' ||
                    booking['provider_id'] != null;
              }

              _checkActiveRequests(suppressNotification: true);
              _showBookingNotification(booking, isDirect: dynamicIsDirect);
            });

            // Listen for User Notifications (Wallet updates, deposits, etc.)
            final userId = widget.userData['user']?['id'];
            if (userId != null) {
              _apiService.listenForUserNotifications(userId, (notification) {
                if (!mounted) return;
                debugPrint(
                  '[WelcomeScreen] 🔔 REAL-TIME User Notification received: $notification',
                );
                // Refresh profile and stats to update wallet balance immediately
                _fetchProfile();
                _fetchDashboardStats();
                _fetchTransactions();
              });

              _apiService.listenForWalletUpdates(userId, (event) {
                if (!mounted) return;
                debugPrint(
                  '[WelcomeScreen] 💰 REAL-TIME Wallet Update: $event',
                );
                _fetchProfile();
                _fetchDashboardStats();
                _fetchTransactions();

                // IMMEDIATELY update the local state for online toggle synchronization
                final raw = event['newBalance']?.toString() ?? '';
                final balance = double.tryParse(
                  raw.replaceAll(RegExp(r'[^0-9.]'), ''),
                );

                if (mounted && balance != null) {
                  setState(() {
                    _walletBalance = balance;
                  });
                }

                showDialog(
                  context: context,
                  builder: (context) => LuxurySuccessModal(
                    title: 'DEPOSIT SUCCESSFUL',
                    message:
                        'Your wallet has been topped up successfully.${balance != null ? ' New balance: ₱${balance.toStringAsFixed(2)}' : ''}',
                    onConfirm: () => Navigator.pop(context),
                  ),
                );
              });
            }

            // Listen for Claimed Bookings (to remove from others' dashboards)
            _apiService.listenForBookingClaimed((claimed) {
              if (!mounted) return;
              debugPrint(
                '[WelcomeScreen] ⚡ REAL-TIME Booking Claimed: $claimed',
              );

              final claimedBookingId = claimed['booking_id'];
              if (claimedBookingId != null &&
                  claimedBookingId == _activeBookingDialogId) {
                // If the dialog for this booking is open, close it
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder: (modalContext) => LuxurySuccessModal(
                      isError: true,
                      title: 'BOOKING CLAIMED',
                      message:
                          "This session has already been accepted by another therapist. Don't worry, more opportunities are coming!",
                      buttonText: 'SEE OTHERS',
                      onConfirm: () => Navigator.pop(modalContext),
                    ),
                  );
                }
              }

              // Refresh counts immediately to remove the claimed booking
              _checkActiveRequests();
              _checkNearbyBookings();
              if (widget.userData['user']?['customer_tier'] == 'store') {
                _checkStoreRequests();
              }
            });

            debugPrint(
              '[WelcomeScreen] Real-time listeners active for provider $providerId and user $userId',
            );
          },
        )
        .catchError((e) {
          debugPrint('[WelcomeScreen] initEcho error: $e');
        });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _monitorPaymentTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _startPolling() async {
    _fetchTiers(); // Fetch tiers once or periodically
    await _fetchProfile(); // INITIAL FETCH MUST BE AWAITED for accurate balance check
    _checkActiveRequests();
    _checkOngoingJob();
    _checkNearbyBookings();
    _fetchDashboardStats(); // Initial fetch
    if (widget.userData['user']?['customer_tier'] == 'store') {
      _checkStoreRequests();
    }
    _fetchTransactions();

    // Immediately fetch location on app launch (shows prompt and populates address)
    _updateLiveLocation();

    // Auto-online on login
    if (_walletBalance >= 1000) {
      _toggleOnline(true);
    }
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      // Core updates always happen
      _fetchProfile();
      _fetchDashboardStats();
      _fetchTransactions();

      if (timer.tick % 6 == 0) _fetchTiers();

      // Conditional updates based on online status
      if (_isOnline) {
        _checkActiveRequests();
        _checkOngoingJob();
        _checkNearbyBookings();
        if (widget.userData['user']?['customer_tier'] == 'store') {
          _checkStoreRequests();
        }
        _updateLiveLocation();
      }
    });
  }

  Future<void> _fetchTiers() async {
    try {
      final tiers = await _apiService.getTiers(widget.userData['token']);
      if (mounted) {
        setState(() {
          widget.userData['tiers'] = tiers;
        });
      }
    } catch (e) {
      debugPrint('Error fetching tiers: $e');
    }
  }

  Future<void> _checkWaiver() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasAgreed = prefs.getBool('waiver_accepted_therapist_v1') ?? false;

      if (!hasAgreed && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => LuxuryWaiverDialog(
            onAccepted: () async {
              await prefs.setBool('waiver_accepted_therapist_v1', true);
              Navigator.of(context).pop();
            },
          ),
        );
      }
    } catch (e) {
      debugPrint("Error checking waiver: $e");
    }
  }

  Future<void> _updateLiveLocation() async {
    final user = widget.userData['user'];
    final provider = widget.userData['provider'];
    final isStore = user?['customer_tier'] == 'store';

    try {
      double lat = 14.5995;
      double lng = 120.9842;

      if (isStore && provider?['store_profile'] != null) {
        // Use Store's fixed coordinates
        lat =
            double.tryParse(provider['store_profile']['latitude'].toString()) ??
            lat;
        lng =
            double.tryParse(
              provider['store_profile']['longitude'].toString(),
            ) ??
            lng;

        if (mounted) {
          setState(() {
            _currentAddress =
                provider['store_profile']['address'] ?? "Store Location";
          });
        }
      } else {
        // Use GPS for Classic/VIP
        final position = await _determinePosition();
        lat = position.latitude;
        lng = position.longitude;
        if (mounted) {
          setState(() {
            _currentPosition = position;
          });
        }
        await _getAddressFromLatLng(position);
      }

      await _apiService.updateLocation(
        token: widget.userData['token'],
        latitude: lat,
        longitude: lng,
        isOnline: _isOnline,
      );
    } catch (e) {
      debugPrint('Periodic location update error: $e');
    }
  }

  Future<void> _fetchProfile() async {
    try {
      final profile = await _apiService.getProfile(widget.userData['token']);
      final user = profile['user'];
      final provider = profile['provider'];

      if (mounted) {
        setState(() {
          // Update the global userData map so child screens (like AccountScreen) get the fresh data
          widget.userData['user'] = user;
          widget.userData['provider'] = provider;

          // Adjust parsing based on actual API response structure (use regex to strip currency symbols/commas)
          final rawBalance = user['wallet_balance'].toString().replaceAll(
            RegExp(r'[^0-9.]'),
            '',
          );
          _walletBalance = double.tryParse(rawBalance) ?? 0.00;
          // Map is_verified (bool) to status string
          bool isVerified =
              user['is_verified'] == true || user['is_verified'] == 1;
          _verificationStatus = isVerified ? 'verified' : 'pending';

          // _currency = user['currency'] ?? 'PHP';

          // Synchronize online status with backend provider availability
          bool canSyncToggle =
              !_isToggling &&
              (_lastToggleTime == null ||
                  DateTime.now().difference(_lastToggleTime!).inSeconds > 5);

          if (provider != null && canSyncToggle) {
            _isOnline =
                provider['is_available'] == true ||
                provider['is_available'] == 1 ||
                provider['is_available'] == '1';
          }

          // Force local status offline if balance is insufficient (Double-check)
          if (_walletBalance < 1000 && _isOnline && canSyncToggle) {
            _isOnline = false;
            _apiService.updateLocation(
              token: widget.userData['token'],
              latitude: _currentPosition?.latitude ?? 14.5995,
              longitude: _currentPosition?.longitude ?? 120.9842,
              isOnline: false,
            );
          }

          // Show initial login warning if balance is low
          if (!_hasShownInitialBalanceWarning && _walletBalance < 1000) {
            _hasShownInitialBalanceWarning = true;
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted) _showBalanceRequirementDialog();
            });
          }
        });
      }
    } catch (e) {
      print('Error fetching profile: $e');
    }
  }

  void _showBalanceRequirementDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFFD4AF37), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: Color(0xFFD4AF37),
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "MAINTAINING BALANCE",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFD4AF37),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "To receive booking requests and stay visible to clients, your wallet must have a minimum balance of ₱1,000.00.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Current Balance: ₱${_walletBalance.toStringAsFixed(2)}",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFB8860B),
                        Color(0xFFD4AF37),
                        Color(0xFFFFD700),
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
                    child: const Text(
                      "UNDERSTOOD",
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
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

  Future<void> _fetchTransactions() async {
    try {
      final response = await _apiService.getTransactions(
        widget.userData['token'],
      );
      if (mounted) {
        setState(() {
          _transactions = response['data'] ?? [];
          _isTransactionsLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching transactions: $e');
      if (mounted) {
        setState(() {
          _isTransactionsLoading = false;
        });
      }
    }
  }

  Future<void> _fetchDashboardStats() async {
    try {
      final stats = await _apiService.getDashboardStats(
        widget.userData['token'],
      );
      if (mounted) {
        setState(() {
          _sessions = stats['sessions'] ?? 0;
          _rating = stats['rating']?.toString() ?? '5.0';
          _earningsToday =
              double.tryParse(stats['earnings_today']?.toString() ?? '0') ??
              0.0;
        });
      }
    } catch (e) {
      print('Error fetching stats: $e');
    }
  }

  Future<void> _checkActiveRequests({bool suppressNotification = false}) async {
    try {
      final response = await _apiService.getActiveRequests(
        token: widget.userData['token'],
        bookingType: 'home_service',
      );
      final List<dynamic> requests = response['bookings'] ?? [];

      if (!suppressNotification && requests.isNotEmpty) {
        final latestBooking = requests.first;
        final latestId = latestBooking['id'];

        if (_lastDirectBookingId != latestId &&
            !_notifiedBookingIds.contains(latestId)) {
          _lastDirectBookingId = latestId;
          if (mounted) {
            _showBookingNotification(latestBooking, isDirect: true);
          }
        }
      }

      if (mounted) {
        setState(() {
          _directRequestCount = requests.length;
        });
      }
    } catch (e) {
      print('Polling error: $e');
    }
  }

  Future<void> _checkStoreRequests() async {
    try {
      final response = await _apiService.getActiveRequests(
        token: widget.userData['token'],
        bookingType: 'in_store',
      );
      final List<dynamic> requests = response['bookings'] ?? [];

      if (mounted) {
        setState(() {
          _storeRequestCount = requests.length;
        });
      }
    } catch (e) {
      print('Polling error (Store): $e');
    }
  }

  Future<void> _checkOngoingJob() async {
    try {
      final response = await _apiService.getCurrentBookings(
        token: widget.userData['token'],
      );
      final List<dynamic> current = response['current'] ?? [];

      // Look for any job that is NOT pending but still active
      final ongoingStatuses = [
        'accepted',
        'en_route',
        'arrived',
        'in_progress',
      ];
      final ongoing = current.firstWhere(
        (b) => ongoingStatuses.contains(b['status']),
        orElse: () => null,
      );

      if (mounted) {
        setState(() {
          _ongoingBooking = ongoing;
        });
      }
    } catch (e) {
      print('Ongoing job check error: $e');
    }
  }

  Future<void> _checkNearbyBookings() async {
    if (!_isOnline) return;

    try {
      final response = await _apiService.getNearbyBookings(
        token: widget.userData['token'],
      );
      final List<dynamic> bookings = response['bookings'] ?? [];

      if (bookings.isNotEmpty) {
        final latestBooking = bookings.first;
        final latestId = latestBooking['id'];

        // Only notify if it's a new booking we haven't shown yet
        if (_lastNearbyBookingId != latestId &&
            !_notifiedBookingIds.contains(latestId)) {
          _lastNearbyBookingId = latestId;
          if (mounted) {
            _showBookingNotification(latestBooking, isDirect: false);
          }
        }

        // Update nearby count for the tab badge
        if (mounted) {
          setState(() {
            _nearbyRequestCount = bookings.length;
          });
        }
      } else {
        // Clear nearby count if no bookings
        if (mounted) {
          setState(() {
            _nearbyRequestCount = 0;
          });
        }
      }
    } catch (e) {
      print('Nearby job polling error: $e');
    }
  }

  void _showBookingNotification(
    Map<String, dynamic> booking, {
    bool isDirect = false,
  }) {
    final bookingId = booking['id'];
    if (bookingId != null) {
      _notifiedBookingIds.add(bookingId);
      _activeBookingDialogId = bookingId;
    }

    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final goldColor = themeProvider.goldColor;
    final customer = booking['customer'];
    final service = booking['service'];
    final bookingType = booking['booking_type'] ?? 'home_service';
    final isStore = bookingType == 'in_store';

    String label = isDirect
        ? 'SOMEONE REQUESTED YOU'
        : 'NEW NEARBY OPPORTUNITY';
    IconData icon = isDirect
        ? Icons.person_pin_outlined
        : Icons.explore_outlined;

    if (isStore) {
      label = 'NEW STORE APPOINTMENT';
      icon = Icons.storefront_outlined;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: themeProvider.isDarkMode
            ? const Color(0xFF1E1E1E)
            : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(
            color: isStore ? goldColor : goldColor.withOpacity(0.3),
            width: isStore ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with Gradient
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    goldColor.withOpacity(isStore ? 0.3 : 0.15),
                    goldColor.withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: goldColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: goldColor, size: 32),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: goldColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: goldColor.withOpacity(0.4),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: goldColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  // Client Avatar & Distance
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: goldColor, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: goldColor.withOpacity(0.2),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(35),
                          child: customer['profile_photo_url'] != null
                              ? Image.network(
                                  ApiService.normalizePhotoUrl(
                                    customer['profile_photo_url'],
                                  )!,
                                  fit: BoxFit.cover,
                                )
                              : Icon(Icons.person, color: goldColor, size: 40),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${customer['first_name']} ${customer['last_name']}',
                            style: TextStyle(
                              color: themeProvider.textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Builder(
                            builder: (context) {
                              double distanceKm = 0.0;
                              final loc = booking['location'];
                              if (loc != null && _currentPosition != null) {
                                distanceKm =
                                    Geolocator.distanceBetween(
                                      _currentPosition!.latitude,
                                      _currentPosition!.longitude,
                                      double.parse(loc['latitude'].toString()),
                                      double.parse(loc['longitude'].toString()),
                                    ) /
                                    1000;
                              }
                              return Text(
                                '${distanceKm.toStringAsFixed(1)} KM AWAY',
                                style: TextStyle(
                                  color: goldColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  Text(
                    service['name'] ?? 'Luxury Service',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: themeProvider.textColor,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
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
                    style: TextStyle(
                      color: goldColor,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 20),

                  const SizedBox(height: 32),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _showBookingDetails(booking);
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: goldColor.withOpacity(0.5)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'DETAILS',
                            style: TextStyle(
                              color: goldColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.redAccent),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'DECLINE',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Main Accept Button
                  Container(
                    width: double.infinity,
                    height: 54,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFFB8860B),
                          goldColor,
                          const Color(0xFFFFD700),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: goldColor.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _acceptBooking(booking['id']);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'ACCEPT JOB NOW',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 1.1,
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
    ).then((_) {
      if (_activeBookingDialogId == bookingId) {
        _activeBookingDialogId = null;
      }
    });
  }

  Future<void> _acceptBooking(int bookingId) async {
    try {
      final response = await _apiService.updateBookingStatus(
        token: widget.userData['token'],
        bookingId: bookingId,
        status: 'accepted',
      );

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => LuxurySuccessModal(
          title: 'SUCCESS',
          message: 'Booking ACCEPTED! You can now start your journey.',
          onConfirm: () {
            Navigator.of(dialogContext).pop(); // Close modal

            // Redirect to job progress
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => JobProgressScreen(
                  booking: response['booking'],
                  token: widget.userData['token'],
                ),
              ),
            ).then((result) {
              if (result == 'switch_to_sessions') {
                setState(() => _selectedIndex = 2);
                _monitorPaymentRelease(bookingId);
              }
              _checkOngoingJob();
            });
          },
        ),
      );
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

  Future<void> _handleLogout() async {
    try {
      // Disconnect Echo & Polling
      _apiService.disconnectEcho();
      _pollingTimer?.cancel();

      // Backend logout (silent failure ok)
      try {
        await _apiService.logout(widget.userData['token']);
      } catch (e) {
        print('Backend logout failed: $e');
      }

      // Clear local auth token
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');

      if (!mounted) return;

      // Navigate back to LoginScreen
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      print('Logout sequence error: $e');
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
        'Location permissions are permanently denied, we cannot request permissions.',
      );
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
    } catch (e) {
      // Fallback to last known position on timeout or error
      Position? lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        return lastKnown;
      }
      rethrow;
    }
  }

  void _showBookingDetails(Map<String, dynamic> booking) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final goldColor = themeProvider.goldColor;
    final customer = booking['customer'];
    final service = booking['service'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: themeProvider.isDarkMode
              ? const Color(0xFF121212)
              : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'SESSION DETAILS',
              style: TextStyle(
                color: goldColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            const Divider(color: Colors.white10),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Client Info Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundImage:
                                customer['profile_photo_url'] != null
                                ? NetworkImage(
                                    ApiService.normalizePhotoUrl(
                                      customer['profile_photo_url'],
                                    )!,
                                  )
                                : null,
                            child: customer['profile_photo_url'] == null
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${customer['first_name']} ${customer['last_name']}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Text(
                                  'Premium Client',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    _buildDetailSection(
                      'SERVICE',
                      service['name'] ?? 'Luxury Spa Treatment',
                      Icons.spa,
                    ),
                    _buildDetailSection(
                      'TOTAL PAYOUT',
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
                      Icons.payments,
                    ),
                    Builder(
                      builder: (context) {
                        double distanceKm = 0.0;
                        final loc = booking['location'];
                        if (loc != null && _currentPosition != null) {
                          distanceKm =
                              Geolocator.distanceBetween(
                                _currentPosition!.latitude,
                                _currentPosition!.longitude,
                                double.parse(loc['latitude'].toString()),
                                double.parse(loc['longitude'].toString()),
                              ) /
                              1000;
                        }
                        return _buildDetailSection(
                          'DISTANCE',
                          '${distanceKm.toStringAsFixed(1)} KM AWAY',
                          Icons.map_outlined,
                        );
                      },
                    ),
                    _buildDetailSection(
                      'LOCATION',
                      booking['location']?['address'] ?? 'Customer address',
                      Icons.location_on,
                    ),
                    _buildDetailSection(
                      'GENDER PREFERENCE',
                      (booking['gender_preference'] ?? 'Any')
                          .toString()
                          .toUpperCase(),
                      Icons.people_outline,
                    ),
                    _buildDetailSection(
                      'MASSAGE INTENSITY',
                      (booking['intensity_preference'] ?? 'Medium')
                          .toString()
                          .toUpperCase(),
                      Icons.fitness_center_outlined,
                    ),
                    if (booking['customer_notes'] != null &&
                        booking['customer_notes'].toString().isNotEmpty)
                      _buildDetailSection(
                        'SPECIAL NOTES',
                        booking['customer_notes'],
                        Icons.note_alt,
                      ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'CLOSE',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [goldColor, const Color(0xFFFFD700)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _acceptBooking(booking['id']);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'ACCEPT NOW',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
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
    );
  }

  Widget _buildDetailSection(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFD4AF37), size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 10,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _getAddressFromLatLng(Position position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        if (mounted) {
          setState(() {
            String name = place.name ?? "";
            String street = place.street ?? "";
            String locality = place.locality ?? "";

            if (street.isNotEmpty && street != name) {
              _currentAddress = "$street, $locality";
            } else if (name.isNotEmpty) {
              _currentAddress = "$name, $locality";
            } else {
              _currentAddress = locality;
            }

            if (_currentAddress.isEmpty) _currentAddress = "Tarlac City, PH";
          });
        }
      }
    } catch (e) {
      print("Geocoding error: $e");
      if (mounted) {
        setState(() {
          _currentAddress = "Address unavailable";
        });
      }
    }
  }

  Future<void> _toggleOnline(bool value) async {
    if (value && _walletBalance < 1000) {
      _showBalanceRequirementDialog();
      setState(() {
        _isOnline = false;
      });
      return;
    }

    final previousState = _isOnline;
    setState(() {
      _isOnline = value;
      _isToggling = true;
      _lastToggleTime = DateTime.now();
    });

    try {
      double latitude = 14.5995;
      double longitude = 120.9842;

      if (value) {
        try {
          final position = _currentPosition ?? await _determinePosition();
          latitude = position.latitude;
          longitude = position.longitude;
          if (_currentPosition == null) {
            await _getAddressFromLatLng(position);
            if (mounted) setState(() => _currentPosition = position);
          }
        } catch (e) {
          if (!mounted) return;

          if (e.toString().contains('Location services are disabled')) {
            bool opened = await Geolocator.openLocationSettings();
            if (opened) {
              // Should we retry?
              // For now, let's just use default but warn user gently or just return
            }

            _showLuxuryDialog(
              'Location services disabled. Using default location.',
              isError: false, // Not an error strictly, just a warning
            );
          } else {
            _showLuxuryDialog(
              'Location error: $e. Using default.',
              isError: true,
            );
          }
        }
      }

      await _apiService.updateLocation(
        token: widget.userData['token'],
        latitude: latitude,
        longitude: longitude,
        isOnline: value,
      );

      if (value) {
        // WebSocket is already initialized in initState/_initRealtimeListeners.
        // No need to re-init here — just ensure connection is live.
        debugPrint(
          '[WelcomeScreen] Therapist went online — WebSocket already connected.',
        );
      } else {
        _apiService.disconnectEcho();
      }
    } catch (e) {
      if (!mounted) return;
      _showLuxuryDialog(
        e.toString().replaceAll("Exception:", "").trim(),
        isError: true,
      );
      setState(() {
        _isOnline = previousState; // Revert to offline state on failure
      });
    } finally {
      if (mounted) setState(() => _isToggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final goldColor = themeProvider.goldColor;
    final user = widget.userData['user'];

    return Scaffold(
      backgroundColor: themeProvider.backgroundColor,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildDashboard(themeProvider),
          ConsolidatedRequestsScreen(
            token: widget.userData['token'],
            userData: widget.userData,
            onTabSwitch: (index) {
              setState(() => _selectedIndex = index);
            },
          ),
          if (user?['customer_tier'] == 'store')
            StoreStaffScreen(token: widget.userData['token']),
          BookingHistoryScreen(
            token: widget.userData['token'],
            showAppBar: false,
          ),
          AccountScreen(userData: widget.userData),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(goldColor, themeProvider),
    );
  }

  Widget _buildBottomNav(Color goldColor, ThemeProvider themeProvider) {
    final user = widget.userData['user'];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border(top: BorderSide(color: Colors.white12, width: 1)),
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: goldColor,
        unselectedItemColor: themeProvider.subtextColor,
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              children: [
                const Icon(Icons.notifications_none_rounded),
                if (_totalRequestCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 12,
                        minHeight: 12,
                      ),
                      child: Text(
                        '$_totalRequestCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            activeIcon: const Icon(Icons.notifications_rounded),
            label: 'Requests',
          ),
          if (user?['customer_tier'] == 'store')
            const BottomNavigationBarItem(
              icon: Icon(Icons.people_outline_rounded),
              activeIcon: Icon(Icons.people_rounded),
              label: 'Staff',
            ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: "Sessions",
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: "Account",
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard(ThemeProvider themeProvider) {
    return _buildTherapistDashboard(themeProvider);
  }

  Widget _buildTherapistDashboard(ThemeProvider themeProvider) {
    final user = widget.userData['user'];
    final goldColor = themeProvider.goldColor;
    final textColor = themeProvider.textColor;

    final nickname = user?['nickname'];
    final firstName = user?['first_name'] ?? "Therapist";
    final middleName = user?['middle_name'] ?? "";
    final lastName = user?['last_name'] ?? "";
    final fullName = middleName.isNotEmpty
        ? "$firstName $middleName $lastName"
        : (lastName.isNotEmpty ? "$firstName $lastName" : firstName);
    final name = (nickname != null && nickname.toString().isNotEmpty)
        ? nickname
        : fullName;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Refined Header Layout
          Row(
            children: [
              // Logout Button & Location (Left Group)
              GestureDetector(
                onTap: _handleLogout,
                child: Container(
                  padding: const EdgeInsets.only(
                    right: 12.0,
                    top: 8.0,
                    bottom: 8.0,
                  ),
                  color: Colors.transparent, // increases hit area
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: textColor.withOpacity(0.4),
                    size: 20,
                  ),
                ),
              ),
              // Location Indicator
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                  // Border removed for unified luxury look
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_on, color: goldColor, size: 14),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        _currentAddress,
                        style: TextStyle(
                          color: textColor.withOpacity(0.7),
                          fontSize: 12,
                          fontWeight: user?['customer_tier'] == 'store'
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Online Toggle (Right)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: _isOnline ? goldColor : Colors.grey,
                      shape: BoxShape.circle,
                      boxShadow: _isOnline
                          ? [
                              BoxShadow(
                                color: goldColor.withOpacity(0.5),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  Transform.scale(
                    scale: 0.7,
                    alignment: Alignment.centerRight,
                    child: Switch.adaptive(
                      value: _isOnline,
                      onChanged: _toggleOnline,
                      activeColor: goldColor,
                      activeTrackColor: goldColor.withOpacity(0.3),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 32),

          // 2. Hero Section: Greeting & Avatar (Standard Professional Layout)
          Row(
            children: [
              // Glowing Avatar
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: goldColor.withOpacity(0.2),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: goldColor.withOpacity(0.1),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: goldColor.withOpacity(0.1),
                  backgroundImage: user?['profile_photo_url'] != null
                      ? NetworkImage(
                          ApiService.normalizePhotoUrl(
                            user!['profile_photo_url'],
                          )!,
                        )
                      : null,
                  child: user?['profile_photo_url'] == null
                      ? Icon(
                          user?['customer_tier'] == 'store'
                              ? Icons.storefront
                              : Icons.person,
                          color: goldColor,
                          size: 32,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Welcome back,',
                          style: TextStyle(
                            color: themeProvider.subtextColor,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (user?['customer_tier'] != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: goldColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: goldColor.withOpacity(0.4),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              user!['customer_tier'].toString().toUpperCase(),
                              style: TextStyle(
                                color: goldColor,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              colors: [textColor, goldColor.withOpacity(0.8)],
                            ).createShader(bounds),
                            child: Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                height: 1.1,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (_verificationStatus == 'verified') ...[
                          const SizedBox(width: 8),
                          Icon(Icons.verified, color: goldColor, size: 20),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 40),

          // Reordered Content: Wallet FIRST
          _buildWalletSection(goldColor, themeProvider),
          const SizedBox(height: 24),

          // Stats SECOND
          _buildStatsSection(goldColor, themeProvider),
          const SizedBox(height: 32),

          // Recent Transactions THIRD
          _buildRecentTransactionsSection(goldColor, themeProvider),

          // Ongoing Job - REMOVED per user request
          // if (_ongoingBooking != null) ...[
          //   _buildOngoingJobCard(goldColor, themeProvider),
          //   const SizedBox(height: 24),
          // ],

          // Extra bottom padding for scrolling
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildStatsSection(Color goldColor, ThemeProvider themeProvider) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            title: 'Sessions',
            value: '$_sessions',
            icon: Icons.spa_outlined,
            goldColor: goldColor,
            themeProvider: themeProvider,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            title: 'Rating',
            value: _rating,
            icon: Icons.star_border_rounded,
            goldColor: goldColor,
            themeProvider: themeProvider,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            title: 'Earnings',
            value: '₱${NumberFormat('#,##0').format(_earningsToday)}',
            icon: Icons.account_balance_wallet_outlined,
            goldColor: goldColor,
            themeProvider: themeProvider,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color goldColor,
    required ThemeProvider themeProvider,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: goldColor.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: goldColor.withOpacity(0.05),
                blurRadius: 10,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: goldColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: goldColor, size: 20),
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: TextStyle(
                  color: themeProvider.textColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  color: themeProvider.subtextColor,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleDeposit(double amount, String method) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFEBC14F)),
      ),
    );

    try {
      final response = await _apiService.deposit(
        token: widget.userData['token'],
        amount: amount,
        method: method,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading

      if (response['checkout_url'] != null) {
        final checkoutUrl = response['checkout_url'];
        final uri = Uri.parse(checkoutUrl);

        // Close deposit dialog before launching URL
        Navigator.of(context).pop();

        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (e) {
          throw Exception('Could not launch payment URL');
        }
      } else {
        // Fallback or immediate success
        Navigator.of(context).pop(); // Close deposit dialog
        setState(() {
          if (response['balance'] != null) {
            _walletBalance =
                double.tryParse(response['balance'].toString()) ??
                _walletBalance;
          } else {
            _walletBalance += amount;
          }
        });

        // Show success
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => LuxurySuccessModal(
            title: 'DEPOSIT SUCCESSFUL',
            message:
                'You have successfully deposited $_currency${NumberFormat('#,##0.00', 'en_US').format(amount)} into your wallet.',
            buttonText: 'OKAY',
            onConfirm: () => Navigator.of(context).pop(),
          ),
        );

        // Refresh profile to sync everything
        _fetchProfile();
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Deposit failed: ${e.toString().replaceAll("Exception:", "")}',
          ),
        ),
      );
    }
  }

  void _showDepositDialog() {
    final amountController = TextEditingController(
      text: NumberFormat('#,###').format(1000),
    );
    final goldColor = const Color(0xFFEBC14F);
    final quickAmounts = [100.0, 200.0, 500.0, 1000.0];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            top: 12,
            left: 24,
            right: 24,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF0A0A0A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 40,
                spreadRadius: 10,
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle Bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: goldColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: goldColor.withOpacity(0.2)),
                      ),
                      child: Icon(
                        Icons.add_card_rounded,
                        color: goldColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ADD FUNDS',
                          style: GoogleFonts.outfit(
                            color: goldColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.0,
                          ),
                        ),
                        Text(
                          'Top up your therapist wallet',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 40),

                // Amount Section
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        Text(
                          'ENTER AMOUNT',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        IntrinsicWidth(
                          child: TextField(
                            controller: amountController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            onChanged: (_) => setModalState(() {}),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              CurrencyInputFormatter(),
                            ],
                            style: TextStyle(
                              color: goldColor,
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1,
                            ),
                            decoration: InputDecoration(
                              prefixText: '$_currency',
                              prefixStyle: TextStyle(
                                color: goldColor.withOpacity(0.5),
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        Container(
                          width: 120,
                          height: 1,
                          color: goldColor.withOpacity(0.3),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                // Preset Amounts Grid
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 2.5,
                  physics: const NeverScrollableScrollPhysics(),
                  children: quickAmounts.map((amt) {
                    final isSelected =
                        amountController.text.replaceAll(',', '') ==
                        amt.toInt().toString();
                    return GestureDetector(
                      onTap: () => setModalState(
                        () => amountController.text = NumberFormat(
                          '#,###',
                        ).format(amt.toInt()),
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? goldColor
                              : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? goldColor
                                : Colors.white.withOpacity(0.1),
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: goldColor.withOpacity(0.2),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            '₱${NumberFormat('#,###').format(amt.toInt())}',
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.black
                                  : Colors.white.withOpacity(0.9),
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 32),

                // Secure Notice
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        color: Colors.greenAccent.withOpacity(0.7),
                        size: 18,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Payment processed securely via Paymongo. GCash, Maya, and Card accepted.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Action Button
                GestureDetector(
                  onTap: () {
                    final amountText = amountController.text.replaceAll(
                      ',',
                      '',
                    );
                    final amount = double.tryParse(amountText) ?? 0.0;
                    if (amount >= 100) {
                      Navigator.pop(context);
                      _handleDeposit(amount, 'Paymongo');
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Minimum deposit is ₱100'),
                        ),
                      );
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [goldColor, const Color(0xFFC5A03F)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: goldColor.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'PROCEED TO PAYMENT',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleWithdraw(
    double amount,
    String method,
    String accountDetails,
  ) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
      ),
    );

    try {
      final response = await _apiService.withdraw(
        token: widget.userData['token'],
        amount: amount,
        method: method,
        accountDetails: accountDetails,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // Dismiss loading

      setState(() {
        if (response['balance'] != null) {
          _walletBalance =
              double.tryParse(response['balance'].toString()) ?? _walletBalance;
        } else {
          _walletBalance -= amount;
        }
      });

      // Show success
      showDialog(
        context: context,
        builder: (context) => LuxurySuccessModal(
          title: 'WITHDRAWAL SUBMITTED',
          message:
              'Your request to withdraw $_currency${NumberFormat('#,##0.00', 'en_US').format(amount)} has been received.',
          buttonText: 'OKAY',
          onConfirm: () => Navigator.of(context).pop(),
        ),
      );

      // Refresh profile
      _fetchProfile();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Dismiss loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Withdrawal failed: ${e.toString().replaceAll("Exception:", "")}',
          ),
        ),
      );
    }
  }

  void _showWithdrawDialog() {
    final amountController = TextEditingController();
    final accountController = TextEditingController();
    final accountNameController = TextEditingController();
    String selectedMethod = 'GCash';
    const goldColor = Color(0xFFEBC14F);
    final paymentMethods = ['GCash', 'Maya', 'Bank Transfer', 'Paymongo'];
    final quickAmounts = [500.0, 1000.0, 2000.0, 5000.0];

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF0A0A0A),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(32),
          side: BorderSide(color: goldColor.withOpacity(0.1), width: 1),
        ),
        child: StatefulBuilder(
          builder: (context, setDialogState) => SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(28.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Withdraw Funds',
                            style: TextStyle(
                              color: goldColor,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            'Request payout from your wallet',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.05),
                            ),
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.white.withOpacity(0.5),
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Wallet Info
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: goldColor.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: goldColor.withOpacity(0.1)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.account_balance_wallet_rounded,
                          color: goldColor,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AVAILABLE BALANCE',
                              style: TextStyle(
                                color: goldColor.withOpacity(0.6),
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                            ),
                            Text(
                              '$_currency${NumberFormat('#,##0.00').format(_walletBalance)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Amount Section
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.02),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AMOUNT TO WITHDRAW',
                          style: TextStyle(
                            color: goldColor.withOpacity(0.5),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: amountController,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setDialogState(() {}),
                          style: const TextStyle(
                            color: goldColor,
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                          ),
                          decoration: InputDecoration(
                            prefixText: '$_currency ',
                            prefixStyle: const TextStyle(
                              color: goldColor,
                              fontSize: 40,
                              fontWeight: FontWeight.w900,
                            ),
                            border: InputBorder.none,
                            hintText: '0.00',
                            hintStyle: TextStyle(
                              color: Colors.white.withOpacity(0.05),
                              fontSize: 40,
                              fontWeight: FontWeight.w900,
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Quick Amounts
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: quickAmounts.map((amt) {
                        final isSelected =
                            amountController.text == amt.toInt().toString();
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setDialogState(
                              () => amountController.text = amt
                                  .toInt()
                                  .toString(),
                            ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? goldColor
                                    : Colors.white.withOpacity(0.03),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.transparent
                                      : Colors.white.withOpacity(0.05),
                                ),
                              ),
                              child: Text(
                                '$_currency${NumberFormat('#,###').format(amt)}',
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.black
                                      : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Method Selection
                  Text(
                    'PAYOUT METHOD',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedMethod,
                        dropdownColor: const Color(0xFF1A1A1A),
                        icon: const Icon(
                          Icons.keyboard_arrow_down,
                          color: goldColor,
                        ),
                        isExpanded: true,
                        underline: Container(),
                        items: paymentMethods.map((m) {
                          return DropdownMenuItem(
                            value: m,
                            child: Text(
                              m,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) =>
                            setDialogState(() => selectedMethod = val!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Account Details Section
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.02),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ACCOUNT DETAILS',
                          style: TextStyle(
                            color: goldColor.withOpacity(0.5),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: accountNameController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Account Name',
                            labelStyle: TextStyle(
                              color: Colors.white.withOpacity(0.3),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.1),
                              ),
                            ),
                            focusedBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: goldColor),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 8,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: accountController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: selectedMethod == 'Bank Transfer'
                                ? 'Account Number'
                                : 'Mobile Number',
                            labelStyle: TextStyle(
                              color: Colors.white.withOpacity(0.3),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.1),
                              ),
                            ),
                            focusedBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: goldColor),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Final Action Button
                  GestureDetector(
                    onTap: () {
                      final amount =
                          double.tryParse(amountController.text) ?? 0.0;
                      final accName = accountNameController.text.trim();
                      final accNum = accountController.text.trim();

                      if (amount <= 0) {
                        _showError('Please enter a valid amount');
                        return;
                      }

                      if (amount > _walletBalance) {
                        _showError('Insufficient balance');
                        return;
                      }

                      if (accName.isEmpty || accNum.isEmpty) {
                        _showError('Please complete account details');
                        return;
                      }

                      Navigator.of(context).pop();
                      _handleWithdraw(
                        amount,
                        selectedMethod,
                        'Name: $accName\nAccount: $accNum',
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [goldColor, Color(0xFFC5A03F)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: goldColor.withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          'REQUEST WITHDRAWAL',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  Widget _buildWalletButton({
    required String text,
    required IconData icon,
    required Color color,
    required bool isOutlined,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isOutlined ? Colors.transparent : color,
        foregroundColor: isOutlined ? color : Colors.black,
        elevation: isOutlined ? 0 : 4,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isOutlined
              ? BorderSide(color: color.withOpacity(0.5))
              : BorderSide.none,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletSection(Color goldColor, ThemeProvider themeProvider) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    goldColor.withOpacity(0.15),
                    goldColor.withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: goldColor.withOpacity(0.25),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: goldColor.withOpacity(0.1),
                    blurRadius: 30,
                    spreadRadius: -5,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.account_balance_wallet_rounded,
                        color: goldColor.withOpacity(0.5),
                        size: 14,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'WALLET BALANCE',
                        style: TextStyle(
                          color: goldColor.withOpacity(0.5),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Colors.white, Color(0xFFFFD700)],
                    ).createShader(bounds),
                    child: Text(
                      '$_currency ${NumberFormat('#,##0.00', 'en_US').format(_walletBalance)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: _buildWalletButton(
                          text: 'Deposit',
                          icon: Icons.add,
                          color: goldColor,
                          isOutlined: false,
                          onPressed: _showDepositDialog,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildWalletButton(
                          text: 'Withdraw',
                          icon: Icons.arrow_outward,
                          color: goldColor,
                          isOutlined: true,
                          onPressed: _showWithdrawDialog,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentTransactionsSection(
    Color goldColor,
    ThemeProvider themeProvider,
  ) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "RECENT TRANSACTIONS",
              style: TextStyle(
                color: goldColor,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            if (!_isTransactionsLoading && _transactions.isNotEmpty)
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TransactionHistoryScreen(
                        token: widget.userData['token'],
                      ),
                    ),
                  );
                },
                child: Text(
                  "SEE ALL",
                  style: TextStyle(
                    color: goldColor.withOpacity(0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _isTransactionsLoading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
                ),
              )
            : _transactions.isEmpty
            ? Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        color: Colors.white.withOpacity(0.2),
                        size: 40,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "No transactions yet",
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.3),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _transactions.length > 4 ? 4 : _transactions.length,
                itemBuilder: (context, index) {
                  final tx = _transactions[index];
                  return _buildTransactionCard(tx, themeProvider, goldColor);
                },
              ),
      ],
    );
  }

  Widget _buildTransactionCard(
    Map<String, dynamic> tx,
    ThemeProvider themeProvider,
    Color goldColor,
  ) {
    final type = tx['type']?.toString().toLowerCase() ?? '';
    final status = tx['status']?.toString().toLowerCase() ?? '';
    final amount = double.tryParse(tx['amount']?.toString() ?? '0') ?? 0.0;
    final createdAt =
        DateTime.tryParse(tx['created_at'] ?? '') ?? DateTime.now();
    final dateStr = DateFormat('MMM dd, yyyy • hh:mm a').format(createdAt);

    bool isCredit = true;
    IconData icon = Icons.payment;
    String title = 'Transaction';

    if (type == 'deposit') {
      title = 'Wallet Top-up';
      icon = Icons.add_circle_outline;
      isCredit = true;
    } else if (type == 'withdrawal') {
      title = 'Wallet Withdrawal';
      icon = Icons.remove_circle_outline;
      isCredit = false;
    } else if (type == 'booking') {
      title = 'Session Payment';
      icon = Icons.spa_outlined;
      isCredit = true; // For therapist, booking is credit!
    }

    // Use meta description if available
    if (tx['meta'] != null) {
      try {
        final meta = tx['meta'] is String ? jsonDecode(tx['meta']) : tx['meta'];
        if (meta['description'] != null) {
          title = meta['description'];
        }
      } catch (e) {
        // Ignore JSON parse errors
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: goldColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: goldColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "${isCredit ? '+' : '-'} ₱${NumberFormat('#,##0.00', 'en_US').format(amount.abs())}",
                style: TextStyle(
                  color: isCredit ? Colors.greenAccent : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (status != 'completed')
                Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    color: status == 'pending' ? Colors.orange : Colors.red,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // _buildStatusCard removed

  void _showLuxuryDialog(
    String message, {
    bool isError = false,
    String? actionLabel,
    VoidCallback? onActionPressed,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) => LuxurySuccessModal(
        isError: isError,
        title: isError ? 'ERROR' : 'SUCCESS',
        message: message,
        buttonText: actionLabel?.toUpperCase() ?? 'CONTINUE',
        onConfirm: () {
          Navigator.of(dialogContext).pop();
          if (onActionPressed != null) {
            onActionPressed();
          }
        },
      ),
    );
  }

  void _monitorPaymentRelease(int bookingId) {
    debugPrint("[PAYMENT MONITOR] Starting monitor for booking $bookingId");
    _monitorPaymentTimer?.cancel();
    int checks = 0;

    _monitorPaymentTimer = Timer.periodic(const Duration(seconds: 5), (
      timer,
    ) async {
      checks++;
      if (checks > 60) {
        // 5 minutes (300s / 5s = 60 checks)
        timer.cancel();
        return;
      }

      try {
        final statusData = await _apiService.getBookingStatus(
          bookingId,
          widget.userData['token'],
        );

        final booking = statusData['booking'] ?? statusData;
        final paymentStatus = booking['payment_status'];

        debugPrint(
          "[PAYMENT MONITOR] Booking $bookingId status: $paymentStatus",
        );

        if (paymentStatus == 'paid' || paymentStatus == 'released') {
          timer.cancel();
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => LuxurySuccessModal(
                title: "PAYMENT RECEIVED",
                message:
                    "Client has submitted their review and payment has been released to your wallet!",
                onConfirm: () => Navigator.pop(context),
              ),
            );
            _fetchProfile(); // Refresh wallet balance
            _fetchTransactions(); // Refresh transactions
            _fetchDashboardStats();
          }
        }
      } catch (e) {
        debugPrint("[PAYMENT MONITOR] Error during payment check: $e");
      }
    });
  }
}

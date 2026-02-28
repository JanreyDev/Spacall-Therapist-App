import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../theme_provider.dart';
import '../api_service.dart';

class TransactionHistoryScreen extends StatefulWidget {
  final String token;

  const TransactionHistoryScreen({super.key, required this.token});

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  final ApiService _apiService = ApiService();
  final ScrollController _scrollController = ScrollController();

  List<dynamic> _transactions = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  bool _hasNextPage = true;
  int _totalTransactions = 0;

  @override
  void initState() {
    super.initState();
    _fetchTransactions();
    // _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Disabled automatic loading on scroll
  }

  Future<void> _fetchTransactions({bool loadMore = false}) async {
    if (loadMore) {
      setState(() => _isLoadingMore = true);
    } else {
      setState(() => _isLoading = true);
    }

    try {
      final response = await _apiService.getTransactions(
        widget.token,
        page: loadMore ? _currentPage + 1 : 1,
      );

      final List<dynamic> newItems = response['data'] ?? [];
      final int lastPage = response['last_page'] ?? 1;
      final int total = response['total'] ?? 0;

      if (mounted) {
        setState(() {
          if (loadMore) {
            _transactions.addAll(newItems);
            _currentPage++;
          } else {
            _transactions = newItems;
            _currentPage = 1;
          }
          _totalTransactions = total;
          _hasNextPage = _currentPage < lastPage;
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching transactions: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final goldColor = themeProvider.goldColor;

    return Scaffold(
      backgroundColor: themeProvider.backgroundColor,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFEBC14F)),
            )
          : CustomScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              slivers: [
                // 1. Premium App Bar
                SliverAppBar(
                  expandedHeight: 180.0,
                  floating: false,
                  pinned: true,
                  backgroundColor: themeProvider.backgroundColor,
                  elevation: 0,
                  leading: IconButton(
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: goldColor,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  centerTitle: true,
                  flexibleSpace: FlexibleSpaceBar(
                    centerTitle: true,
                    title: Text(
                      'TRANSACTION HISTORY',
                      style: TextStyle(
                        color: goldColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                      ),
                    ),
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Background gradient
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                goldColor.withOpacity(0.15),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                        // Stats summary
                        Positioned(
                          bottom: 60,
                          left: 0,
                          right: 0,
                          child: Column(
                            children: [
                              Text(
                                "TOTAL TRANSACTIONS",
                                style: TextStyle(
                                  color: goldColor.withOpacity(0.5),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "$_totalTransactions",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 42,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. Transaction List
                _transactions.isEmpty
                    ? SliverFillRemaining(child: _buildEmptyState())
                    : SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 10, 24, 40),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              if (index < _transactions.length) {
                                return _buildTransactionCard(
                                  _transactions[index],
                                  themeProvider,
                                  goldColor,
                                );
                              } else {
                                // LOAD MORE button at the bottom
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 30,
                                  ),
                                  child: Center(
                                    child: _isLoadingMore
                                        ? CircularProgressIndicator(
                                            color: goldColor,
                                            strokeWidth: 2,
                                          )
                                        : TextButton(
                                            onPressed: () => _fetchTransactions(
                                              loadMore: true,
                                            ),
                                            style: TextButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 32,
                                                    vertical: 12,
                                                  ),
                                              side: BorderSide(
                                                color: goldColor.withOpacity(
                                                  0.3,
                                                ),
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(30),
                                              ),
                                            ),
                                            child: Text(
                                              "LOAD MORE",
                                              style: TextStyle(
                                                color: goldColor,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 1.5,
                                              ),
                                            ),
                                          ),
                                  ),
                                );
                              }
                            },
                            childCount:
                                _transactions.length + (_hasNextPage ? 1 : 0),
                          ),
                        ),
                      ),
              ],
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            color: Colors.white.withOpacity(0.1),
            size: 80,
          ),
          const SizedBox(height: 20),
          Text(
            "No transactions found",
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
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
      isCredit = true;
    }

    if (tx['meta'] != null) {
      try {
        final meta = tx['meta'] is String ? jsonDecode(tx['meta']) : tx['meta'];
        if (meta['description'] != null) {
          title = meta['description'];
        }
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: goldColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: goldColor, size: 22),
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
                const SizedBox(height: 4),
                Text(
                  dateStr,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 11,
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
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (status != 'completed')
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: (status == 'pending' ? Colors.orange : Colors.red)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: status == 'pending' ? Colors.orange : Colors.red,
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

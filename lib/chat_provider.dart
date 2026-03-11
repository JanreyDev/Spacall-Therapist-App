import 'package:flutter/material.dart';
import 'api_service.dart';

class ChatMessage {
  final int id;
  final String content;
  final int senderId;
  final String senderName;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.content,
    required this.senderId,
    required this.senderName,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'],
      content: json['content'],
      senderId: json['sender_id'],
      senderName: json['sender_name'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class ChatProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  final Map<int, int> _unreadCounts = {};

  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;

  int getUnreadCount(int bookingId) => _unreadCounts[bookingId] ?? 0;
  int get totalUnreadCount =>
      _unreadCounts.values.fold(0, (sum, count) => sum + count);

  void markAsRead(int bookingId) {
    if (_unreadCounts.containsKey(bookingId)) {
      _unreadCounts[bookingId] = 0;
      notifyListeners();
    }
  }

  void incrementUnread(int bookingId) {
    _unreadCounts[bookingId] = (_unreadCounts[bookingId] ?? 0) + 1;
    notifyListeners();
  }

  Future<void> fetchMessages(int bookingId, String token) async {
    _isLoading = true;
    notifyListeners();

    try {
      final data = await _apiService.getChatMessages(bookingId, token);
      final List<dynamic> msgs = data['messages'];
      _messages = msgs.map((m) => ChatMessage.fromJson(m)).toList();
      // Automatically mark as read when fetching messages for this booking
      markAsRead(bookingId);
    } catch (e) {
      debugPrint('Error fetching chat messages: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> sendMessage(int bookingId, String token, String content) async {
    try {
      final data = await _apiService.sendChatMessage(bookingId, token, content);
      final newMessage = ChatMessage.fromJson(data['message']);
      _messages.add(newMessage);
      notifyListeners();
    } catch (e) {
      debugPrint('Error sending message: $e');
      rethrow;
    }
  }

  void addMessage(Map<String, dynamic> messageData, {dynamic bookingId}) {
    final newMessage = ChatMessage.fromJson(messageData);
    final int? bId = bookingId is String
        ? int.tryParse(bookingId)
        : bookingId as int?;

    debugPrint(
      '[ChatProvider] addMessage for booking $bId: ${newMessage.content}',
    );

    // Avoid duplicates if echoed back or already added locally
    if (!_messages.any((m) => m.id == newMessage.id)) {
      _messages.add(newMessage);
      if (bId != null) {
        _unreadCounts[bId] = (_unreadCounts[bId] ?? 0) + 1;
        debugPrint(
          '[ChatProvider] Increment unread for $bId, new count: ${_unreadCounts[bId]}',
        );
      }
      notifyListeners();
    }
  }

  void clearMessages() {
    _messages = [];
    notifyListeners();
  }
}

import 'package:flutter/material.dart';
import 'api_service.dart';
import 'chat_provider.dart';

class SupportChatProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  int? _sessionId;

  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  int? get sessionId => _sessionId;

  Future<void> initializeSession(String token) async {
    _isLoading = true;
    notifyListeners();

    try {
      final sessionData = await _apiService.getSupportSession(token);
      _sessionId = sessionData['session']['id'];

      if (_sessionId != null) {
        final messagesData = await _apiService.getSupportMessages(
          token,
          _sessionId!,
        );
        final List<dynamic> msgs = messagesData['messages'];
        _messages = msgs.map((m) => ChatMessage.fromJson(m)).toList();
      }
    } catch (e) {
      debugPrint('Error initializing support session: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> sendMessage(String token, String content) async {
    if (_sessionId == null) return;

    try {
      final data = await _apiService.sendSupportMessage(
        token,
        _sessionId!,
        content,
      );
      final newMessage = ChatMessage.fromJson(data['message']);

      if (!_messages.any((m) => m.id == newMessage.id)) {
        _messages.add(newMessage);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error sending support message: $e');
      rethrow;
    }
  }

  void addMessage(Map<String, dynamic> messageData) {
    final newMessage = ChatMessage.fromJson(messageData);
    if (!_messages.any((m) => m.id == newMessage.id)) {
      _messages.add(newMessage);
      notifyListeners();
    }
  }
}

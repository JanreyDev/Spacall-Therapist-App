import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api_service.dart';
import '../chat_provider.dart';
import '../support_chat_provider.dart';
import '../theme_provider.dart';
import 'package:intl/intl.dart';

class SupportChatScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const SupportChatScreen({super.key, required this.userData});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ApiService _apiService = ApiService();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<SupportChatProvider>(context, listen: false);
      provider.initializeSession(widget.userData['token']).then((_) {
        if (provider.sessionId != null) {
          _setupEcho(provider.sessionId!);
        }
      });
    });
  }

  void _setupEcho(int sessionId) {
    final userId = widget.userData['user']['id'];
    _apiService.initEcho(widget.userData['token'], userId).then((_) {
      _apiService.listenForSupportMessages(sessionId, (messageData) {
        if (mounted) {
          Provider.of<SupportChatProvider>(
            context,
            listen: false,
          ).addMessage(messageData);
          _scrollToBottom();
        }
      });
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _handleSendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      await Provider.of<SupportChatProvider>(
        context,
        listen: false,
      ).sendMessage(widget.userData['token'], content);
      _scrollToBottom();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final goldColor = const Color(0xFFD4AF37);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        elevation: 0,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: goldColor.withOpacity(0.1),
              child: Icon(Icons.support_agent, color: goldColor),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Spacall Support',
                  style: TextStyle(
                    color: themeProvider.textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'Online',
                  style: TextStyle(color: Colors.green, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: themeProvider.textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Consumer<SupportChatProvider>(
              builder: (context, provider, child) {
                if (provider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (provider.sessionId == null) {
                  return const Center(child: Text('Connecting to support...'));
                }

                final messages = provider.messages;
                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: goldColor.withOpacity(0.3),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No messages yet.\nHow can we help you today?',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMe =
                        message.senderId == widget.userData['user']['id'];

                    return _buildMessageBubble(message, isMe, themeProvider);
                  },
                );
              },
            ),
          ),
          _buildInputArea(themeProvider, goldColor),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
    ChatMessage message,
    bool isMe,
    ThemeProvider themeProvider,
  ) {
    final goldColor = const Color(0xFFD4AF37);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: goldColor.withOpacity(0.1),
              child: Icon(Icons.support_agent, color: goldColor, size: 20),
            ),
            const SizedBox(width: 8),
          ],
          Column(
            crossAxisAlignment: isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isMe
                      ? goldColor
                      : (themeProvider.isDarkMode
                            ? const Color(0xFF2A2A2A)
                            : Colors.grey[200]),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(isMe ? 20 : 0),
                    bottomRight: Radius.circular(isMe ? 0 : 20),
                  ),
                ),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.65,
                ),
                child: Text(
                  message.content,
                  style: TextStyle(
                    color: isMe ? Colors.black : themeProvider.textColor,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('HH:mm').format(message.createdAt),
                style: TextStyle(
                  color: themeProvider.textColor.withOpacity(0.4),
                  fontSize: 10,
                ),
              ),
            ],
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundImage:
                  widget.userData['user']['profile_photo_url'] != null
                  ? NetworkImage(widget.userData['user']['profile_photo_url'])
                  : null,
              child: widget.userData['user']['profile_photo_url'] == null
                  ? Icon(Icons.person, color: goldColor, size: 20)
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputArea(ThemeProvider themeProvider, Color goldColor) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        8 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: themeProvider.isDarkMode
            ? const Color(0xFF1A1A1A)
            : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: themeProvider.isDarkMode
                    ? Colors.black
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _messageController,
                style: TextStyle(color: themeProvider.textColor),
                decoration: const InputDecoration(
                  hintText: 'Type your message...',
                  hintStyle: TextStyle(color: Colors.grey),
                  border: InputBorder.none,
                ),
                maxLines: null,
                keyboardType: TextInputType.multiline,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _isSending ? null : _handleSendMessage,
            icon: Icon(Icons.send, color: _isSending ? Colors.grey : goldColor),
          ),
        ],
      ),
    );
  }
}

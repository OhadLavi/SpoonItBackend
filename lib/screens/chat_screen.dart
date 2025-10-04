import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_keeper/services/chat_service.dart';
import 'package:recipe_keeper/providers/settings_provider.dart';
import 'package:recipe_keeper/utils/translations.dart';
import 'package:recipe_keeper/widgets/app_header.dart';
import 'package:recipe_keeper/widgets/app_bottom_nav.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ChatService _chatService = ChatService();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;

  @override
  void dispose() {
    _messageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    final isHebrew = ref.read(settingsProvider) == AppLanguage.hebrew;

    setState(() {
      _messages.add(ChatMessage(text: message, isUser: true));
      _isLoading = true;
    });

    _messageController.clear();
    _focusNode.requestFocus();

    try {
      final response = await _chatService.sendMessage(
        message,
        language: isHebrew ? 'he' : 'en',
      );
      setState(() {
        _messages.add(ChatMessage(text: response, isUser: false));
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppTranslations.getText(ref, 'error')}: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHebrew = ref.watch(settingsProvider) == AppLanguage.hebrew;

    return Directionality(
      textDirection: isHebrew ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: Column(
          children: [
            const AppHeader(title: 'צ\'אט'),
            Expanded(
              child:
                  _messages.isEmpty
                      ? Center(
                        child: Text(
                          AppTranslations.getText(ref, 'no_messages'),
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      )
                      : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          return MessageBubble(
                            message: message,
                            isHebrew: isHebrew,
                          );
                        },
                      ),
            ),
            if (_isLoading)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFFFF7E6B)),
                    const SizedBox(width: 8),
                    Text(AppTranslations.getText(ref, 'loading')),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _sendMessage,
                    tooltip: AppTranslations.getText(ref, 'send'),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      focusNode: _focusNode,
                      autofocus: true,
                      textDirection:
                          isHebrew ? TextDirection.rtl : TextDirection.ltr,
                      textAlign: isHebrew ? TextAlign.right : TextAlign.left,
                      style: TextStyle(
                        fontFamily: isHebrew ? 'Heebo' : null,
                        fontSize: 16,
                      ),
                      decoration: InputDecoration(
                        hintText: AppTranslations.getText(ref, 'type_message'),
                        hintTextDirection:
                            isHebrew ? TextDirection.rtl : TextDirection.ltr,
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ],
              ),
            ),
            const AppBottomNav(currentIndex: -1),
          ],
        ),
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
}

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isHebrew;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isHebrew,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment:
          message.isUser
              ? (isHebrew ? Alignment.centerLeft : Alignment.centerRight)
              : (isHebrew ? Alignment.centerRight : Alignment.centerLeft),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color:
              message.isUser
                  ? Theme.of(context).primaryColor
                  : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: message.isUser ? Colors.white : null,
            fontFamily: isHebrew ? 'Heebo' : null,
            fontSize: 16,
          ),
          textDirection: isHebrew ? TextDirection.rtl : TextDirection.ltr,
          textAlign: isHebrew ? TextAlign.right : TextAlign.left,
        ),
      ),
    );
  }
}

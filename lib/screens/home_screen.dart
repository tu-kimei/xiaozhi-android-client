import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/providers/conversation_provider.dart';
import 'package:ai_assistant/models/conversation.dart';
import 'package:ai_assistant/screens/chat_screen.dart';
import 'package:ai_assistant/screens/settings_screen.dart';
import 'package:ai_assistant/screens/conversation_type_screen.dart';
import 'package:ai_assistant/widgets/conversation_tile.dart';
import 'package:ai_assistant/widgets/slidable_delete_tile.dart';
import 'package:ai_assistant/widgets/discovery_screen.dart';
import 'package:flutter/rendering.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // 点击页面任何地方时，让搜索框失去焦点
        _searchFocusNode.unfocus();
        // 同时关闭所有打开的删除按钮
        SlidableController.instance.closeCurrentTile();
      },
      child: Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: true,
        backgroundColor: const Color(0xFFF8F9FA),
        appBar:
            _selectedIndex == 1
                ? null
                : AppBar(
                  title: const Text(
                    'Tin nhắn',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      color: Colors.black,
                    ),
                  ),
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  backgroundColor: const Color(0xFFF8F9FA),
                  centerTitle: false,
                  titleSpacing: 20,
                  toolbarHeight: 56,
                  actions: [
                    // 新建对话（原来的悬浮按钮会挡住列表项的删除按钮）
                    IconButton(
                      tooltip: 'Hội thoại mới',
                      icon: const Icon(Icons.add_circle, size: 30),
                      color: Colors.black,
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (context) => const ConversationTypeScreen(),
                          ),
                        );
                      },
                    ),
                    Padding(
                      // 右上角留出机器人系统电量浮层的位置
                      padding: const EdgeInsets.only(right: 44),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          splashColor: Colors.grey.withOpacity(0.1),
                          highlightColor: Colors.grey.withOpacity(0.1),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const SettingsScreen(),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Icon(
                              Icons.settings,
                              size: 26,
                              color: Colors.grey.shade700,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 0.5,
                                  offset: const Offset(0, 0.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        body:
            _selectedIndex == 1
                ? const SafeArea(bottom: false, child: DiscoveryScreen())
                : SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      _buildSearchBar(),
                      Expanded(child: _buildBody()),
                    ],
                  ),
                ),
        bottomNavigationBar: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          child: Theme(
            data: ThemeData(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    spreadRadius: 0,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom / 2,
                ),
                child: BottomNavigationBar(
                  currentIndex: _selectedIndex,
                  onTap: (index) {
                    setState(() {
                      _selectedIndex = index;
                    });
                  },
                  selectedItemColor: Colors.black,
                  unselectedItemColor: Colors.grey.shade600,
                  showSelectedLabels: true,
                  showUnselectedLabels: true,
                  backgroundColor: Colors.white,
                  elevation: 0,
                  type: BottomNavigationBarType.fixed,
                  selectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                  iconSize: 26,
                  items: [
                    BottomNavigationBarItem(
                      icon: Material(
                        color: Colors.transparent,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                _selectedIndex == 0
                                    ? Colors.grey.shade100
                                    : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow:
                                _selectedIndex == 0
                                    ? [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 4,
                                        spreadRadius: 0,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                    : null,
                          ),
                          child: Icon(
                            _selectedIndex == 0
                                ? Icons.chat_bubble
                                : Icons.chat_bubble_outline,
                          ),
                        ),
                      ),
                      label: 'Tin nhắn',
                    ),
                    BottomNavigationBarItem(
                      icon: Material(
                        color: Colors.transparent,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                _selectedIndex == 1
                                    ? Colors.grey.shade100
                                    : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow:
                                _selectedIndex == 1
                                    ? [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 4,
                                        spreadRadius: 0,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                    : null,
                          ),
                          child: Icon(
                            _selectedIndex == 1
                                ? Icons.search
                                : Icons.search_outlined,
                          ),
                        ),
                      ),
                      label: 'Khám phá',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    if (_selectedIndex == 1) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.white,
          child: TextField(
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              hintText: 'Tìm hội thoại',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 16),
              prefixIcon: Container(
                padding: const EdgeInsets.all(12),
                child: Icon(
                  Icons.search,
                  color: Colors.grey.shade500,
                  size: 22,
                ),
              ),
              suffixIcon: Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.mic_none_outlined,
                  color: Colors.grey.shade500,
                  size: 22,
                ),
              ),
              filled: true,
              fillColor: Colors.white,
              focusColor: Colors.white,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 16,
                horizontal: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    // Messages tab
    return Consumer<ConversationProvider>(
      builder: (context, provider, child) {
        final pinnedConversations = provider.pinnedConversations;
        final unpinnedConversations = provider.unpinnedConversations;

        return ListView(
          padding: EdgeInsets.only(
            bottom: 16 + MediaQuery.of(context).padding.bottom,
          ),
          children: [
            if (pinnedConversations.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 8,
                  bottom: 8,
                ),
                child: Text(
                  'Ghim hội thoại',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                    fontSize: 15,
                    shadows: [
                      Shadow(
                        color: Color(0x40000000),
                        blurRadius: 0.5,
                        offset: Offset(0, 0.5),
                      ),
                    ],
                  ),
                ),
              ),
              ...pinnedConversations.map(
                (conversation) => _buildConversationTile(conversation),
              ),
            ],

            if (unpinnedConversations.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: pinnedConversations.isEmpty ? 8 : 16,
                  bottom: 8,
                ),
                child: const Text(
                  'Tất cả hội thoại',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                    fontSize: 15,
                    shadows: [
                      Shadow(
                        color: Color(0x40000000),
                        blurRadius: 0.5,
                        offset: Offset(0, 0.5),
                      ),
                    ],
                  ),
                ),
              ),
              ...unpinnedConversations.map(
                (conversation) => _buildConversationTile(conversation),
              ),
            ],

            if (pinnedConversations.isEmpty && unpinnedConversations.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(64.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              spreadRadius: 0,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.chat_bubble_outline,
                          size: 48,
                          color: Colors.grey.shade300,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Chưa có hội thoại',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade500,
                          shadows: const [
                            Shadow(
                              color: Color(0x40000000),
                              blurRadius: 0.5,
                              offset: Offset(0, 0.5),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 5,
                              spreadRadius: 0,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add_circle_outline,
                              size: 18,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Nhấn + để tạo hội thoại mới',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildConversationTile(Conversation conversation) {
    return SlidableDeleteTile(
      key: Key(conversation.id),
      onDelete: () => _deleteWithUndo(conversation),
      onTap: () {
        // 直接导航到聊天页面
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(conversation: conversation),
          ),
        );
      },
      onLongPress: () {
        // 显示置顶等选项
        _showConversationOptions(conversation);
      },
      child: ConversationTile(
        conversation: conversation,
        onTap: null, // 不再需要处理点击
        onLongPress: null, // 不再需要处理长按
      ),
    );
  }

  void _deleteWithUndo(Conversation conversation) {
    final provider = Provider.of<ConversationProvider>(context, listen: false);
    provider.deleteConversation(conversation.id);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã xóa ${conversation.title}'),
        backgroundColor: Colors.grey.shade800,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        margin: const EdgeInsets.only(bottom: 70, left: 12, right: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: 'Hoàn tác',
          textColor: Colors.white,
          onPressed: provider.restoreLastDeletedConversation,
        ),
      ),
    );
  }

  /// 长按菜单：用紧凑对话框代替底部弹层，小屏幕（机器人 308x240）也能看到"删除"
  void _showConversationOptions(Conversation conversation) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 12,
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          contentPadding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            conversation.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          children: [
            SimpleDialogOption(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              onPressed: () {
                Navigator.pop(dialogContext);
                _deleteWithUndo(conversation);
              },
              child: const Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 12),
                  Text(
                    'Xóa hội thoại',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
            SimpleDialogOption(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              onPressed: () {
                Navigator.pop(dialogContext);
                Provider.of<ConversationProvider>(
                  context,
                  listen: false,
                ).togglePinConversation(conversation.id);
              },
              child: Row(
                children: [
                  Icon(
                    conversation.isPinned
                        ? Icons.push_pin
                        : Icons.push_pin_outlined,
                    color: Colors.black,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    conversation.isPinned ? 'Bỏ ghim' : 'Ghim hội thoại',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

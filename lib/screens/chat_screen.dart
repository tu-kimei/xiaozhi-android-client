import '../widgets/voice_state_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'dart:math';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ai_assistant/models/conversation.dart';
import 'package:ai_assistant/models/message.dart';
import 'package:ai_assistant/models/xiaozhi_config.dart';
import 'package:ai_assistant/models/dify_config.dart';
import 'package:ai_assistant/providers/conversation_provider.dart';
import 'package:ai_assistant/providers/config_provider.dart';
import 'package:ai_assistant/models/minimax_config.dart';
import 'package:ai_assistant/services/dify_service.dart';
import 'package:ai_assistant/services/xiaozhi_service.dart';
import 'package:ai_assistant/services/minimax_service.dart';
import 'package:ai_assistant/widgets/message_bubble.dart';
import 'package:ai_assistant/screens/voice_call_screen.dart';
import 'dart:convert';
import 'dart:async';
import 'package:path_provider/path_provider.dart';

class ChatScreen extends StatefulWidget {
  final Conversation conversation;

  const ChatScreen({super.key, required this.conversation});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  XiaozhiService? _xiaozhiService; // 保持XiaozhiService实例
  DifyService? _difyService; // 保持DifyService实例
  MiniMaxService? _minimaxService; // 保持MiniMaxService实例
  Timer? _connectionCheckTimer; // 添加定时器检查连接状态
  Timer? _autoReconnectTimer; // 自动重连定时器

  // 语音输入相关
  bool _isVoiceInputMode = false;
  bool _isRecording = false;
  bool _isCancelling = false;
  double _startDragY = 0.0;
  final double _cancelThreshold = 50.0; // 上滑超过这个距离认为是取消
  Timer? _waveAnimationTimer;
  final List<double> _waveHeights = List.filled(20, 0.0);
  double _minWaveHeight = 5.0;
  double _maxWaveHeight = 30.0;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();

    // 设置状态栏为透明并使图标为黑色
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );

    // 在帧绘制后再次设置系统UI样式，避免被覆盖
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarDividerColor: Colors.transparent,
        ),
      );

      Provider.of<ConversationProvider>(
        context,
        listen: false,
      ).markConversationAsRead(widget.conversation.id);

      // 如果是小智对话，初始化服务
      if (widget.conversation.type == ConversationType.xiaozhi) {
        _initXiaozhiService();
        // 添加定时器定期检查连接状态
        _connectionCheckTimer = Timer.periodic(const Duration(seconds: 2), (
          timer,
        ) {
          if (mounted && _xiaozhiService != null) {
            final wasConnected = _xiaozhiService!.isConnected;

            // 刷新UI
            setState(() {});

            // 如果状态从连接变为断开，尝试自动重连
            if (wasConnected &&
                !_xiaozhiService!.isConnected &&
                _autoReconnectTimer == null) {
              print('检测到连接断开，准备自动重连');
              _scheduleReconnect();
            }
          }
        });

        // 默认启用语音输入模式 (针对小智对话)
        setState(() {
          _isVoiceInputMode = true;
        });
      } else if (widget.conversation.type == ConversationType.dify) {
        // 初始化 DifyService
        _initDifyService();
      } else if (widget.conversation.type == ConversationType.minimax) {
        // 初始化 MiniMaxService
        _initMiniMaxService();
      }
    });
  }

  // 安排自动重连
  void _scheduleReconnect() {
    // 取消现有重连定时器
    _autoReconnectTimer?.cancel();

    // 创建新的重连定时器，5秒后尝试重连
    _autoReconnectTimer = Timer(const Duration(seconds: 5), () async {
      print('正在尝试自动重连...');
      if (_xiaozhiService != null && !_xiaozhiService!.isConnected && mounted) {
        try {
          await _xiaozhiService!.disconnect();
          await _xiaozhiService!.connect();

          setState(() {});
          print('自动重连 ${_xiaozhiService!.isConnected ? "成功" : "失败"}');

          // 如果重连失败，则继续尝试重连
          if (!_xiaozhiService!.isConnected) {
            _scheduleReconnect();
          } else {
            _autoReconnectTimer = null;
          }
        } catch (e) {
          print('自动重连出错: $e');
          _scheduleReconnect(); // 出错后继续尝试
        }
      } else {
        _autoReconnectTimer = null;
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    // 取消所有定时器
    _connectionCheckTimer?.cancel();
    _autoReconnectTimer?.cancel();
    _waveAnimationTimer?.cancel();

    // 在销毁前确保停止所有音频播放
    if (_xiaozhiService != null) {
      _xiaozhiService!.stopPlayback();
      _xiaozhiService!.disconnect();
    }

    super.dispose();
  }

  // 初始化小智服务
  Future<void> _initXiaozhiService() async {
    final configProvider = Provider.of<ConfigProvider>(context, listen: false);
    XiaozhiConfig? xiaozhiConfig;
    for (final config in configProvider.xiaozhiConfigs) {
      if (config.id == widget.conversation.configId) {
        xiaozhiConfig = config;
        break;
      }
    }

    if (xiaozhiConfig == null) {
      print('ChatScreen: Không tìm thấy cấu hình Xiaozhi cho hội thoại này');
      return;
    }

    _xiaozhiService = XiaozhiService(
      websocketUrl: xiaozhiConfig.websocketUrl,
      macAddress: xiaozhiConfig.macAddress,
      token: xiaozhiConfig.token,
      otaUrl: xiaozhiConfig.otaUrl,
      clientId: xiaozhiConfig.clientId,
    );

    // 添加消息监听器
    _xiaozhiService!.addListener(_handleXiaozhiMessage);

    // 连接服务
    await _xiaozhiService!.connect();

    // 连接后刷新UI状态
    if (mounted) {
      setState(() {});
    }
  }

  // 处理小智消息
  void _handleXiaozhiMessage(XiaozhiServiceEvent event) {
    if (!mounted) return;

    final conversationProvider = Provider.of<ConversationProvider>(
      context,
      listen: false,
    );

    if (event.type == XiaozhiServiceEventType.textMessage) {
      // 直接使用文本内容
      String content = event.data as String;
      print('收到消息内容: $content');

      // 忽略空消息
      if (content.isNotEmpty) {
        conversationProvider.addMessage(
          conversationId: widget.conversation.id,
          role: MessageRole.assistant,
          content: content,
        );
      }
    } else if (event.type == XiaozhiServiceEventType.userMessage) {
      // 处理用户的语音识别文本
      String content = event.data as String;
      print('收到用户语音识别内容: $content');

      // 只有在语音输入模式下才添加用户消息
      if (content.isNotEmpty && _isVoiceInputMode) {
        // 语音消息可能有延迟，使用Future.microtask确保UI已更新
        Future.microtask(() {
          conversationProvider.addMessage(
            conversationId: widget.conversation.id,
            role: MessageRole.user,
            content: content,
          );
        });
      }
    } else if (event.type == XiaozhiServiceEventType.connected ||
        event.type == XiaozhiServiceEventType.disconnected) {
      // 当连接状态发生变化时，更新UI
      setState(() {});
    }
  }

  // 初始化 DifyService
  Future<void> _initDifyService() async {
    final configProvider = Provider.of<ConfigProvider>(context, listen: false);
    final String? configId = widget.conversation.configId;
    DifyConfig? difyConfig;

    if (configId != null && configId.isNotEmpty) {
      difyConfig =
          configProvider.difyConfigs
              .where((config) => config.id == configId)
              .firstOrNull;
    }

    if (difyConfig == null) {
      if (configProvider.difyConfigs.isEmpty) {
        throw Exception("Chưa cấu hình Dify, hãy cài đặt Dify API trước");
      }
      difyConfig = configProvider.difyConfigs.first;
    }

    _difyService = await DifyService.create(
      apiKey: difyConfig.apiKey,
      apiUrl: difyConfig.apiUrl,
    );
  }

  // 初始化 MiniMaxService
  void _initMiniMaxService() {
    final configProvider = Provider.of<ConfigProvider>(context, listen: false);
    final String? configId = widget.conversation.configId;
    MiniMaxConfig? minimaxConfig;

    if (configId != null && configId.isNotEmpty) {
      minimaxConfig =
          configProvider.minimaxConfigs
              .where((config) => config.id == configId)
              .firstOrNull;
    }

    if (minimaxConfig == null) {
      if (configProvider.minimaxConfigs.isEmpty) {
        throw Exception("Chưa cấu hình MiniMax, hãy cài đặt MiniMax API trước");
      }
      minimaxConfig = configProvider.minimaxConfigs.first;
    }

    _minimaxService = MiniMaxService(
      apiKey: minimaxConfig.apiKey,
      model: minimaxConfig.model,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 确保状态栏设置正确
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        toolbarHeight: 70,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        actions: [
          if (widget.conversation.type == ConversationType.dify ||
              widget.conversation.type == ConversationType.minimax)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.black, size: 24),
              tooltip: 'Cuộc trò chuyện mới',
              onPressed: _resetConversation,
            ),
          if (widget.conversation.type == ConversationType.xiaozhi)
            Container(
              // 右上角留出机器人系统电量浮层的位置
              margin: const EdgeInsets.only(right: 44),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _navigateToVoiceCall,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.phone, color: Colors.black, size: 16),
                    ),
                  ),
                ),
              ),
            ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 26),
          onPressed: () {
            // 返回前停止播放
            if (_xiaozhiService != null) {
              _xiaozhiService!.stopPlayback();
            }
            Navigator.of(context).pop();
          },
        ),
        title:
            widget.conversation.type == ConversationType.xiaozhi
                ? Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.3),
                            blurRadius: 8,
                            spreadRadius: 0,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.grey.shade700,
                        child: const Icon(
                          Icons.mic,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.conversation.title,
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 1,
                                spreadRadius: 0,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: const Text(
                            'Giọng nói',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                )
                : Consumer<ConfigProvider>(
                  builder: (context, configProvider, child) {
                    final String? configId = widget.conversation.configId;
                    String configName = widget.conversation.title;
                    final bool isMinimax =
                        widget.conversation.type == ConversationType.minimax;
                    final MaterialColor themeColor =
                        isMinimax ? Colors.teal : Colors.blue;

                    // 查找此会话对应的配置
                    if (configId != null && configId.isNotEmpty) {
                      if (isMinimax) {
                        final minimaxConfig =
                            configProvider.minimaxConfigs
                                .where((config) => config.id == configId)
                                .firstOrNull;
                        if (minimaxConfig != null) {
                          configName = minimaxConfig.name;
                        }
                      } else {
                        final difyConfig =
                            configProvider.difyConfigs
                                .where((config) => config.id == configId)
                                .firstOrNull;
                        if (difyConfig != null) {
                          configName = difyConfig.name;
                        }
                      }
                    }

                    return Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: themeColor.withOpacity(0.3),
                                blurRadius: 8,
                                spreadRadius: 0,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: themeColor.shade400,
                            child: Icon(
                              isMinimax
                                  ? Icons.auto_awesome
                                  : Icons.chat_bubble_outline,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              configName,
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: themeColor.shade50,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.03),
                                    blurRadius: 1,
                                    spreadRadius: 0,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Text(
                                isMinimax ? 'MiniMax' : 'Văn bản',
                                style: TextStyle(
                                  color: themeColor,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
      ),
      body: Column(
        children: [
          if (widget.conversation.type == ConversationType.xiaozhi)
            _buildXiaozhiInfo(),
          Expanded(child: _buildMessageList()),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildXiaozhiInfo() {
    final bool isConnected = _xiaozhiService?.isConnected ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 连接状态指示器
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected ? Colors.green : Colors.red,
              boxShadow: [
                BoxShadow(
                  color: (isConnected ? Colors.green : Colors.red).withOpacity(
                    0.4,
                  ),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isConnected ? 'Đã kết nối' : 'Chưa kết nối',
            style: TextStyle(
              fontSize: 13,
              color: isConnected ? Colors.green : Colors.red,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 12),

          // 分隔线
          Container(width: 1, height: 16, color: Colors.grey.withOpacity(0.3)),
          const SizedBox(width: 12),

          // 机器人语音状态（正在听 / 已停止听）
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child:
                  _xiaozhiService == null
                      ? const SizedBox.shrink()
                      : VoiceStateChip(state: _xiaozhiService!.voiceState),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return Consumer<ConversationProvider>(
      builder: (context, provider, child) {
        final messages = provider.getMessages(widget.conversation.id);

        if (messages.isEmpty) {
          return Center(
            child: Text(
              'Cuộc trò chuyện mới',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 16),
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          reverse: true,
          itemCount: messages.length + (_isLoading ? 1 : 0),
          cacheExtent: 1000.0,
          addRepaintBoundaries: true,
          addAutomaticKeepAlives: true,
          physics: const ClampingScrollPhysics(),
          itemBuilder: (context, index) {
            if (_isLoading && index == 0) {
              return MessageBubble(
                message: Message(
                  id: 'loading',
                  conversationId: '',
                  role: MessageRole.assistant,
                  content: 'Đang suy nghĩ...',
                  timestamp: DateTime.now(),
                ),
                isThinking: true,
                conversationType: widget.conversation.type,
              );
            }

            final adjustedIndex = _isLoading ? index - 1 : index;
            final message = messages[messages.length - 1 - adjustedIndex];

            return RepaintBoundary(
              child: MessageBubble(
                key: ValueKey(message.id),
                message: message,
                conversationType: widget.conversation.type,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInputArea() {
    final bool hasText = _textController.text.trim().isNotEmpty;

    // 根据状态决定显示文本输入还是语音输入
    if (_isVoiceInputMode &&
        widget.conversation.type == ConversationType.xiaozhi) {
      return _buildVoiceInputArea();
    } else {
      return _buildTextInputArea(hasText);
    }
  }

  // 文本输入区域
  Widget _buildTextInputArea(bool hasText) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 16,
        top: 16,
        right: 16,
        bottom: 16 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7F9),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.07),
                  blurRadius: 8,
                  spreadRadius: 0,
                  offset: const Offset(0, 3),
                ),
                BoxShadow(
                  color: Colors.white.withOpacity(0.8),
                  blurRadius: 5,
                  spreadRadius: 0,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Nhập tin nhắn...',
                      hintStyle: TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 16,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                    ),
                    style: const TextStyle(
                      color: Color(0xFF1F2937),
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (widget.conversation.type == ConversationType.dify &&
                    !hasText)
                  IconButton(
                    icon: const Icon(
                      Icons.add_circle_outline,
                      color: Color(0xFF9CA3AF), // 使用紫色，与小智的麦克风按钮风格一致
                      size: 24,
                    ),
                    onPressed: _showImagePickerOptions,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    constraints: const BoxConstraints(),
                    splashRadius: 22,
                  ),
                _buildSendButton(hasText),
                if (widget.conversation.type == ConversationType.xiaozhi &&
                    !hasText)
                  IconButton(
                    icon: const Icon(
                      Icons.mic,
                      color: Color.fromARGB(255, 108, 108, 112),
                      size: 24,
                    ),
                    onPressed: () {
                      setState(() {
                        _isVoiceInputMode = true;
                      });
                    },
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    constraints: const BoxConstraints(),
                    splashRadius: 22,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 语音输入区域
  Widget _buildVoiceInputArea() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 16,
        top: 16,
        right: 16,
        bottom: 16 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: GestureDetector(
              onLongPressStart: (details) {
                setState(() {
                  _isRecording = true;
                  _isCancelling = false;
                  _startDragY = details.globalPosition.dy;
                });
                _startRecording();
                _startWaveAnimation();
              },
              onLongPressMoveUpdate: (details) {
                // 计算垂直移动距离
                final double dragDistance =
                    _startDragY - details.globalPosition.dy;

                // 如果上滑超过阈值，标记为取消状态
                if (dragDistance > _cancelThreshold && !_isCancelling) {
                  setState(() {
                    _isCancelling = true;
                  });
                  // 震动反馈
                  HapticFeedback.mediumImpact();
                } else if (dragDistance <= _cancelThreshold && _isCancelling) {
                  setState(() {
                    _isCancelling = false;
                  });
                  // 震动反馈
                  HapticFeedback.lightImpact();
                }
              },
              onLongPressEnd: (details) {
                final wasRecording = _isRecording;
                final wasCancelling = _isCancelling;

                setState(() {
                  _isRecording = false;
                });

                _stopWaveAnimation();

                if (wasRecording) {
                  if (wasCancelling) {
                    _cancelRecording();
                  } else {
                    _stopRecording();
                  }
                }
              },
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  color:
                      _isRecording
                          ? _isCancelling
                              ? Colors.red.shade50
                              : Colors.blue.shade50
                          : const Color(0xFFF5F7F9),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.07),
                      blurRadius: 8,
                      spreadRadius: 0,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 波纹动画效果
                    if (_isRecording && !_isCancelling)
                      _buildWaveAnimationIndicator(),

                    // 文字提示
                    Center(
                      child: Text(
                        _isRecording
                            ? _isCancelling
                                ? "Thả tay để hủy"
                                : "Thả để gửi, vuốt lên để hủy"
                            : "Nhấn giữ để nói",
                        style: TextStyle(
                          color:
                              _isRecording
                                  ? _isCancelling
                                      ? Colors.red
                                      : Colors.blue.shade700
                                  : const Color.fromARGB(255, 9, 9, 9),
                          fontSize: 16,
                          fontWeight:
                              _isRecording
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 键盘按钮 (切换回文本模式)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  spreadRadius: 0,
                  offset: const Offset(0, 2),
                ),
                BoxShadow(
                  color: Colors.white.withOpacity(0.8),
                  blurRadius: 4,
                  spreadRadius: 0,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              shape: CircleBorder(),
              child: InkWell(
                borderRadius: BorderRadius.circular(25),
                onTap: () {
                  // 如果正在录音，先取消录音
                  if (_isRecording) {
                    _cancelRecording();
                    _stopWaveAnimation();
                  }
                  // 切换回文本输入模式
                  setState(() {
                    _isVoiceInputMode = false;
                    _isRecording = false;
                    _isCancelling = false;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Icon(
                    Icons.keyboard,
                    color: Colors.grey.shade700,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendButton(bool hasText) {
    return IconButton(
      key: const ValueKey('send_button'),
      icon: Icon(
        Icons.send_rounded,
        color: hasText ? Colors.black : const Color(0xFFC4C9D2),
        size: 24,
      ),
      onPressed: hasText ? _sendMessage : null,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      constraints: const BoxConstraints(),
      splashRadius: 22,
    );
  }

  // 开始录音
  void _startRecording() async {
    if (widget.conversation.type != ConversationType.xiaozhi ||
        _xiaozhiService == null) {
      _showCustomSnackbar('Giọng nói chỉ dùng cho Xiaozhi');
      setState(() {
        _isVoiceInputMode = false;
      });
      return;
    }

    try {
      // 震动反馈
      HapticFeedback.mediumImpact();

      // 开始录音
      await _xiaozhiService!.startListening();
    } catch (e) {
      print('开始录音失败: $e');
      _showCustomSnackbar('Không thể ghi âm: ${e.toString()}');
      setState(() {
        _isRecording = false;
        _isVoiceInputMode = false;
      });
    }
  }

  // 停止录音并发送
  void _stopRecording() async {
    try {
      setState(() {
        _isLoading = true;
        _isRecording = false;
        // 不要立即关闭语音输入模式，让用户可以看到识别结果
        // _isVoiceInputMode = false;
      });

      // 震动反馈
      HapticFeedback.mediumImpact();

      // 停止录音
      await _xiaozhiService?.stopListening();

      _scrollToBottom();
    } catch (e) {
      print('停止录音失败: $e');
      _showCustomSnackbar('Gửi giọng nói thất bại: ${e.toString()}');

      // 出错时关闭语音输入模式
      setState(() {
        _isVoiceInputMode = false;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 取消录音
  void _cancelRecording() async {
    try {
      setState(() {
        _isRecording = false;
      });

      // 震动反馈
      HapticFeedback.heavyImpact();

      // 取消录音
      await _xiaozhiService?.abortListening();

      // 使用自定义的拟物化提示，显示在顶部且带有圆角
      _showCustomSnackbar('Đã hủy gửi');
    } catch (e) {
      print('取消录音失败: $e');
    }
  }

  // 显示自定义Snackbar
  void _showCustomSnackbar(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final snackBar = SnackBar(
      content: Text(
        message,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.black.withOpacity(0.7),
      duration: const Duration(seconds: 2),
      margin: EdgeInsets.only(
        bottom: MediaQuery.of(context).size.height - 120,
        left: 16,
        right: 16,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  void _resetConversation() async {
    // 给用户一个清晰的提示
    _showCustomSnackbar('Đang bắt đầu trò chuyện mới...');

    final conversationProvider = Provider.of<ConversationProvider>(
      context,
      listen: false,
    );

    if (widget.conversation.type == ConversationType.minimax) {
      final sessionId = widget.conversation.id;
      _minimaxService?.clearConversation(sessionId);

      await conversationProvider.addMessage(
        conversationId: widget.conversation.id,
        role: MessageRole.system,
        content: '--- Cuộc trò chuyện mới ---',
      );

      _showCustomSnackbar('Đã bắt đầu trò chuyện mới');
    } else if (_difyService != null) {
      // 使用会话的ID作为sessionId，确保与发送消息时使用相同的标识符
      final sessionId = widget.conversation.id;

      // 清除当前会话的conversation_id
      await _difyService!.clearConversation(sessionId);

      // 添加系统消息表明这是一个新对话
      await conversationProvider.addMessage(
        conversationId: widget.conversation.id,
        role: MessageRole.system,
        content: '--- Cuộc trò chuyện mới ---',
      );

      _showCustomSnackbar('Đã bắt đầu trò chuyện mới');
    } else {
      _showCustomSnackbar('Chưa cấu hình, không thể đặt lại');
    }
  }

  void _sendMessage() async {
    final message = _textController.text.trim();
    if (message.isEmpty || _isLoading) return;

    _textController.clear();

    final conversationProvider = Provider.of<ConversationProvider>(
      context,
      listen: false,
    );

    // Add user message
    await conversationProvider.addMessage(
      conversationId: widget.conversation.id,
      role: MessageRole.user,
      content: message,
    );

    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    _scrollToBottom();

    try {
      if (widget.conversation.type == ConversationType.minimax) {
        if (_minimaxService == null) {
          _initMiniMaxService();
        }

        if (_minimaxService == null) {
          throw Exception(
            "Chưa cấu hình MiniMax, hãy cài đặt MiniMax API trước",
          );
        }

        final sessionId = widget.conversation.id;

        final response = await _minimaxService!.sendMessage(
          message,
          sessionId: sessionId,
          forceNewConversation: false,
        );

        if (!mounted) return;

        await conversationProvider.addMessage(
          conversationId: widget.conversation.id,
          role: MessageRole.assistant,
          content: response,
        );
      } else if (widget.conversation.type == ConversationType.dify) {
        if (_difyService == null) {
          await _initDifyService();
        }

        if (_difyService == null) {
          throw Exception("Chưa cấu hình Dify, hãy cài đặt Dify API trước");
        }

        // 使用会话的ID作为sessionId，使每次请求保持相同的对话上下文
        final sessionId = widget.conversation.id;

        // 使用阻塞式响应
        final response = await _difyService!.sendMessage(
          message,
          sessionId: sessionId, // 使用一致的会话ID
          // 永远不要在普通消息中使用forceNewConversation，除非用户明确请求开始新对话
          forceNewConversation: false,
        );

        if (!mounted) return; // 再次检查组件是否还在widget树中

        // 添加助手回复
        await conversationProvider.addMessage(
          conversationId: widget.conversation.id,
          role: MessageRole.assistant,
          content: response,
        );
      } else {
        // 确保服务已连接
        if (_xiaozhiService == null) {
          await _initXiaozhiService();
        } else if (!_xiaozhiService!.isConnected) {
          // 如果未连接，尝试重新连接
          print('聊天屏幕: 服务未连接，尝试重新连接');
          await _xiaozhiService!.connect();

          // 如果重连失败，提示用户
          if (!_xiaozhiService!.isConnected) {
            throw Exception(
              "Không thể kết nối Xiaozhi, hãy kiểm tra mạng hoặc cấu hình",
            );
          }

          // 刷新UI显示连接状态
          setState(() {});
        }

        // 发送消息
        await _xiaozhiService!.sendTextMessage(message);
      }
    } catch (e) {
      print('聊天屏幕: 发送消息错误: $e');

      if (!mounted) return;

      // Add error message
      await conversationProvider.addMessage(
        conversationId: widget.conversation.id,
        role: MessageRole.assistant,
        content: 'Đã xảy ra lỗi: ${e.toString()}',
      );
    } finally {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _navigateToVoiceCall() {
    final configProvider = Provider.of<ConfigProvider>(context, listen: false);
    final xiaozhiConfig = configProvider.xiaozhiConfigs.firstWhere(
      (config) => config.id == widget.conversation.configId,
    );

    // 导航前停止当前音频播放
    if (_xiaozhiService != null) {
      _xiaozhiService!.stopPlayback();
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => VoiceCallScreen(
              conversation: widget.conversation,
              xiaozhiConfig: xiaozhiConfig,
            ),
      ),
    ).then((_) {
      // 页面返回后，确保重新初始化服务以恢复正常对话功能
      if (_xiaozhiService != null &&
          widget.conversation.type == ConversationType.xiaozhi) {
        // 重新连接服务
        _xiaozhiService!.connect();
      }
    });
  }

  // 启动波形动画
  void _startWaveAnimation() {
    _waveAnimationTimer?.cancel();
    _waveAnimationTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) {
      if (_isRecording && !_isCancelling) {
        setState(() {
          for (int i = 0; i < _waveHeights.length; i++) {
            _waveHeights[i] = 0.5 + _random.nextDouble() * 0.5;
          }
        });
      }
    });
  }

  // 停止波形动画
  void _stopWaveAnimation() {
    _waveAnimationTimer?.cancel();
    _waveAnimationTimer = null;
  }

  // 构建波形动画指示器
  Widget _buildWaveAnimationIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(
          16,
          (index) => AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 3,
            height: 20 * _waveHeights[index],
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.6),
              borderRadius: BorderRadius.circular(1.5),
            ),
            curve: Curves.easeInOut,
          ),
        ),
      ),
    );
  }

  // 显示图片选择器选项
  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      elevation: 20,
      barrierColor: Colors.black.withOpacity(0.5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部拖动条
              Container(
                width: 36,
                height: 5,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 1,
                      spreadRadius: 0,
                      offset: const Offset(0, 0.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // 从相册选择选项
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 10,
                        spreadRadius: 0,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 6,
                      ),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.1),
                              blurRadius: 4,
                              spreadRadius: 0,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.photo_library,
                          color: Colors.blue.shade600,
                          size: 24,
                        ),
                      ),
                      title: const Text(
                        'Chọn từ thư viện',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      subtitle: Text(
                        'Chọn ảnh có sẵn',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        _pickImage(true);
                      },
                    ),
                  ),
                ),
              ),

              // 拍照选项
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 10,
                        spreadRadius: 0,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 6,
                      ),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withOpacity(0.1),
                              blurRadius: 4,
                              spreadRadius: 0,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.camera_alt,
                          color: Colors.green.shade600,
                          size: 24,
                        ),
                      ),
                      title: const Text(
                        'Chụp ảnh',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      subtitle: Text(
                        'Chụp ảnh mới',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        _pickImage(false);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage(bool fromGallery) async {
    if (widget.conversation.type != ConversationType.dify) {
      _showCustomSnackbar('Tải ảnh chỉ dùng cho Dify');
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      if (_difyService == null) {
        await _initDifyService();
      }

      if (_difyService == null) {
        throw Exception("Chưa cấu hình Dify, hãy cài đặt Dify API trước");
      }

      final ImagePicker picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(
        source: fromGallery ? ImageSource.gallery : ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1500,
      );

      if (pickedFile == null) {
        _showCustomSnackbar('Đã hủy chọn');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // 获取应用的文档目录
      final appDir = await getApplicationDocumentsDirectory();
      final conversationDir = Directory(
        '${appDir.path}/conversations/${widget.conversation.id}/images',
      );
      await conversationDir.create(recursive: true);

      // 生成唯一的文件名
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = pickedFile.path.split('.').last;
      final fileName = 'image_$timestamp.$extension';
      final localPath = '${conversationDir.path}/$fileName';

      // 复制图片到永久存储
      final File imageFile = File(pickedFile.path);
      await imageFile.copy(localPath);

      print('图片已保存到永久存储: $localPath');

      final sessionId = widget.conversation.id;

      // 在消息列表中显示用户上传的图片消息
      final conversationProvider = Provider.of<ConversationProvider>(
        context,
        listen: false,
      );

      // 添加用户消息，使用永久存储的路径
      await conversationProvider.addMessage(
        conversationId: widget.conversation.id,
        role: MessageRole.user,
        content: "[Đang tải ảnh lên...]",
        isImage: true,
        imageLocalPath: localPath,
      );

      _scrollToBottom();

      // 上传图片到Dify API
      final response = await _difyService!.uploadFile(File(localPath));

      if (response.containsKey('id')) {
        final fileId = response['id'];
        final messageContent = "";

        // 更新最后一条用户消息为实际的图片消息
        await conversationProvider.updateLastUserMessage(
          conversationId: widget.conversation.id,
          content: messageContent,
          fileId: fileId,
          isImage: true,
          imageLocalPath: localPath,
        );

        final textPrompt = "Phân tích hình ảnh này";
        final chatResponse = await _difyService!.sendMessage(
          textPrompt,
          sessionId: sessionId,
          fileIds: [fileId],
        );

        await conversationProvider.addMessage(
          conversationId: widget.conversation.id,
          role: MessageRole.assistant,
          content: chatResponse,
        );
      } else {
        throw Exception(
          "Tải lên thành công nhưng máy chủ không trả về ID tệp: $response",
        );
      }

      _showCustomSnackbar('Tải ảnh lên thành công');
    } catch (e) {
      print('图片上传失败: $e');

      final conversationProvider = Provider.of<ConversationProvider>(
        context,
        listen: false,
      );
      await conversationProvider.addMessage(
        conversationId: widget.conversation.id,
        role: MessageRole.assistant,
        content: 'Tải ảnh lên thất bại: ${e.toString()}',
      );

      _showCustomSnackbar('Tải ảnh lên thất bại: ${e.toString()}');
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }
}

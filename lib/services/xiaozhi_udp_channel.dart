import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// 小智 MQTT 模式下的 UDP 音频通道。
///
/// 协议与 xiaozhi-esp32 固件 mqtt_protocol.cc 一致：
/// 每个 UDP 包 = 16 字节 nonce 头 + AES-128-CTR 加密的 Opus 帧。
/// 头部格式（大端）：
///   [0]      type = 0x01
///   [1]      flags
///   [2..3]   payload 长度
///   [4..7]   ssrc（沿用服务器下发 nonce 中的值）
///   [8..11]  timestamp
///   [12..15] sequence
/// 加解密都以该 16 字节头作为 CTR 的 IV。
class XiaozhiUdpChannel {
  static const String TAG = "XiaozhiUdp";

  final String server;
  final int port;
  final Uint8List _key;
  final Uint8List _nonceTemplate;
  final void Function(Uint8List opus) onAudio;

  RawDatagramSocket? _socket;
  InternetAddress? _serverAddress;
  int _localSequence = 0;
  int _remoteSequence = 0;
  int _lost = 0;
  int _late = 0;
  int _received = 0;
  int _sent = 0;
  final Stopwatch _clock = Stopwatch();

  XiaozhiUdpChannel({
    required this.server,
    required this.port,
    required String keyHex,
    required String nonceHex,
    required this.onAudio,
  }) : _key = _hexToBytes(keyHex),
       _nonceTemplate = _hexToBytes(nonceHex) {
    if (_key.length != 16 || _nonceTemplate.length != 16) {
      throw ArgumentError('UDP key/nonce 长度必须为 16 字节');
    }
  }

  bool get isOpen => _socket != null && _serverAddress != null;

  Future<void> open() async {
    final addresses = await InternetAddress.lookup(server);
    _serverAddress = addresses.firstWhere(
      (a) => a.type == InternetAddressType.IPv4,
      orElse: () => addresses.first,
    );
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket!.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? dg;
      while ((dg = _socket?.receive()) != null) {
        _onDatagram(dg!.data);
      }
    });
    _clock
      ..reset()
      ..start();
    print('$TAG: UDP 通道已打开 -> ${_serverAddress!.address}:$port');
    // 服务器只在收到合法 Opus 包后才记录本端地址（空包无效），
    // 文字聊天时不会上行音频，所以先发几帧 Opus 静音包"打洞"
    for (int i = 0; i < 3; i++) {
      send(const <int>[0xF8, 0xFF, 0xFE]);
    }
  }

  /// 发送一帧 Opus 音频
  void send(List<int> opus) {
    final socket = _socket;
    final address = _serverAddress;
    if (socket == null || address == null) {
      print('$TAG: UDP 未打开，丢弃音频帧');
      return;
    }
    if (++_sent % 50 == 0) print('$TAG: 已发送 $_sent 个音频包');

    final header = Uint8List.fromList(_nonceTemplate);
    final bd = ByteData.sublistView(header);
    bd.setUint16(2, opus.length, Endian.big);
    bd.setUint32(8, _clock.elapsedMilliseconds & 0xFFFFFFFF, Endian.big);
    bd.setUint32(12, ++_localSequence & 0xFFFFFFFF, Endian.big);

    final encrypted = _ctr(header, Uint8List.fromList(opus));
    final packet =
        Uint8List(16 + encrypted.length)
          ..setRange(0, 16, header)
          ..setRange(16, 16 + encrypted.length, encrypted);
    socket.send(packet, address, port);
  }

  void _onDatagram(Uint8List data) {
    if (data.length < 16) return;
    if (data[0] != 0x01) {
      print('$TAG: 未知包类型 ${data[0]}');
      return;
    }
    final header = Uint8List.sublistView(data, 0, 16);
    final sequence = ByteData.sublistView(header).getUint32(12, Endian.big);
    if (sequence <= _remoteSequence || _reorder.containsKey(sequence)) {
      // 已经补偿过/重复的包直接丢弃
      _late++;
      print('$TAG: 乱序包被丢弃 seq=$sequence <= $_remoteSequence（累计 $_late）');
      return;
    }
    _received++;
    if (_received == 1 || _received % 100 == 0) {
      print('$TAG: 已收到 $_received 个音频包（丢 $_lost，乱序 $_late）');
    }
    _reorder[sequence] = _ctr(
      Uint8List.fromList(header),
      Uint8List.sublistView(data, 16),
    );
    _drainReorder();
  }

  /// WiFi 上偶尔有包晚到一两个位置：先按序号排好再交给播放端，
  /// 缺口最多等 [_reorderWaitMs] 或 [_reorderMaxPending] 个后续包，
  /// 还没到才算丢包并做 Opus 丢包补偿（PLC）。
  static const _reorderWaitMs = 150;
  static const _reorderMaxPending = 3;
  final Map<int, Uint8List> _reorder = {};
  Timer? _reorderTimer;

  void _drainReorder({bool force = false}) {
    while (_reorder.isNotEmpty) {
      final next = _remoteSequence + 1;
      final ready = _reorder.remove(next);
      if (ready != null || _remoteSequence == 0) {
        if (ready == null) {
          // 第一个包：从最小序号开始
          final first = _reorder.keys.reduce((a, b) => a < b ? a : b);
          _remoteSequence = first;
          onAudio(_reorder.remove(first)!);
        } else {
          _remoteSequence = next;
          onAudio(ready);
        }
        continue;
      }
      if (!force && _reorder.length < _reorderMaxPending) {
        _reorderTimer ??= Timer(
          const Duration(milliseconds: _reorderWaitMs),
          () {
            _reorderTimer = null;
            _drainReorder(force: true);
          },
        );
        return;
      }
      // 等不到了：缺的包算丢失
      final first = _reorder.keys.reduce((a, b) => a < b ? a : b);
      final gap = first - _remoteSequence - 1;
      _lost += gap;
      // 间隔太大（新的一段/重连）就不补
      if (gap <= 5) {
        for (int i = 0; i < gap; i++) {
          onAudio(Uint8List(0));
        }
      }
      _remoteSequence = first - 1;
    }
    _reorderTimer?.cancel();
    _reorderTimer = null;
  }

  Uint8List _ctr(Uint8List iv, Uint8List input) {
    final cipher = CTRStreamCipher(AESEngine())
      ..init(true, ParametersWithIV(KeyParameter(_key), iv));
    return cipher.process(input);
  }

  void close() {
    _socket?.close();
    _socket = null;
    _serverAddress = null;
    _clock.stop();
    print('$TAG: UDP 通道已关闭');
  }

  static Uint8List _hexToBytes(String hex) {
    final clean = hex.trim();
    final out = Uint8List(clean.length ~/ 2);
    for (int i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}

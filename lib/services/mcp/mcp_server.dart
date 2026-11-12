import 'dart:async';

typedef McpArguments = Map<String, dynamic>;

class McpTool {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final Future<String> Function(McpArguments) handler;
  final bool Function()? enabled;

  const McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.handler,
    this.enabled,
  });

  bool get isEnabled => enabled?.call() ?? true;
  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'inputSchema': inputSchema,
  };
}

/// Transport-independent JSON-RPC endpoint. No hardware work runs for notifications.
class McpServer {
  final Map<String, McpTool> _tools = {};
  final Future<void> Function()? beforeRequest;
  final Map<Object, Future<Map<String, dynamic>?>> _requests = {};

  McpServer({this.beforeRequest});

  void register(McpTool tool) {
    if (_tools.containsKey(tool.name)) {
      throw ArgumentError('Duplicate MCP tool: ${tool.name}');
    }
    _tools[tool.name] = tool;
  }

  void resetSession() => _requests.clear();

  Future<Map<String, dynamic>?> handle(dynamic payload) {
    if (payload is! Map || (payload['id'] is! int && payload['id'] is! String)) {
      return _handle(payload);
    }
    final id = payload['id'] as Object;
    // Retransmitted tool calls must not drive the wheels twice.
    if (_requests.containsKey(id)) return _requests[id]!;
    if (_requests.length >= 64) _requests.remove(_requests.keys.first);
    return _requests[id] = _handle(payload);
  }

  Future<Map<String, dynamic>?> _handle(dynamic payload) async {
    if (payload is! Map ||
        payload['jsonrpc'] != '2.0' ||
        payload['method'] is! String) {
      return _error(null, -32600, 'Invalid Request');
    }
    final id = payload['id'];
    if (!payload.containsKey('id')) return null;
    if (id is! String && id is! int) {
      return _error(null, -32600, 'Invalid request id');
    }
    final params = payload['params'] ?? <String, dynamic>{};
    if (params is! Map || params.keys.any((key) => key is! String)) {
      return _error(id, -32602, 'Invalid params');
    }
    try {
      await beforeRequest?.call();
      switch (payload['method']) {
        case 'initialize':
          return _result(id, {
            'protocolVersion': '2024-11-05',
            'capabilities': {'tools': <String, dynamic>{}},
            'serverInfo': {'name': 'xiaozhi-android', 'version': '2.0.0'},
          });
        case 'ping':
          return _result(id, <String, dynamic>{});
        case 'tools/list':
          // The small on-device registry fits in one page.
          if (params['cursor'] != null && params['cursor'] != '') {
            return _error(id, -32602, 'Invalid cursor');
          }
          return _result(id, {
            'tools': [
              for (final t in _tools.values)
                if (t.isEnabled) t.toJson(),
            ],
          });
        case 'tools/call':
          final tool = _tools[params['name']];
          if (tool == null || !tool.isEnabled) {
            return _error(id, -32601, 'Unknown or disabled tool');
          }
          final args = params['arguments'] ?? <String, dynamic>{};
          if (args is! Map || args.keys.any((key) => key is! String)) {
            return _error(id, -32602, 'Invalid arguments');
          }
          final arguments = Map<String, dynamic>.from(args);
          final invalid = _validate(tool.inputSchema, arguments);
          if (invalid != null) return _error(id, -32602, invalid);
          try {
            final text = await tool.handler(arguments);
            return _result(id, {
              'content': [
                {'type': 'text', 'text': text},
              ],
              'isError': false,
            });
          } catch (e) {
            return _result(id, {
              'content': [
                {'type': 'text', 'text': e.toString()},
              ],
              'isError': true,
            });
          }
        default:
          return _error(id, -32601, 'Method not found');
      }
    } catch (_) {
      return _error(id, -32603, 'Device tools unavailable');
    }
  }

  String? _validate(Map<String, dynamic> schema, McpArguments args) {
    final properties = schema['properties'] as Map? ?? {};
    for (final key in schema['required'] as List? ?? []) {
      if (!args.containsKey(key)) return 'Missing argument: $key';
    }
    for (final entry in args.entries) {
      if (!properties.containsKey(entry.key)) {
        return 'Unknown argument: ${entry.key}';
      }
      final rule = properties[entry.key] as Map;
      final value = entry.value;
      final valid = switch (rule['type']) {
        'string' => value is String,
        'integer' => value is int,
        'number' => value is num && value.isFinite,
        'boolean' => value is bool,
        _ => false,
      };
      if (!valid) return 'Invalid type: ${entry.key}';
      if (rule['enum'] is List && !(rule['enum'] as List).contains(value)) {
        return 'Invalid value: ${entry.key}';
      }
      if (value is num &&
          ((rule['minimum'] is num && value < rule['minimum']) ||
              (rule['maximum'] is num && value > rule['maximum']))) {
        return 'Out of range: ${entry.key}';
      }
    }
    return null;
  }

  Map<String, dynamic> _result(dynamic id, Object result) => {
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  };
  Map<String, dynamic> _error(dynamic id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };
}

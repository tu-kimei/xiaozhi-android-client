import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_assistant/services/mcp/mcp_server.dart';

void main() {
  late McpServer server;
  var calls = 0;
  var enabled = true;
  Map<String, dynamic> request(
    String method, {
    int id = 1,
    Map<String, dynamic>? params,
  }) => {
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    if (params != null) 'params': params,
  };
  setUp(() {
    calls = 0;
    enabled = true;
    server = McpServer();
    server.register(
      McpTool(
        name: 'test.move',
        description: 'test',
        enabled: () => enabled,
        inputSchema: const {
          'type': 'object',
          'properties': {
            'steps': {'type': 'integer', 'minimum': 1, 'maximum': 10},
          },
          'required': ['steps'],
        },
        handler: (args) async {
          calls++;
          return 'done';
        },
      ),
    );
  });

  test(
    'initialize and discovery follow the Xiaozhi JSON-RPC envelope',
    () async {
      final initialized = await server.handle(request('initialize'));
      expect(initialized!['id'], 1);
      expect(initialized['result']['protocolVersion'], '2024-11-05');
      final listed = await server.handle(request('tools/list', id: 2));
      expect(listed!['result']['tools'].single['name'], 'test.move');
      enabled = false;
      expect(
        (await server.handle(request('tools/list', id: 3)))!['result']['tools'],
        isEmpty,
      );
    },
  );
  test(
    'tool results wait for completion and duplicate requests execute once',
    () async {
      final done = Completer<String>();
      server.register(
        McpTool(
          name: 'long',
          description: 'test',
          inputSchema: const {'properties': {}},
          handler: (_) {
            calls++;
            return done.future;
          },
        ),
      );
      final req = request('tools/call', params: {'name': 'long'});
      final first = server.handle(req);
      final duplicate = server.handle(req);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      done.complete('finished');
      expect((await first)!['result']['content'].single['text'], 'finished');
      expect(await duplicate, await first);
      server.resetSession();
      await server.handle(req);
      expect(calls, 2);
    },
  );
  test(
    'unknown, malformed, disabled and unsafe requests never execute',
    () async {
      expect(
        (await server.handle({'method': 'tools/call'}))!['error']['code'],
        -32600,
      );
      expect(
        (await server.handle(request('unknown', id: 2)))!['error']['code'],
        -32601,
      );
      for (final value in [0, 11, 1.5, '2', null]) {
        server.resetSession();
        final result = await server.handle(
          request(
            'tools/call',
            params: {
              'name': 'test.move',
              'arguments': {'steps': value},
            },
          ),
        );
        expect(result!['error']['code'], -32602);
      }
      server.resetSession();
      expect(
        (await server.handle(
          request(
            'tools/call',
            params: {
              'name': 'test.move',
              'arguments': {'steps': 1, 'speed': 1000},
            },
          ),
        ))!['error']['code'],
        -32602,
      );
      server.resetSession();
      enabled = false;
      expect(
        (await server.handle(
          request(
            'tools/call',
            params: {
              'name': 'test.move',
              'arguments': {'steps': 1},
            },
          ),
        ))!['error']['code'],
        -32601,
      );
      expect(
        await server.handle({
          'jsonrpc': '2.0',
          'method': 'tools/call',
          'params': {'name': 'test.move'},
        }),
        isNull,
      );
      expect(calls, 0);
    },
  );
  test('hardware failures return MCP tool errors', () async {
    server.register(
      McpTool(
        name: 'fail',
        description: 'test',
        inputSchema: const {'properties': {}},
        handler: (_) => Future.error(StateError('stopped')),
      ),
    );
    final result = await server.handle(
      request('tools/call', params: {'name': 'fail'}),
    );
    expect(result!['result']['isError'], isTrue);
  });
}

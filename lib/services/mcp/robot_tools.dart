import '../robot_motion_controller.dart';
import '../robot_preferences.dart';
import 'mcp_server.dart';

void registerRobotTools(
  McpServer server,
  RobotMotionController motion,
  RobotPreferences preferences, {
  required bool Function() available,
}) {
  bool voiceEnabled() => available() && preferences.voiceEnabled;
  server.register(
    McpTool(
      name: 'self.robot.stop',
      description:
          'Dừng ngay mọi chuyển động và xóa lệnh đang chờ. Dùng khi bé nói dừng, đứng lại, stop. Luôn được phép.',
      inputSchema: const {
        'type': 'object',
        'properties': {},
        'additionalProperties': false,
      },
      handler: (_) async {
        await motion.stop(requireConfirmation: true);
        return 'Đã dừng robot và xóa các động tác đang chờ.';
      },
    ),
  );
  server.register(
    McpTool(
      name: 'self.robot.head',
      description:
          'Cử động đầu robot. Bé nói ngẩng đầu → up, cúi đầu → down, nhìn thẳng → center, gật đầu/đồng ý → nod. Chờ từng động tác xong rồi gọi động tác tiếp theo. Không hỗ trợ lắc ngang.',
      enabled: voiceEnabled,
      inputSchema: const {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['up', 'down', 'center', 'nod'],
          },
        },
        'required': ['action'],
        'additionalProperties': false,
      },
      handler: (args) => motion.head(args['action'] as String),
    ),
  );
  server.register(
    McpTool(
      name: 'self.robot.move',
      description:
          'Di chuyển robot khi bé yêu cầu: tiến lên/đi tới → forward, lùi → backward; rẽ trái/phải một góc vuông → left/right; xoay vòng sang trái/phải → spinleft/spinright. steps là số bước 1–10 khi đi thẳng; rotations là số vòng 0.25–5 khi xoay. Một bước khoảng nửa giây, mỗi lệnh tối đa 10 giây. Câu nhiều động tác: gọi lần lượt và đợi kết quả từng lệnh.',
      enabled: () => voiceEnabled() && preferences.wheelsEnabled,
      inputSchema: const {
        'type': 'object',
        'properties': {
          'direction': {
            'type': 'string',
            'enum': [
              'forward',
              'backward',
              'left',
              'right',
              'spinleft',
              'spinright',
            ],
          },
          'steps': {'type': 'integer', 'minimum': 1, 'maximum': 10},
          'rotations': {'type': 'number', 'minimum': 0.25, 'maximum': 5},
        },
        'required': ['direction'],
        'additionalProperties': false,
      },
      handler:
          (args) => motion.move(
            args['direction'] as String,
            steps: args['steps'] as int? ?? 1,
            rotations: (args['rotations'] as num? ?? 1).toDouble(),
          ),
    ),
  );
}

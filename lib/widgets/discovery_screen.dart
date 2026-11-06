import 'package:flutter/material.dart';
import 'package:ai_assistant/screens/robot_control_screen.dart';

class DiscoveryScreen extends StatelessWidget {
  const DiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppBar(
          title: const Text(
            'Khám phá',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 28,
              color: Colors.black,
            ),
          ),
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: const Color(0xFFF8F9FA),
          centerTitle: false,
          titleSpacing: 20,
          toolbarHeight: 65,
        ),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Text(
                    'Công cụ hữu ích',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                _buildFeaturesGrid(context),
                const SizedBox(height: 24),

                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Text(
                    'Đề xuất nổi bật',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                _buildRecommendations(context),
                // 添加底部间距，避免内容被底部导航栏遮挡
                SizedBox(height: MediaQuery.of(context).padding.bottom + 80),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturesGrid(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.3,
      children: [
        _buildFeatureCard(
          context,
          'Điều khiển robot',
          'Gật đầu, di chuyển bánh xe',
          Icons.smart_toy_outlined,
          const Color(0xFF00897B),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RobotControlScreen()),
            );
          },
        ),
        _buildFeatureCard(
          context,
          'Trợ lý đọc',
          'Hiểu và tóm tắt bài viết nhanh',
          Icons.menu_book_outlined,
          const Color(0xFFFF6D00),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Trợ lý đọc đang được phát triển...'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
        _buildFeatureCard(
          context,
          'Công cụ dịch',
          'Dịch đa ngôn ngữ tức thì',
          Icons.translate_outlined,
          const Color(0xFF2979FF),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Công cụ dịch đang được phát triển...'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
        _buildFeatureCard(
          context,
          'Trợ lý giọng nói',
          'Tương tác giọng nói thông minh',
          Icons.mic_outlined,
          const Color(0xFF6200EA),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Trợ lý giọng nói đang được phát triển...'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
        _buildFeatureCard(
          context,
          'Phân tích tài liệu',
          'Phân tích nội dung tài liệu thông minh',
          Icons.description_outlined,
          const Color(0xFF00BFA5),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Phân tích tài liệu đang được phát triển...'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildFeatureCard(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    Color color, {
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, color.withOpacity(0.8)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 10,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              bottom: -20,
              child: Icon(
                icon,
                size: 100,
                color: Colors.white.withOpacity(0.2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: Colors.white, size: 28),
                  const Spacer(),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendations(BuildContext context) {
    return SizedBox(
      height: 180,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _buildRecommendationCard(
            context,
            'Trợ lý viết AI',
            'Giúp bài viết chuyên nghiệp hơn',
            'assets/images/writing.png',
            const Color(0xFFE91E63),
          ),
          _buildRecommendationCard(
            context,
            'Nhắc nhở thông minh',
            'Không bỏ lỡ việc quan trọng',
            'assets/images/reminder.png',
            const Color(0xFF4CAF50),
          ),
          _buildRecommendationCard(
            context,
            'Ghi chú giọng nói',
            'Ghi lại ý tưởng mọi lúc mọi nơi',
            'assets/images/voice_note.png',
            const Color(0xFF3F51B5),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationCard(
    BuildContext context,
    String title,
    String description,
    String imagePath,
    Color color,
  ) {
    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$title đang được phát triển...'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            splashColor: color.withOpacity(0.1),
            highlightColor: color.withOpacity(0.1),
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(height: 6, color: color),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Icon(
                            Icons.auto_awesome,
                            color: color,
                            size: 28,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Spacer(),
                          Icon(Icons.arrow_forward, size: 16, color: color),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

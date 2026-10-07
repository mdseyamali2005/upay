import 'package:flutter/material.dart';

/// Full Agent AI artwork, including the উপায় mark and the AGENT AI name.
class AgentAiMark extends StatelessWidget {
  final double size;

  const AgentAiMark({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE8F0FC), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/agent_ai.jpg',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

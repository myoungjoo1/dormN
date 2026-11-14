import 'package:flutter/material.dart';

class HostSettlementPage extends StatelessWidget {
  const HostSettlementPage({required this.postId, super.key});

  final int postId;

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('모집자 정산 화면을 구현합니다.')),
    );
  }
}

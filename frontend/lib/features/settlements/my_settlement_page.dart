import 'package:flutter/material.dart';

class MySettlementPage extends StatelessWidget {
  const MySettlementPage({required this.postId, super.key});

  final int postId;

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('내 정산 화면을 구현합니다.')),
    );
  }
}

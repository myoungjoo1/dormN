import 'package:flutter/material.dart';

class PostDetailPage extends StatelessWidget {
  const PostDetailPage({required this.postId, super.key});

  final int postId;

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('공동구매 상세 화면을 구현합니다.')),
    );
  }
}

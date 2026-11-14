class Post {
  const Post({
    required this.id,
    required this.authorId,
    required this.productName,
    required this.productUrl,
    required this.imageUrl,
    required this.totalPrice,
    required this.totalQuantity,
    required this.hostQuantity,
    required this.deadline,
    required this.pickupLocation,
    required this.shortfallPolicy,
    required this.status,
    required this.createdAt,
    required this.authorRoomNumber,
    required this.joinedQuantity,
    required this.remainingQuantity,
    required this.participantCount,
  });

  final int id;
  final String authorId;
  final String productName;
  final String? productUrl;
  final String? imageUrl;
  final int totalPrice;
  final int totalQuantity;
  final int hostQuantity;
  final DateTime deadline;
  final String pickupLocation;
  final String shortfallPolicy;
  final String status;
  final DateTime createdAt;
  final String? authorRoomNumber;
  final int joinedQuantity;
  final int remainingQuantity;
  final int participantCount;

  int get filledQuantity => totalQuantity - remainingQuantity;

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'] as int,
      authorId: json['author_id'] as String,
      productName: json['product_name'] as String,
      productUrl: json['product_url'] as String?,
      imageUrl: json['image_url'] as String?,
      totalPrice: json['total_price'] as int,
      totalQuantity: json['total_quantity'] as int,
      hostQuantity: json['host_quantity'] as int,
      deadline: DateTime.parse(json['deadline'] as String),
      pickupLocation: json['pickup_location'] as String,
      shortfallPolicy: json['shortfall_policy'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      authorRoomNumber: json['author_room_number'] as String?,
      joinedQuantity: json['joined_quantity'] as int,
      remainingQuantity: json['remaining_quantity'] as int,
      participantCount: json['participant_count'] as int,
    );
  }
}

class PostCreateValidationException implements Exception {
  const PostCreateValidationException(this.field, this.message);

  final String field;
  final String message;

  @override
  String toString() => '$field: $message';
}

class PostCreateRequest {
  const PostCreateRequest({
    required this.productName,
    this.productUrl,
    this.imageUploadId,
    required this.totalPrice,
    required this.totalQuantity,
    required this.hostQuantity,
    required this.deadline,
    required this.pickupLocation,
    required this.shortfallPolicy,
  });

  static const keepByHost = 'KEEP_BY_HOST';
  static const cancelIfShort = 'CANCEL_IF_SHORT';

  final String productName;
  final String? productUrl;
  final String? imageUploadId;
  final int totalPrice;
  final int totalQuantity;
  final int hostQuantity;
  final DateTime deadline;
  final String pickupLocation;
  final String shortfallPolicy;

  double get estimatedUnitPrice {
    if (totalQuantity <= 0) {
      return 0;
    }
    return totalPrice / totalQuantity;
  }

  int get estimatedHostAmount {
    if (totalQuantity <= 0) {
      return 0;
    }
    // Keep the estimate consistent with the backend's integer settlement rule.
    return totalPrice * hostQuantity ~/ totalQuantity;
  }

  int get recruitmentQuantity => totalQuantity - hostQuantity;

  int get maximumHostShortfallAmount => totalPrice;

  void validate({DateTime? now}) {
    final trimmedProductName = productName.trim();
    if (trimmedProductName.isEmpty) {
      throw const PostCreateValidationException(
        'product_name',
        '상품명을 입력해주세요.',
      );
    }
    if (trimmedProductName.runes.length > 200) {
      throw const PostCreateValidationException(
        'product_name',
        '상품명은 200자 이하로 입력해주세요.',
      );
    }

    final trimmedProductUrl = productUrl?.trim();
    if (trimmedProductUrl != null && trimmedProductUrl.isNotEmpty) {
      final uri = Uri.tryParse(trimmedProductUrl);
      final isHttpUrl = uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty;
      if (!isHttpUrl) {
        throw const PostCreateValidationException(
          'product_url',
          '상품 링크는 HTTP 또는 HTTPS URL이어야 합니다.',
        );
      }
    }

    if (totalPrice <= 0) {
      throw const PostCreateValidationException(
        'total_price',
        '전체 구매 금액은 양수여야 합니다.',
      );
    }
    if (totalQuantity <= 0) {
      throw const PostCreateValidationException(
        'total_quantity',
        '전체 상품 수량은 양수여야 합니다.',
      );
    }
    if (hostQuantity < 1 || hostQuantity > totalQuantity) {
      throw const PostCreateValidationException(
        'host_quantity',
        '모집자 구매 수량은 1개 이상 전체 수량 이하여야 합니다.',
      );
    }

    final current = (now ?? DateTime.now()).toUtc();
    if (!deadline.toUtc().isAfter(current)) {
      throw const PostCreateValidationException(
        'deadline',
        '모집 마감 일시는 현재 시각 이후여야 합니다.',
      );
    }

    final trimmedPickupLocation = pickupLocation.trim();
    if (trimmedPickupLocation.isEmpty) {
      throw const PostCreateValidationException(
        'pickup_location',
        '픽업 장소를 입력해주세요.',
      );
    }
    if (trimmedPickupLocation.runes.length > 200) {
      throw const PostCreateValidationException(
        'pickup_location',
        '픽업 장소는 200자 이하로 입력해주세요.',
      );
    }

    if (shortfallPolicy != keepByHost && shortfallPolicy != cancelIfShort) {
      throw const PostCreateValidationException(
        'shortfall_policy',
        '올바른 모집 미달 처리 방식을 선택해주세요.',
      );
    }
  }

  Map<String, dynamic> toJson() {
    validate();
    return {
      'product_name': productName.trim(),
      'product_url': _nullableTrim(productUrl),
      'image_upload_id': _nullableTrim(imageUploadId),
      'total_price': totalPrice,
      'total_quantity': totalQuantity,
      'host_quantity': hostQuantity,
      'deadline': deadline.toUtc().toIso8601String(),
      'pickup_location': pickupLocation.trim(),
      'shortfall_policy': shortfallPolicy,
    };
  }

  String? _nullableTrim(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

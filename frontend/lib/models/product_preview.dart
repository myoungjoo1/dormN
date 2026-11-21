class ProductPreview {
  const ProductPreview({
    required this.productUrl,
    required this.productNameSuggestion,
    required this.imageUrl,
  });

  final String productUrl;
  final String? productNameSuggestion;
  final String? imageUrl;

  factory ProductPreview.fromJson(Map<String, dynamic> json) {
    return ProductPreview(
      productUrl: json['product_url'] as String,
      productNameSuggestion: json['product_name_suggestion'] as String?,
      imageUrl: json['image_url'] as String?,
    );
  }
}

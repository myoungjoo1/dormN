import 'package:image_picker/image_picker.dart';

const maxPostImageBytes = 5 * 1024 * 1024;
const supportedPostImageExtensions = {'jpg', 'jpeg', 'png', 'webp'};

class ImageValidationException implements Exception {
  const ImageValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<void> validatePostImage(XFile file) async {
  final extension = file.name.toLowerCase().split('.').last;
  if (!supportedPostImageExtensions.contains(extension)) {
    throw const ImageValidationException(
      'JPEG, PNG, WEBP 이미지만 선택할 수 있습니다.',
    );
  }

  if (await file.length() > maxPostImageBytes) {
    throw const ImageValidationException(
      '이미지는 5MB 이하만 선택할 수 있습니다.',
    );
  }
}

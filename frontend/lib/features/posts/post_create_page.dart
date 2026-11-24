import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/dormn_api.dart';
import '../../core/image/image_validator.dart';
import '../../models/post_create_request.dart';
import '../../models/product_preview.dart';

const _blue = Color(0xFF3156D9);
const _pageBackground = Color(0xFFF7F8FC);

typedef ProductPreviewLoader = Future<ProductPreview> Function(
  String productUrl,
);
typedef PostImageUploader = Future<String> Function(
  String filePath,
  String accessToken,
);
typedef PostCreator = Future<Map<String, dynamic>> Function(
  PostCreateRequest request,
  String accessToken,
);
typedef AccessTokenProvider = String? Function();

class PostCreatePage extends StatefulWidget {
  const PostCreatePage({
    super.key,
    this.previewLoader,
    this.imageUploader,
    this.postCreator,
    this.accessTokenProvider,
    this.initialSelectedImage,
    this.initialDeadline,
  });

  final ProductPreviewLoader? previewLoader;
  final PostImageUploader? imageUploader;
  final PostCreator? postCreator;
  final AccessTokenProvider? accessTokenProvider;
  final XFile? initialSelectedImage;
  final DateTime? initialDeadline;

  @override
  State<PostCreatePage> createState() => _PostCreatePageState();
}

class _PostCreatePageState extends State<PostCreatePage> {
  final _api = const DormNApi();
  final _picker = ImagePicker();
  final _productUrlController = TextEditingController();
  final _productNameController = TextEditingController();
  final _totalPriceController = TextEditingController();
  final _totalQuantityController = TextEditingController();
  final _hostQuantityController = TextEditingController();
  final _pickupLocationController = TextEditingController();

  int _step = 0;
  bool _showReview = false;
  String _shortfallPolicy = PostCreateRequest.keepByHost;
  DateTime? _deadline;
  XFile? _selectedImage;
  String? _imageUploadId;
  String? _previewImageUrl;
  String? _previewUrl;
  bool _isPreviewLoading = false;
  bool _isSubmitting = false;
  Map<String, String> _errors = {};

  @override
  void initState() {
    super.initState();
    _selectedImage = widget.initialSelectedImage;
    _deadline = widget.initialDeadline;
  }

  @override
  void dispose() {
    _productUrlController.dispose();
    _productNameController.dispose();
    _totalPriceController.dispose();
    _totalQuantityController.dispose();
    _hostQuantityController.dispose();
    _pickupLocationController.dispose();
    super.dispose();
  }

  PostCreateRequest _draftRequest() {
    final now = DateTime.now();
    final usesStepTwoValues = _step >= 1 || _showReview;
    final usesStepThreeValues = _step >= 2 || _showReview;
    return PostCreateRequest(
      productName: _productNameController.text,
      productUrl: _productUrlController.text,
      imageUploadId: _imageUploadId,
      totalPrice: usesStepTwoValues
          ? int.tryParse(_totalPriceController.text.trim()) ?? 0
          : 1,
      totalQuantity: usesStepTwoValues
          ? int.tryParse(_totalQuantityController.text.trim()) ?? 0
          : 1,
      hostQuantity: usesStepTwoValues
          ? int.tryParse(_hostQuantityController.text.trim()) ?? 0
          : 1,
      deadline:
          _deadline ??
          (usesStepThreeValues
              ? now.subtract(const Duration(seconds: 1))
              : now.add(const Duration(minutes: 1))),
      pickupLocation: usesStepThreeValues
          ? _pickupLocationController.text
          : '픽업 장소',
      shortfallPolicy: _shortfallPolicy,
    );
  }

  bool _validateCurrentStep() {
    try {
      _draftRequest().validate();
      setState(() => _errors = {});
      return true;
    } on PostCreateValidationException catch (error) {
      setState(() => _errors = {error.field: error.message});
      return false;
    }
  }

  void _nextStep() {
    FocusScope.of(context).unfocus();
    if (!_validateCurrentStep()) return;

    setState(() {
      if (_step < 2) {
        _step += 1;
      } else {
        _showReview = true;
      }
    });
  }

  void _goBack() {
    FocusScope.of(context).unfocus();
    if (_showReview) {
      setState(() => _showReview = false);
      return;
    }
    if (_step > 0) {
      setState(() => _step -= 1);
      return;
    }
    Navigator.of(context).pop();
  }

  void _clearError(String field) {
    if (!_errors.containsKey(field)) return;
    setState(() {
      final errors = Map<String, String>.from(_errors);
      errors.remove(field);
      _errors = errors;
    });
  }

  void _onProductUrlChanged(String value) {
    final normalizedUrl = value.trim();
    setState(() {
      _errors.remove('product_url');
      if (_previewUrl != normalizedUrl) {
        _previewUrl = null;
        _previewImageUrl = null;
      }
    });
  }

  Future<void> _loadProductPreview() async {
    final productUrl = _productUrlController.text.trim();
    final uri = Uri.tryParse(productUrl);
    final isHttpUrl =
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    if (!isHttpUrl) {
      setState(() {
        _errors = {
          ..._errors,
          'product_url': '상품 링크는 HTTP 또는 HTTPS URL이어야 합니다.',
        };
      });
      return;
    }

    setState(() {
      _isPreviewLoading = true;
      _errors.remove('product_url');
    });

    try {
      final loader = widget.previewLoader ?? _api.previewProduct;
      final preview = await loader(productUrl);
      if (!mounted) return;

      setState(() {
        _previewUrl = productUrl;
        _previewImageUrl = preview.imageUrl;
        final suggestion = preview.productNameSuggestion?.trim();
        if (suggestion != null && suggestion.isNotEmpty) {
          _productNameController.text = suggestion;
        }
      });

      final hasName = preview.productNameSuggestion?.trim().isNotEmpty == true;
      final hasImage = preview.imageUrl?.trim().isNotEmpty == true;
      if (!hasName && !hasImage) {
        _showMessage('상품명과 이미지를 불러오지 못했습니다. 직접 입력해주세요.');
      } else if (!hasName) {
        _showMessage('이미지는 불러왔지만 상품명은 직접 입력해주세요.');
      } else if (!hasImage) {
        _showMessage('상품명은 불러왔지만 이미지는 직접 선택할 수 있습니다.');
      }
    } on ApiException {
      if (!mounted) return;
      setState(() {
        _errors = {..._errors, 'product_url': '상품 정보를 불러오지 못했습니다. 링크를 확인해주세요.'};
      });
      _showMessage('상품 정보를 불러오지 못했습니다. 링크를 확인해주세요.');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errors = {..._errors, 'product_url': '상품 정보를 불러오지 못했습니다. 직접 입력해주세요.'};
      });
    } finally {
      if (mounted) setState(() => _isPreviewLoading = false);
    }
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    try {
      await validatePostImage(picked);
      if (!mounted) return;
      setState(() {
        _selectedImage = picked;
        _imageUploadId = null;
      });
    } on ImageValidationException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var initialDate = _deadline ?? now.add(const Duration(hours: 1));
    if (initialDate.isBefore(today)) initialDate = today;

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context)
            .copyWith(colorScheme: const ColorScheme.light(primary: _blue)),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final initialTime = _deadline == null
        ? TimeOfDay.fromDateTime(now.add(const Duration(hours: 1)))
        : TimeOfDay.fromDateTime(_deadline!);
    final time = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (time == null || !mounted) return;

    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!selected.isAfter(DateTime.now())) {
      setState(() {
        _errors = {..._errors, 'deadline': '모집 마감 일시는 현재 시각 이후여야 합니다.'};
      });
      return;
    }

    setState(() {
      _deadline = selected;
      _errors.remove('deadline');
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ignore: unused_element
  void _showMetadataNotReady() {
    _showMessage('상품 정보 불러오기는 다음 단계에서 연결됩니다.');
  }

  // ignore: unused_element
  void _registerLater() {
    _showMessage('공동구매 등록 API는 다음 단계에서 연결됩니다.');
  }

  String? _getAccessToken() {
    if (widget.accessTokenProvider != null) {
      return widget.accessTokenProvider!();
    }
    try {
      return Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {
      return null;
    }
  }

  Future<void> _submitPost() async {
    if (_isSubmitting) return;

    FocusScope.of(context).unfocus();
    try {
      _draftRequest().validate();
      setState(() => _errors = {});

      final accessToken = _getAccessToken();
      if (accessToken == null || accessToken.isEmpty) {
        _showMessage('로그인이 필요합니다. 다시 로그인해주세요.');
        return;
      }

      setState(() => _isSubmitting = true);

      if (_selectedImage != null && _imageUploadId == null) {
        final uploader =
            widget.imageUploader ??
            (filePath, token) =>
                _api.uploadPostImage(filePath: filePath, accessToken: token);
        final uploadId = await uploader(_selectedImage!.path, accessToken);
        if (!mounted) return;
        setState(() => _imageUploadId = uploadId);
      }

      final creator =
          widget.postCreator ??
          (post, token) => _api.createPost(request: post, accessToken: token);
      final createdPost = await creator(_draftRequest(), accessToken);
      if (!mounted) return;

      Navigator.of(context).pop(createdPost);
    } on PostCreateValidationException catch (error) {
      if (mounted) setState(() => _errors = {error.field: error.message});
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'IMAGE_UPLOAD_EXPIRED') {
        setState(() => _imageUploadId = null);
        _showMessage('사진 업로드가 만료되었습니다. 다시 등록해주세요.');
      } else if (error.code == 'DORM_VERIFICATION_REQUIRED') {
        _showMessage('기숙사 인증을 완료한 사용자만 공동구매를 등록할 수 있어요.');
      } else {
        _showMessage('공동구매 등록에 실패했습니다. 잠시 후 다시 시도해주세요.');
      }
    } catch (_) {
      if (mounted) {
        _showMessage('공동구매 등록에 실패했습니다. 잠시 후 다시 시도해주세요.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _showReview ? '등록 확인' : '공동구매 글 작성';
    return Scaffold(
      backgroundColor: _pageBackground,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: _pageBackground,
        elevation: 0,
        leading: IconButton(
          onPressed: _goBack,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StepIndicator(activeStep: _showReview ? 3 : _step + 1),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                child: _showReview ? _buildReview() : _buildStep(),
              ),
            ),
            _BottomAction(
              label: _showReview
                  ? '공동구매 등록'
                  : _step == 2
                  ? '최종 확인'
                  : '다음',
              onPressed: _isSubmitting
                  ? null
                  : (_showReview
                        ? () {
                            _submitPost();
                          }
                        : _nextStep),
              isLoading: _isSubmitting,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _buildProductStep();
      case 1:
        return _buildConditionStep();
      default:
        return _buildRecruitmentStep();
    }
  }

  Widget _buildProductStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageHeading(
          title: '상품 정보를 입력해주세요',
          subtitle: '상품 링크와 사진을 등록하면 참여자가 더 쉽게 확인할 수 있어요.',
        ),
        const SizedBox(height: 22),
        _InputField(
          fieldKey: const ValueKey('product-url'),
          controller: _productUrlController,
          label: '상품 링크 (선택)',
          hintText: 'https://example.com/product',
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          errorText: _errors['product_url'],
          onChanged: _onProductUrlChanged,
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const ValueKey('preview-button'),
            onPressed: _isPreviewLoading ? null : _loadProductPreview,
            icon: _isPreviewLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_outlined, size: 18),
            label: const Text('상품 정보 불러오기'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _blue,
              side: const BorderSide(color: Color(0xFFCBD5FF)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _buildImagePicker(),
        const SizedBox(height: 18),
        _InputField(
          fieldKey: const ValueKey('product-name'),
          controller: _productNameController,
          label: '상품명',
          hintText: '예: 햇반 24개 한 박스',
          textInputAction: TextInputAction.done,
          errorText: _errors['product_name'],
          onChanged: (_) => _clearError('product_name'),
        ),
      ],
    );
  }

  Widget _buildImagePicker() {
    final image = _selectedImage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '상품 사진 (선택)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (image == null && _previewImageUrl == null)
          InkWell(
            onTap: _pickImage,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: double.infinity,
              height: 150,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFDDE2F0)),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    color: _blue,
                    size: 32,
                  ),
                  SizedBox(height: 8),
                  Text(
                    '사진 선택',
                    style: TextStyle(color: _blue, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'JPEG, PNG, WebP · 최대 5MB',
                    style: TextStyle(color: Color(0xFF7B8398), fontSize: 11),
                  ),
                ],
              ),
            ),
          )
        else if (image != null)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFDDE2F0)),
            ),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(image.path),
                    width: double.infinity,
                    height: 170,
                    fit: BoxFit.cover,
                  ),
                ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.refresh_rounded, size: 17),
                      label: const Text('변경'),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _selectedImage = null;
                        _imageUploadId = null;
                      }),
                      icon: const Icon(Icons.delete_outline_rounded, size: 17),
                      label: const Text('삭제'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFB34B55),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          )
        else
          _buildAutoPreview(),
      ],
    );
  }

  Widget _buildAutoPreview() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE2F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              _previewImageUrl!,
              width: double.infinity,
              height: 170,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const SizedBox(
                height: 170,
                child: Center(child: Text('이미지를 표시할 수 없습니다.')),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8, left: 2),
            child: Text(
              '상품 URL에서 불러온 이미지 · 직접 사진을 선택하면 직접 선택한 사진이 우선됩니다.',
              style: TextStyle(color: Color(0xFF697386), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConditionStep() {
    final draft = _draftRequest();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageHeading(
          title: '구매 조건을 정해주세요',
          subtitle: '전체 금액과 수량을 기준으로 예상 부담 금액을 계산해요.',
        ),
        const SizedBox(height: 22),
        _InputField(
          fieldKey: const ValueKey('total-price'),
          controller: _totalPriceController,
          label: '전체 구매 금액 (배송비 포함)',
          hintText: '예: 22900',
          suffixText: '원',
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          errorText: _errors['total_price'],
          onChanged: (_) => setState(() => _errors.remove('total_price')),
        ),
        const SizedBox(height: 14),
        _InputField(
          fieldKey: const ValueKey('total-quantity'),
          controller: _totalQuantityController,
          label: '전체 상품 수량',
          hintText: '예: 24',
          suffixText: '개',
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          errorText: _errors['total_quantity'],
          onChanged: (_) => setState(() => _errors.remove('total_quantity')),
        ),
        const SizedBox(height: 14),
        _InputField(
          fieldKey: const ValueKey('host-quantity'),
          controller: _hostQuantityController,
          label: '모집자 본인 구매 수량',
          hintText: '예: 4',
          suffixText: '개',
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          errorText: _errors['host_quantity'],
          onChanged: (_) => setState(() => _errors.remove('host_quantity')),
        ),
        const SizedBox(height: 20),
        _EstimateCard(request: draft),
      ],
    );
  }

  Widget _buildRecruitmentStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageHeading(
          title: '모집 조건을 정해주세요',
          subtitle: '언제까지, 어디에서 받을지 참여자에게 알려주세요.',
        ),
        const SizedBox(height: 22),
        const Text(
          '모집 마감 일시',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const ValueKey('deadline-button'),
            onPressed: _pickDeadline,
            icon: const Icon(Icons.event_outlined, size: 19),
            label: Text(
              _deadline == null
                  ? '날짜와 시간을 선택해주세요'
                  : _formatDeadline(_deadline!),
            ),
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              foregroundColor: _deadline == null
                  ? const Color(0xFF7B8398)
                  : _blue,
              backgroundColor: Colors.white,
              side: BorderSide(
                color: _errors['deadline'] == null
                    ? const Color(0xFFDDE2F0)
                    : Colors.redAccent,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
            ),
          ),
        ),
        if (_errors['deadline'] != null) _ErrorText(_errors['deadline']!),
        const SizedBox(height: 18),
        _InputField(
          fieldKey: const ValueKey('pickup-location'),
          controller: _pickupLocationController,
          label: '픽업 장소',
          hintText: '예: 기숙사 1층 로비',
          textInputAction: TextInputAction.done,
          errorText: _errors['pickup_location'],
          onChanged: (_) => _clearError('pickup_location'),
        ),
        const SizedBox(height: 20),
        const Text(
          '모집 미달 처리 방식',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        RadioGroup<String>(
          groupValue: _shortfallPolicy,
          onChanged: (value) {
            if (value != null) setState(() => _shortfallPolicy = value);
          },
          child: Column(
            children: [
              _PolicyOption(
                value: PostCreateRequest.keepByHost,
                selected: _shortfallPolicy == PostCreateRequest.keepByHost,
                title: '남은 수량을 제가 부담할게요',
                subtitle: '목표 수량이 모이지 않아도 거래를 진행합니다.',
                onTap: () => setState(
                  () => _shortfallPolicy = PostCreateRequest.keepByHost,
                ),
              ),
              const SizedBox(height: 8),
              _PolicyOption(
                value: PostCreateRequest.cancelIfShort,
                selected: _shortfallPolicy == PostCreateRequest.cancelIfShort,
                title: '목표 수량이 모이지 않으면 취소할게요',
                subtitle: '전체 수량을 채우지 못하면 거래를 취소합니다.',
                onTap: () => setState(
                  () => _shortfallPolicy = PostCreateRequest.cancelIfShort,
                ),
              ),
            ],
          ),
        ),
        if (_shortfallPolicy == PostCreateRequest.keepByHost) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFFE9EEFF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: _blue, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '모집이 부족하면 남은 상품을 모집자가 부담합니다. 최대 부담 가능 금액은 전체 구매 금액입니다.',
                    style: TextStyle(color: _blue, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildReview() {
    final request = _draftRequest();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageHeading(
          title: '등록 내용을 확인해주세요',
          subtitle: '내용을 확인한 뒤 등록 버튼을 눌러주세요.',
        ),
        const SizedBox(height: 18),
        _ReviewImage(image: _selectedImage),
        const SizedBox(height: 14),
        _ReviewCard(
          children: [
            _ReviewRow(label: '상품명', value: _productNameController.text.trim()),
            _ReviewRow(label: '전체 구매 가격', value: '${request.totalPrice}원'),
            _ReviewRow(
              label: '예상 개당 가격',
              value: '${request.estimatedUnitPrice.round()}원',
            ),
            _ReviewRow(label: '본인 구매 수량', value: '${request.hostQuantity}개'),
            _ReviewRow(
              label: '모집 수량',
              value: '${request.recruitmentQuantity}개',
            ),
            _ReviewRow(
              label: '모집 마감',
              value: _formatDeadline(request.deadline),
            ),
            _ReviewRow(
              label: '픽업 장소',
              value: _pickupLocationController.text.trim(),
            ),
            _ReviewRow(
              label: '미달 처리',
              value: request.shortfallPolicy == PostCreateRequest.keepByHost
                  ? '남은 수량 모집자 부담'
                  : '목표 미달 시 취소',
            ),
          ],
        ),
      ],
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.activeStep});

  final int activeStep;

  @override
  Widget build(BuildContext context) {
    const labels = ['상품 정보', '구매 조건', '모집 조건'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            Expanded(
              child: Column(
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: activeStep >= index + 1
                          ? _blue
                          : const Color(0xFFE0E4EF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    labels[index],
                    style: TextStyle(
                      color: activeStep >= index + 1
                          ? _blue
                          : const Color(0xFF8A92A5),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (index != labels.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 7),
        Text(
          subtitle,
          style: const TextStyle(color: Color(0xFF697386), fontSize: 12),
        ),
      ],
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    this.fieldKey,
    required this.controller,
    required this.label,
    required this.hintText,
    this.suffixText,
    this.keyboardType,
    this.textInputAction,
    this.errorText,
    this.onChanged,
  });

  final Key? fieldKey;
  final TextEditingController controller;
  final String label;
  final String hintText;
  final String? suffixText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        suffixText: suffixText,
        errorText: errorText,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDDE2F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDDE2F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _blue, width: 1.5),
        ),
      ),
    );
  }
}

class _EstimateCard extends StatelessWidget {
  const _EstimateCard({required this.request});

  final PostCreateRequest request;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE9EEFF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '예상 금액',
              style: TextStyle(color: _blue, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 12),
          _EstimateRow(
            label: '예상 개당 가격',
            value: '${request.estimatedUnitPrice.round()}원',
          ),
          _EstimateRow(
            label: '모집자 예상 부담 금액',
            value: '${request.estimatedHostAmount}원',
          ),
          _EstimateRow(
            label: '모집할 수량',
            value: '${request.recruitmentQuantity}개',
          ),
        ],
      ),
    );
  }
}

class _EstimateRow extends StatelessWidget {
  const _EstimateRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF697386), fontSize: 12),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(color: _blue, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _PolicyOption extends StatelessWidget {
  const _PolicyOption({
    required this.value,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String value;
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected ? _blue : const Color(0xFFDDE2F0),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Radio<String>(value: value, activeColor: _blue),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF697386),
                      fontSize: 11,
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
}

class _ReviewImage extends StatelessWidget {
  const _ReviewImage({required this.image});

  final XFile? image;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: image == null
          ? Container(
              width: double.infinity,
              height: 120,
              color: const Color(0xFFE9EEFF),
              child: const Icon(
                Icons.shopping_bag_outlined,
                color: _blue,
                size: 42,
              ),
            )
          : Image.file(
              File(image!.path),
              width: double.infinity,
              height: 180,
              fit: BoxFit.cover,
            ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: children),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF697386), fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 6),
      child: Text(
        message,
        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
      ),
    );
  }
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 12 + bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 10,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: _blue,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
        ),
      ),
    );
  }
}

String _formatDeadline(DateTime value) {
  final local = value.toLocal();
  final weekday = ['월', '화', '수', '목', '금', '토', '일'][local.weekday - 1];
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}.${local.month}.${local.day} ($weekday) $hour:$minute';
}

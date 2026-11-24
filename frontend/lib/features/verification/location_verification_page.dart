import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/dormn_api.dart';
import '../../models/location_verification.dart';

const _blue = Color(0xFF3156D9);
const _pageBackground = Color(0xFFF7F8FC);
const _maxPositionAge = Duration(minutes: 2);

class LocationMeasurement {
  const LocationMeasurement({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime timestamp;
}

class LocationVerificationPage extends StatefulWidget {
  const LocationVerificationPage({super.key});

  @override
  State<LocationVerificationPage> createState() =>
      _LocationVerificationPageState();
}

class _LocationVerificationPageState extends State<LocationVerificationPage>
    with WidgetsBindingObserver {
  final _api = const DormNApi();
  bool _isStatusLoading = true;
  bool _isVerificationLoading = true;
  bool _isMeasuring = false;
  bool? _serviceEnabled;
  LocationPermission _permission = LocationPermission.denied;
  LocationAccuracyStatus? _accuracyStatus;
  LocationMeasurement? _measurement;
  LocationVerificationStatus? _verificationStatus;
  String? _error;
  String? _verificationError;
  bool _isFinalVerificationLoading = false;
  bool? _dormVerified;
  String? _finalVerificationError;
  int _verificationRequestVersion = 0;
  String? _activeUserId;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenToAuthState();
    unawaited(_refreshLocationStatus());
    unawaited(_loadVerificationStatus());
  }

  void _listenToAuthState() {
    try {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((state) {
            if (!mounted) return;
            final session = state.session;
            if (session == null) {
              _verificationRequestVersion += 1;
              _activeUserId = null;
              setState(() {
                _verificationStatus = null;
                _dormVerified = null;
                _measurement = null;
                _verificationError = '로그인이 필요합니다. 다시 로그인해 주세요.';
                _finalVerificationError = null;
                _isVerificationLoading = false;
                _isFinalVerificationLoading = false;
              });
              return;
            }
            if (_activeUserId != null && _activeUserId != session.user.id) {
              _verificationRequestVersion += 1;
              _activeUserId = session.user.id;
              setState(() {
                _verificationStatus = null;
                _dormVerified = null;
                _measurement = null;
                _verificationError = null;
                _finalVerificationError = null;
              });
              unawaited(_loadVerificationStatus());
            }
          });
    } catch (_) {
      // AuthGate remains the source of truth when the auth stream is unavailable.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isMeasuring) {
      unawaited(_refreshLocationStatus());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    super.dispose();
  }

  bool _hasPermission(LocationPermission permission) {
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  Future<void> _refreshLocationStatus() async {
    if (!mounted) return;
    setState(() => _isStatusLoading = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      final permission = await Geolocator.checkPermission();
      LocationAccuracyStatus? accuracyStatus;
      if (_hasPermission(permission)) {
        accuracyStatus = await Geolocator.getLocationAccuracy();
      }

      if (!mounted) return;
      setState(() {
        _serviceEnabled = serviceEnabled;
        _permission = permission;
        _accuracyStatus = accuracyStatus;
        _isStatusLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isStatusLoading = false;
        _error = '위치 상태를 확인하지 못했습니다. 다시 시도해 주세요.';
      });
    }
  }

  Session? _currentSession() {
    try {
      return Supabase.instance.client.auth.currentSession;
    } catch (_) {
      return null;
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([_refreshLocationStatus(), _loadVerificationStatus()]);
  }

  Future<void> _loadVerificationStatus() async {
    final requestVersion = ++_verificationRequestVersion;
    final session = _currentSession();
    final userId = session?.user.id;
    _activeUserId = userId;

    if (!mounted) return;
    setState(() {
      _isVerificationLoading = true;
      _verificationError = null;
      _verificationStatus = null;
      _isFinalVerificationLoading = false;
      _dormVerified = null;
      _finalVerificationError = null;
    });

    if (session == null || session.accessToken.isEmpty) {
      if (!mounted || requestVersion != _verificationRequestVersion) return;
      setState(() {
        _isVerificationLoading = false;
        _verificationError = '로그인이 필요합니다. 다시 로그인해 주세요.';
      });
      return;
    }

    try {
      final status = await _api.getLocationVerificationStatus(
        accessToken: session.accessToken,
      );
      if (!mounted ||
          requestVersion != _verificationRequestVersion ||
          _currentSession()?.user.id != userId) {
        return;
      }
      setState(() {
        _verificationStatus = status;
        _isVerificationLoading = false;
      });
      if (status.isCompleted) {
        unawaited(
          _completeFinalVerification(
            accessToken: session.accessToken,
            userId: userId!,
            requestVersion: requestVersion,
          ),
        );
      }
    } on ApiException catch (error) {
      if (!mounted || requestVersion != _verificationRequestVersion) return;
      setState(() {
        _isVerificationLoading = false;
        _verificationError = _serverErrorMessage(error);
      });
    } catch (_) {
      if (!mounted || requestVersion != _verificationRequestVersion) return;
      setState(() {
        _isVerificationLoading = false;
        _verificationError = 'GPS 인증 상태를 불러오지 못했습니다. 다시 시도해 주세요.';
      });
    }
  }

  Future<void> _completeFinalVerification({
    required String accessToken,
    required String userId,
    required int requestVersion,
  }) async {
    if (!mounted || requestVersion != _verificationRequestVersion) return;
    setState(() {
      _isFinalVerificationLoading = true;
      _finalVerificationError = null;
    });

    try {
      await _api.completeDormVerification(accessToken);
      final profile = await _api.getMyProfile(
        accessToken,
        timeout: const Duration(seconds: 15),
      );
      if (!mounted ||
          requestVersion != _verificationRequestVersion ||
          _currentSession()?.user.id != userId) {
        return;
      }
      setState(() {
        _isFinalVerificationLoading = false;
        _dormVerified = profile.dormVerified;
        _finalVerificationError = profile.dormVerified
            ? null
            : '최종 기숙사 인증 상태를 확인하지 못했습니다.';
      });
    } on ApiException catch (error) {
      if (!mounted || requestVersion != _verificationRequestVersion) return;
      setState(() {
        _isFinalVerificationLoading = false;
        _finalVerificationError = _finalVerificationErrorMessage(error);
      });
    } on TimeoutException {
      if (!mounted || requestVersion != _verificationRequestVersion) return;
      setState(() {
        _isFinalVerificationLoading = false;
        _finalVerificationError = '최종 인증 결과를 확인하지 못했습니다. 인증 완료로 표시하지 않았습니다.';
      });
    } catch (_) {
      if (!mounted || requestVersion != _verificationRequestVersion) return;
      setState(() {
        _isFinalVerificationLoading = false;
        _finalVerificationError = '최종 기숙사 인증 결과를 확인하지 못했습니다. 다시 시도해 주세요.';
      });
    }
  }

  Future<void> _retryFinalVerification() async {
    final session = _currentSession();
    final status = _verificationStatus;
    if (session == null || status == null || !status.isCompleted) return;

    final requestVersion = ++_verificationRequestVersion;
    await _completeFinalVerification(
      accessToken: session.accessToken,
      userId: session.user.id,
      requestVersion: requestVersion,
    );
  }

  Future<void> _measureLocation() async {
    if (_isMeasuring || _verificationStatus?.isCompleted == true) return;

    setState(() {
      _isMeasuring = true;
      _error = null;
      _measurement = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _updateLocationState(serviceEnabled: false);
        _showError('기기의 위치 서비스를 켜고 다시 시도해 주세요.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        _updateLocationState(serviceEnabled: true, permission: permission);
        _showError('위치 권한이 영구적으로 거부되었습니다. 앱 설정에서 허용해 주세요.');
        return;
      }
      if (!_hasPermission(permission)) {
        _updateLocationState(serviceEnabled: true, permission: permission);
        _showError('현재 위치를 확인하려면 위치 권한이 필요합니다.');
        return;
      }

      final accuracyStatus = await Geolocator.getLocationAccuracy();
      _updateLocationState(
        serviceEnabled: true,
        permission: permission,
        accuracyStatus: accuracyStatus,
      );
      if (accuracyStatus == LocationAccuracyStatus.reduced) {
        _showError('대략적인 위치 권한입니다. 앱 설정에서 정확한 위치를 허용해 주세요.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final timestamp = position.timestamp;
      final age = DateTime.now().difference(timestamp).abs();
      if (age > _maxPositionAge) {
        _showError('측정된 위치가 오래되었습니다. 잠시 후 다시 시도해 주세요.');
        return;
      }

      final measurement = LocationMeasurement(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        timestamp: timestamp,
      );
      if (!mounted) return;
      setState(() {
        _measurement = measurement;
        _error = null;
      });
      await _submitLocationMeasurement(measurement);
    } on TimeoutException {
      _showError('현재 위치를 확인하는 데 시간이 걸리고 있습니다. 다시 시도해 주세요.');
    } on LocationServiceDisabledException {
      _updateLocationState(serviceEnabled: false);
      _showError('기기의 위치 서비스를 켜고 다시 시도해 주세요.');
    } catch (_) {
      _showError('현재 위치를 확인하지 못했습니다. 위치 상태를 확인한 뒤 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _isMeasuring = false);
    }
  }

  Future<void> _submitLocationMeasurement(
    LocationMeasurement measurement,
  ) async {
    final session = _currentSession();
    final userId = session?.user.id;
    if (session == null || session.accessToken.isEmpty) {
      _showError('로그인이 필요합니다. 다시 로그인해 주세요.');
      return;
    }

    final requestVersion = ++_verificationRequestVersion;
    if (mounted) {
      setState(() => _verificationError = null);
    }

    try {
      await _api.submitLocationCheck(
        latitude: measurement.latitude,
        longitude: measurement.longitude,
        accuracyMeters: measurement.accuracyMeters,
        accessToken: session.accessToken,
      );
      final status = await _api.getLocationVerificationStatus(
        accessToken: session.accessToken,
      );
      if (!mounted ||
          requestVersion != _verificationRequestVersion ||
          _currentSession()?.user.id != userId) {
        return;
      }
      setState(() {
        _verificationStatus = status;
        _verificationError = null;
      });
      if (status.isCompleted) {
        unawaited(
          _completeFinalVerification(
            accessToken: session.accessToken,
            userId: userId!,
            requestVersion: requestVersion,
          ),
        );
      }
    } on ApiException catch (error) {
      if (!mounted || requestVersion != _verificationRequestVersion) return;
      setState(() => _verificationError = _serverErrorMessage(error));
      if (error.code == 'LOCATION_CHECK_TOO_SOON') {
        unawaited(_loadVerificationStatus());
      }
    } on TimeoutException {
      if (mounted && requestVersion == _verificationRequestVersion) {
        setState(() {
          _verificationError = '서버 응답 시간이 초과되었습니다. 인증 완료로 처리하지 않았습니다.';
        });
      }
    } catch (_) {
      if (mounted && requestVersion == _verificationRequestVersion) {
        setState(() {
          _verificationError = 'GPS 인증 서버에 연결하지 못했습니다. 다시 시도해 주세요.';
        });
      }
    }
  }

  void _updateLocationState({
    required bool serviceEnabled,
    LocationPermission? permission,
    LocationAccuracyStatus? accuracyStatus,
  }) {
    if (!mounted) return;
    setState(() {
      _serviceEnabled = serviceEnabled;
      if (permission != null) _permission = permission;
      if (accuracyStatus != null) _accuracyStatus = accuracyStatus;
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _measurement = null;
    });
  }

  Future<void> _openAppSettings() async {
    final opened = await Geolocator.openAppSettings();
    if (!opened && mounted) {
      _showError('앱 설정을 열지 못했습니다. 기기 설정에서 위치 권한을 확인해 주세요.');
    }
  }

  Future<void> _openLocationSettings() async {
    final opened = await Geolocator.openLocationSettings();
    if (!opened && mounted) {
      _showError('위치 설정을 열지 못했습니다. 기기 설정에서 위치 서비스를 켜 주세요.');
    }
  }

  String _permissionLabel() {
    switch (_permission) {
      case LocationPermission.denied:
        return '아직 허용되지 않음';
      case LocationPermission.deniedForever:
        return '영구 거부됨';
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        return _accuracyStatus == LocationAccuracyStatus.reduced
            ? '대략적인 위치 허용'
            : '정확한 위치 허용';
      case LocationPermission.unableToDetermine:
        return '확인할 수 없음';
    }
  }

  String _serverErrorMessage(ApiException error) {
    switch (error.code) {
      case 'AUTH_REQUIRED':
      case 'INVALID_ACCESS_TOKEN':
        return '로그인이 필요합니다. 다시 로그인해 주세요.';
      case 'LOCATION_VERIFICATION_CONFIGURATION_ERROR':
        return 'GPS 인증 설정이 아직 준비되지 않았습니다.';
      case 'LOCATION_VERIFICATION_TIME_WINDOW_CLOSED':
        return '현재는 GPS 인증 가능 시간이 아닙니다. 서버 안내 시간을 확인해 주세요.';
      case 'GPS_ACCURACY_TOO_LOW':
        return 'GPS 정확도가 서버 기준보다 낮습니다. 정확한 위치에서 다시 시도해 주세요.';
      case 'LOCATION_CHECK_TOO_SOON':
        return '다음 위치 확인 가능 시각 전입니다. 잠시 후 다시 시도해 주세요.';
      case 'LOCATION_VERIFICATION_UNAVAILABLE':
        return 'GPS 인증 서버를 일시적으로 사용할 수 없습니다. 잠시 후 다시 시도해 주세요.';
      default:
        return error.message;
    }
  }

  String _finalVerificationErrorMessage(ApiException error) {
    switch (error.code) {
      case 'ROOM_NUMBER_REQUIRED':
        return '호실 번호를 먼저 등록해 주세요. GPS 인증만으로 최종 인증할 수 없습니다.';
      case 'GPS_VERIFICATION_REQUIRED':
        return 'GPS 체류 인증을 완료한 뒤 최종 기숙사 인증을 진행해 주세요.';
      case 'DORM_VERIFICATION_UNAVAILABLE':
        return '최종 기숙사 인증 서버를 일시적으로 사용할 수 없습니다. 다시 시도해 주세요.';
      default:
        return _serverErrorMessage(error);
    }
  }

  String _verificationStatusLabel(String status) {
    switch (status) {
      case 'NOT_STARTED':
        return '아직 시작하지 않음';
      case 'IN_PROGRESS':
        return '체류 인증 진행 중';
      case 'OUT_OF_RANGE':
        return '기숙사 지정 범위 밖';
      case 'EXPIRED':
        return '인증 가능 시간이 지남';
      case 'COMPLETED':
        return 'GPS 체류 인증 완료';
      default:
        return 'GPS 인증 상태 확인 필요';
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    if (minutes == 0) return '${remainingSeconds}초';
    if (remainingSeconds == 0) return '${minutes}분';
    return '${minutes}분 ${remainingSeconds}초';
  }

  String _formatKoreaDateTime(DateTime value) {
    final korea = value.toUtc().add(const Duration(hours: 9));
    final month = korea.month.toString().padLeft(2, '0');
    final day = korea.day.toString().padLeft(2, '0');
    final hour = korea.hour.toString().padLeft(2, '0');
    final minute = korea.minute.toString().padLeft(2, '0');
    return '${korea.year}.$month.$day $hour:$minute KST';
  }

  String _verificationWindowMessage() {
    final status = _verificationStatus;
    if (status == null) {
      return '서버에서 GPS 인증 가능 시간을 확인합니다. 현재 위치는 버튼을 누른 순간에만 측정합니다.';
    }
    return '인증 가능 시간은 ${status.eligibleTimeStart}~${status.eligibleTimeEnd} '
        '(${status.eligibleTimeZone})입니다. 현재 위치는 버튼을 누른 순간에만 측정합니다.';
  }

  Widget _buildVerificationStatusCard() {
    if (_isVerificationLoading) {
      return const _Card(
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('GPS 인증 상태 확인 중...'),
          ],
        ),
      );
    }

    final status = _verificationStatus;
    if (status == null) return const SizedBox.shrink();

    final statusColor = status.isCompleted
        ? const Color(0xFF1D9B55)
        : status.status == 'OUT_OF_RANGE' || status.status == 'EXPIRED'
        ? const Color(0xFFD14343)
        : _blue;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                status.isCompleted
                    ? Icons.verified_rounded
                    : Icons.timelapse_rounded,
                color: statusColor,
                size: 23,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _verificationStatusLabel(status.status),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '유효 위치 확인 ${status.validCheckCount}/${status.requiredCheckCount}회',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            '체류 시간 ${_formatDuration(status.dwellSeconds)} / '
            '${_formatDuration(status.minimumDwellSeconds)}',
            style: const TextStyle(color: Color(0xFF526079), fontSize: 13),
          ),
          const SizedBox(height: 5),
          Text(
            status.intervalSatisfied
                ? '다음 위치 확인 간격을 충족했습니다.'
                : '이전 확인과의 최소 간격을 기다려야 합니다.',
            style: const TextStyle(color: Color(0xFF526079), fontSize: 13),
          ),
          const SizedBox(height: 10),
          Text(
            _verificationWindowMessage(),
            style: const TextStyle(color: Color(0xFF697386), fontSize: 12),
          ),
          if (status.nextCheckAt != null) ...[
            const SizedBox(height: 5),
            Text(
              '다음 확인 가능: ${_formatKoreaDateTime(status.nextCheckAt!)}',
              style: const TextStyle(color: Color(0xFFB57900), fontSize: 12),
            ),
          ],
          if (status.isCompleted) ...[
            const SizedBox(height: 12),
            Text(
              _dormVerified == true
                  ? 'GPS 체류 인증과 호실 조건을 확인하여 최종 기숙사 인증이 완료되었습니다.'
                  : 'GPS 체류 인증이 완료되었습니다. 최종 기숙사 인증을 위해 호실 등록을 진행해 주세요.',
              style: const TextStyle(
                color: Color(0xFF1D9B55),
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
          ] else if (status.additionalCheckRequired) ...[
            const SizedBox(height: 12),
            const Text(
              '추가 위치 확인이 필요합니다. 서버가 반환한 다음 확인 가능 시각을 따라 주세요.',
              style: TextStyle(
                color: Color(0xFF526079),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFinalVerificationCard() {
    if (_verificationStatus?.isCompleted != true) {
      return const SizedBox.shrink();
    }
    if (_isFinalVerificationLoading) {
      return const _Card(
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('최종 기숙사 인증 상태 확인 중...'),
          ],
        ),
      );
    }
    if (_dormVerified == true) {
      return const _Card(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.verified_rounded, color: Color(0xFF1D9B55)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '최종 기숙사 인증이 완료되었습니다. 호실 번호와 GPS 체류 조건을 '
                '서버에서 확인했습니다.',
                style: TextStyle(
                  color: Color(0xFF1D9B55),
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (_finalVerificationError != null) {
      return _ErrorCard(
        message: _finalVerificationError!,
        onRetry: _retryFinalVerification,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _statusRow({
    required IconData icon,
    required String label,
    required String value,
    Color valueColor = const Color(0xFF25324A),
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, color: _blue, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(color: valueColor, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildAction() {
    if (_isStatusLoading || _isVerificationLoading) {
      return const SizedBox(
        width: double.infinity,
        child: OutlinedButton(onPressed: null, child: Text('위치 상태 확인 중...')),
      );
    }

    if (_verificationStatus?.isCompleted == true) {
      return const SizedBox(
        width: double.infinity,
        child: OutlinedButton(onPressed: null, child: Text('GPS 체류 인증 완료')),
      );
    }

    if (_serviceEnabled == false) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _openLocationSettings,
          icon: const Icon(Icons.location_on_outlined),
          label: const Text('위치 서비스 설정 열기'),
          style: FilledButton.styleFrom(backgroundColor: _blue),
        ),
      );
    }

    if (_permission == LocationPermission.deniedForever) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _openAppSettings,
          icon: const Icon(Icons.settings_outlined),
          label: const Text('앱 설정에서 위치 권한 허용'),
          style: FilledButton.styleFrom(backgroundColor: _blue),
        ),
      );
    }

    if (_accuracyStatus == LocationAccuracyStatus.reduced) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _openAppSettings,
          icon: const Icon(Icons.my_location_outlined),
          label: const Text('정확한 위치 설정 열기'),
          style: FilledButton.styleFrom(backgroundColor: _blue),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _isMeasuring ? null : _measureLocation,
        icon: _isMeasuring
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.gps_fixed_rounded),
        label: Text(_isMeasuring ? '현재 위치 확인 중...' : '현재 위치 확인'),
        style: FilledButton.styleFrom(backgroundColor: _blue),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        backgroundColor: _pageBackground,
        elevation: 0,
        title: const Text(
          '기숙사 위치 인증',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            children: [
              _InfoCard(
                icon: Icons.location_searching_rounded,
                title: '수경재 위치 확인',
                message:
                    '한국 시간 00:00~03:00에 기숙사 위치 확인을 진행합니다. '
                    '현재 위치는 버튼을 누른 순간에만 한 번 측정합니다.',
              ),
              const SizedBox(height: 14),
              _Card(
                child: Column(
                  children: [
                    _statusRow(
                      icon: Icons.location_on_outlined,
                      label: '위치 서비스',
                      value: _isStatusLoading
                          ? '확인 중'
                          : _serviceEnabled == true
                          ? '켜짐'
                          : '꺼짐',
                      valueColor: _serviceEnabled == true
                          ? const Color(0xFF1D9B55)
                          : const Color(0xFFB57900),
                    ),
                    _statusRow(
                      icon: Icons.security_outlined,
                      label: '위치 권한',
                      value: _isStatusLoading ? '확인 중' : _permissionLabel(),
                      valueColor:
                          _permission == LocationPermission.deniedForever
                          ? const Color(0xFFD14343)
                          : const Color(0xFF25324A),
                    ),
                    _statusRow(
                      icon: Icons.gps_fixed_rounded,
                      label: '현재 GPS 정확도',
                      value: _measurement == null
                          ? '아직 측정하지 않음'
                          : '${_measurement!.accuracyMeters.toStringAsFixed(1)} m',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _buildVerificationStatusCard(),
              const SizedBox(height: 12),
              _buildFinalVerificationCard(),
              if (_verificationError != null) ...[
                const SizedBox(height: 12),
                _ErrorCard(
                  message: _verificationError!,
                  onRetry: _loadVerificationStatus,
                ),
              ],
              const SizedBox(height: 14),
              _Card(child: _buildAction()),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _ErrorCard(message: _error!, onRetry: _measureLocation),
              ],
              if (_measurement != null) ...[
                const SizedBox(height: 12),
                _Card(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF1D9B55)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '현재 위치를 측정했습니다. 측정 정확도는 ${_measurement!.accuracyMeters.toStringAsFixed(1)} m입니다.\n'
                          '서버가 반환한 체류 인증 상태를 확인하고, 조건을 충족하면 최종 인증 상태를 다시 조회합니다.',
                          style: const TextStyle(
                            color: Color(0xFF526079),
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const _InfoCard(
                icon: Icons.privacy_tip_outlined,
                title: '개인정보 안내',
                message:
                    '위도·경도는 기기에 저장하거나 화면에 표시하지 않습니다. '
                    '이 화면에서는 백그라운드 추적을 하지 않으며, 위치 인증 완료 상태도 변경하지 않습니다.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF2FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _blue, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFF526079),
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3F1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFD14343), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(color: Color(0xFF7D2D2D), height: 1.4),
                ),
                const SizedBox(height: 7),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: onRetry,
                    child: const Text('다시 시도'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

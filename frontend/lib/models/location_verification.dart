class LocationVerificationStatus {
  const LocationVerificationStatus({
    required this.status,
    required this.validCheckCount,
    required this.requiredCheckCount,
    required this.firstValidCheckAt,
    required this.lastValidCheckAt,
    required this.lastCheckAt,
    required this.dwellSeconds,
    required this.minimumDwellSeconds,
    required this.dwellSatisfied,
    required this.intervalSatisfied,
    required this.additionalCheckRequired,
    required this.eligibleTimeStart,
    required this.eligibleTimeEnd,
    required this.eligibleTimeZone,
    required this.nextCheckAt,
    required this.message,
  });

  final String status;
  final int validCheckCount;
  final int requiredCheckCount;
  final DateTime? firstValidCheckAt;
  final DateTime? lastValidCheckAt;
  final DateTime? lastCheckAt;
  final int dwellSeconds;
  final int minimumDwellSeconds;
  final bool dwellSatisfied;
  final bool intervalSatisfied;
  final bool additionalCheckRequired;
  final String eligibleTimeStart;
  final String eligibleTimeEnd;
  final String eligibleTimeZone;
  final DateTime? nextCheckAt;
  final String? message;

  bool get isCompleted => status == 'COMPLETED';

  factory LocationVerificationStatus.fromJson(Map<String, dynamic> json) {
    DateTime? nullableDate(String key) {
      final value = json[key] as String?;
      return value == null ? null : DateTime.parse(value);
    }

    int integer(String key) => (json[key] as num).toInt();

    return LocationVerificationStatus(
      status: json['status'] as String,
      validCheckCount: integer('valid_check_count'),
      requiredCheckCount: integer('required_check_count'),
      firstValidCheckAt: nullableDate('first_valid_check_at'),
      lastValidCheckAt: nullableDate('last_valid_check_at'),
      lastCheckAt: nullableDate('last_check_at'),
      dwellSeconds: integer('dwell_seconds'),
      minimumDwellSeconds: integer('minimum_dwell_seconds'),
      dwellSatisfied: json['dwell_satisfied'] as bool,
      intervalSatisfied: json['interval_satisfied'] as bool,
      additionalCheckRequired: json['additional_check_required'] as bool,
      eligibleTimeStart: json['eligible_time_start'] as String,
      eligibleTimeEnd: json['eligible_time_end'] as String,
      eligibleTimeZone: json['eligible_time_zone'] as String,
      nextCheckAt: nullableDate('next_check_at'),
      message: json['message'] as String?,
    );
  }
}

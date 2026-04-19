import 'package:flutter/material.dart';

const double kScreenTopPadding = 50.0;
const EdgeInsets kScreenPadding = EdgeInsets.fromLTRB(16.0, kScreenTopPadding, 16.0, 16.0);
const Color kAccentColor = Color(0xFF00A9CE);
const Color kScreenBackgroundColor = Color(0xFFF8F9FA);

// ── SharedPreferences 키 ───────────────────────────────────────────────────
const String kPrefLastDeviceId  = 'last_device_id';

// ── 측정 주기 SharedPreferences 키 / 기본값 ───────────────────────────────
const String kPrefCalibSec    = 'calib_sec';
const String kPrefPpgOnMin    = 'ppg_on_min';
const String kPrefPpgOffMin   = 'ppg_off_min';
const String kPrefSleepOnMin  = 'sleep_on_min';
const String kPrefSleepOffMin = 'sleep_off_min';

const int kDefaultCalibSec    = 30;
const int kDefaultPpgOnMin    = 1;
const int kDefaultPpgOffMin   = 1;
const int kDefaultSleepOnMin  = 1;
const int kDefaultSleepOffMin = 1;

// ── 배터리 전압 SharedPreferences 키 / 기본값 ──────────────────────────────
const String kPrefBatteryMinMv  = 'battery_min_mv';
const String kPrefBatteryMaxMv  = 'battery_max_mv';
const int    kDefaultBatteryMinMv = 3500;
const int    kDefaultBatteryMaxMv = 4200;

BoxDecoration buildCardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Colors.grey.shade200),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.02),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

TextStyle buildSectionTitleStyle() {
  return TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.bold,
    color: Colors.grey.shade500,
  );
}

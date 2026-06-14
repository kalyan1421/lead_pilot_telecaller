import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The telecaller's own profile, edited in-app and persisted locally.
class UserProfile {
  const UserProfile({
    this.name = 'Telecaller',
    this.role = 'Telecaller',
    this.company = '',
    this.language = 'తె',
    this.notificationsEnabled = true,
  });

  final String name;
  final String role;
  final String company;
  final String language;
  final bool notificationsEnabled;

  /// First-letter initials for the avatar, e.g. "Ravi Verma" → "RV".
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return 'TC';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  UserProfile copyWith({
    String? name,
    String? role,
    String? company,
    String? language,
    bool? notificationsEnabled,
  }) =>
      UserProfile(
        name: name ?? this.name,
        role: role ?? this.role,
        company: company ?? this.company,
        language: language ?? this.language,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      );

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        name: j['name'] as String? ?? 'Telecaller',
        role: j['role'] as String? ?? 'Telecaller',
        company: j['company'] as String? ?? '',
        language: j['language'] as String? ?? 'తె',
        notificationsEnabled: j['notifications_enabled'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'role': role,
        'company': company,
        'language': language,
        'notifications_enabled': notificationsEnabled,
      };
}

class UserProfileStore {
  static const _key = 'user_profile_v1';

  Future<UserProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const UserProfile();
    try {
      return UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const UserProfile();
    }
  }

  Future<void> save(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(profile.toJson()));
  }
}

final userProfileStoreProvider =
    Provider<UserProfileStore>((_) => UserProfileStore());

final userProfileProvider =
    NotifierProvider<UserProfileController, UserProfile>(
  UserProfileController.new,
);

class UserProfileController extends Notifier<UserProfile> {
  @override
  UserProfile build() {
    _load();
    return const UserProfile();
  }

  Future<void> _load() async {
    state = await ref.read(userProfileStoreProvider).load();
  }

  Future<void> update(UserProfile profile) async {
    state = profile;
    await ref.read(userProfileStoreProvider).save(profile);
  }
}

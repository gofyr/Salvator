import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

@immutable
class Agent {
  final String id; // stable identifier
  final String name; // display name
  final String baseUrl;
  final String clientKey; // stored as entered; secured by secure storage

  const Agent({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.clientKey,
  });

  Agent copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? clientKey,
  }) => Agent(
    id: id ?? this.id,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    clientKey: clientKey ?? this.clientKey,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'clientKey': clientKey,
  };

  static Agent fromJson(Map<String, dynamic> m) => Agent(
    id: (m['id'] ?? '') as String,
    name: (m['name'] ?? '') as String,
    baseUrl: (m['baseUrl'] ?? '') as String,
    clientKey: (m['clientKey'] ?? '') as String,
  );
}

class AgentStore {
  static const _storage = FlutterSecureStorage();
  static const _agentsKey = 'agents';
  static const _currentIdKey = 'currentAgentId';

  Future<List<Agent>> loadAgents() async {
    final s = await _storage.read(key: _agentsKey);
    if (s == null || s.isEmpty) return [];
    try {
      final list = (jsonDecode(s) as List).cast<Map<String, dynamic>>();
      return list.map(Agent.fromJson).toList(growable: false);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAgents(List<Agent> agents) async {
    final data = jsonEncode(
      agents.map((a) => a.toJson()).toList(growable: false),
    );
    await _storage.write(key: _agentsKey, value: data);
  }

  Future<String?> loadCurrentAgentId() => _storage.read(key: _currentIdKey);
  Future<void> saveCurrentAgentId(String id) =>
      _storage.write(key: _currentIdKey, value: id);
}

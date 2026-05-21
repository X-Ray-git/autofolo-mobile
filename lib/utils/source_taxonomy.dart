import 'package:flutter/material.dart';

abstract final class SourceTaxonomy {
  static const Color feedColor = Color(0xFF7C3AED);
  static const Color socialColor = Color(0xFF2563EB);
  static const Color inboxColor = Color(0xFFF59E0B);
  static const Color fallbackColor = Color(0xFF64748B);

  static String viewKeyFromInt(int? view) => switch (view) {
    0 => 'feeds',
    1 => 'social',
    2 => 'inbox',
    _ => 'unknown',
  };

  static String viewLabelFromInt(int? view) => switch (view) {
    0 => '订阅源',
    1 => '社交',
    2 => '收件箱',
    _ => '未分类',
  };

  static Color viewColorFromInt(int? view) => switch (view) {
    0 => feedColor,
    1 => socialColor,
    2 => inboxColor,
    _ => fallbackColor,
  };

  static int viewOrderFromInt(int? view) => switch (view) {
    0 => 0,
    1 => 1,
    2 => 2,
    _ => 99,
  };

  static String viewLabelFromCategory(String? category) => switch (category) {
    'feeds' => '订阅源',
    'social' => '社交',
    'inbox' => '收件箱',
    _ => '未分类',
  };

  static Color viewColorFromCategory(String? category) => switch (category) {
    'feeds' => feedColor,
    'social' => socialColor,
    'inbox' => inboxColor,
    _ => fallbackColor,
  };

  static int viewOrderFromCategory(String? category) => switch (category) {
    'feeds' => 0,
    'social' => 1,
    'inbox' => 2,
    _ => 99,
  };

  static String inboxDisplayTitle(Map<String, dynamic> inbox) {
    final candidates = <Object?>[
      inbox['title'],
      inbox['name'],
      inbox['email'],
      inbox['address'],
      inbox['id'],
    ];
    for (final candidate in candidates) {
      final value = candidate?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '收件箱';
  }

  static String inboxShortLabel(Map<String, dynamic> inbox) {
    final candidates = <Object?>[
      inbox['shortName'],
      inbox['alias'],
      inbox['title'],
      inbox['name'],
      inbox['email'],
      inbox['address'],
      inbox['id'],
    ];
    for (final candidate in candidates) {
      final label = _normalizeInboxLabel(candidate?.toString() ?? '');
      if (label.isNotEmpty) return label;
    }
    return '收件箱';
  }

  static String _normalizeInboxLabel(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';

    final lower = trimmed.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (lower.contains('x-ray') || lower.contains('xray')) {
      return 'x-ray';
    }
    if (lower.contains('coderbill') ||
        lower.contains('coder-bill') ||
        lower.contains('coderbill')) {
      return 'coderbill';
    }
    if (lower.contains('@')) {
      final local = lower.split('@').first;
      if (local.contains('x-ray') || local.contains('xray')) return 'x-ray';
      if (local.contains('coderbill') || local.contains('coder-bill')) {
        return 'coderbill';
      }
      return local;
    }
    return trimmed;
  }
}

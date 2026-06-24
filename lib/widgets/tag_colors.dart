import 'package:flutter/material.dart';

/// Color map for product tags — sampled from Dan Murphy's badge icons
class TagColors {
  static const _map = {
    'New': Color(0xFF4CAF50),
    'Vegan': Color(0xFF388E3C),
    'Organic': Color(0xFF2E7D32),
    'Gluten_Free': Color(0xFF2196F3),
    'Limited_Release': Color(0xFF9C27B0),
    'Zero_': Color(0xFF00BCD4),
    'Low_Alcohol': Color(0xFF00BCD4),
    'Member Offer': Color(0xFFFF9800),
    'Catalogue_Offer': Color(0xFFE91E63),
  };

  static Color? forTag(String tag) => _map[tag];

  /// Extract display label from tag key
  static String label(String tag) {
    switch (tag) {
      case 'Zero_':
        return 'Zero Alcohol';
      case 'Gluten_Free':
        return 'Gluten Free';
      case 'Limited_Release':
        return 'Limited Release';
      case 'Low_Alcohol':
        return 'Low Alcohol';
      case 'Catalogue_Offer':
        return 'Catalogue';
      default:
        return tag.replaceAll('_', ' ');
    }
  }
}

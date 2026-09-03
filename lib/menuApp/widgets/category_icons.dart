import 'package:flutter/material.dart';

/// Icon for a category name. Keyword-matched (case-insensitive) instead of
/// an exact-name switch, since it needs to cover whatever categories a
/// branch actually has (was hardcoded to Daraejung's Korean category names,
/// so every Blue Moon category silently fell through to the default icon).
IconData getCategoryIcon(String category) {
  final name = category.toLowerCase();
  bool has(String kw) => name.contains(kw);

  if (has('cocktail') || has('liquor') || has('shot')) return Icons.local_bar_outlined;
  if (has('wine') || has('champagne')) return Icons.wine_bar_outlined;
  if (has('whiskey') || has('whisky') || has('tequila') || has('soju') || has('gin') || has('vodka') || has('cognac') || has('bourbon')) {
    return Icons.liquor_outlined;
  }
  if (has('beer')) return Icons.sports_bar_outlined;
  if (has('coffee') || has('frappe')) return Icons.coffee_outlined;
  if (has('shake') || has('ade') || has('soda') || has('drink') || has('mixer') || has('water')) {
    return Icons.local_drink_outlined;
  }
  if (has('pizza')) return Icons.local_pizza_outlined;
  if (has('pasta') || has('spaghetti')) return Icons.dinner_dining_outlined;
  if (has('noodle') || has('ramen') || has('soup')) return Icons.ramen_dining_outlined;
  if (has('rice')) return Icons.rice_bowl_outlined;
  if (has('salad')) return Icons.eco_outlined;
  if (has('dessert') || has('ice cream') || has('sweet')) return Icons.icecream_outlined;
  if (has('platter') || has('sando') || has('sandwich')) return Icons.tapas_outlined;
  if (has('chicken') || has('bbq') || has('barbecue') || has('grill')) return Icons.local_fire_department_outlined;
  if (has('seafood') || has('shrimp') || has('fish')) return Icons.set_meal_outlined;
  if (has('fries') || has('side')) return Icons.lunch_dining_outlined;
  if (has('set menu') || has('promo') || has('package')) return Icons.set_meal_outlined;
  if (has('game')) return Icons.sports_esports_outlined;
  if (has('room') || has('ktv') || has('charge')) return Icons.meeting_room_outlined;
  if (has('delivery')) return Icons.delivery_dining_outlined;
  if (has('star') || has('recommend')) return Icons.star_outline;
  if (category == 'All') return Icons.apps_rounded;
  return Icons.restaurant_outlined;
}

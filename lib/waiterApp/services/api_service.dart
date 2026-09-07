import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/app_config.dart';
import '../../shared/globals.dart';

class ApiService {
  // Cached base URL to avoid repeated async calls
  static String? _cachedBaseUrl;
  static Map<String, dynamic>? _cachedTopRevenueResponse;
  static DateTime? _cachedTopRevenueTime;
  
  // Get base URL from config
  static Future<String> get baseUrl async {
    if (_cachedBaseUrl == null) {
      _cachedBaseUrl = await AppConfig.getBaseUrl();
    }
    return _cachedBaseUrl!;
  }

  static Future<String> _getLanguageCode() async {
    final prefs = await SharedPreferences.getInstance();
    final initialized = prefs.getBool('language_initialized') ?? false;
    if (!initialized) {
      await prefs.setString('language', 'en');
      await prefs.setBool('language_initialized', true);
      setAppLanguage('en');
      return 'en';
    }
    final lang = prefs.getString('language') ?? 'en';
    if (languageNotifier.value != lang) {
      setAppLanguage(lang);
    }
    return lang;
  }

  static Future<Uri> _buildUriWithLanguage(String urlString) async {
    final lang = await _getLanguageCode();
    final uri = Uri.parse(urlString);
    final params = Map<String, String>.from(uri.queryParameters);
    params['lang'] = lang;
    return uri.replace(queryParameters: params);
  }
  
  // Clear cached URL (call this when URL changes)
  static void clearBaseUrlCache() {
    _cachedBaseUrl = null;
  }

  // Login API endpoint
  static Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final url = Uri.parse('${await baseUrl}/api/login');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        // Save user data to shared preferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', data['data']['user_id'].toString());
        await prefs.setString('username', data['data']['username']);
        await prefs.setString('firstname', data['data']['firstname'] ?? '');
        await prefs.setString('lastname', data['data']['lastname'] ?? '');
        await prefs.setString('permissions', data['data']['permissions'].toString());
        if (data['data']['role'] != null) {
          await prefs.setString('role', data['data']['role'].toString());
        }
        if (data['data']['table_id'] != null) {
          await prefs.setString('table_id', data['data']['table_id'].toString());
        }
        // Save JWT tokens for authentication
        if (data['tokens'] != null) {
          await prefs.setString('access_token', data['tokens']['accessToken'] ?? '');
          await prefs.setString('refresh_token', data['tokens']['refreshToken'] ?? '');
        }
        await prefs.setBool('is_logged_in', true);

        return {
          'success': true,
          'data': data['data'],
        };
      } else {
        // Handle all error status codes (401, 403, 500, etc.)
        return {
          'success': false,
          'error': data['error'] ?? 'Login failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Connection error: ${e.toString()}',
      };
    }
  }

  // Check if user is logged in and token is valid
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedInFlag = prefs.getBool('is_logged_in') ?? false;
    final accessToken = prefs.getString('access_token') ?? '';
    
    // If no login flag or no token, user is not logged in
    if (!isLoggedInFlag || accessToken.isEmpty) {
      return false;
    }
    
    // Validate token by making a test API call
    try {
      final url = await _buildUriWithLanguage('${await baseUrl}/api/categories');
      final headers = await getAuthHeaders();
      final response = await http.get(url, headers: headers);
      
      // If 401, token is invalid - logout user
      if (response.statusCode == 401) {
        await logout();
        return false;
      }
      
      // If 200, token is valid
      return response.statusCode == 200;
    } catch (e) {
      // On error, assume token might be invalid but don't logout (could be network issue)
      // Return true if we have a token, false otherwise
      return accessToken.isNotEmpty;
    }
  }

  // Logout
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setBool('is_logged_in', false);
  }

  // Get authentication headers
  static Future<Map<String, String>> getAuthHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token') ?? '';
    
    final headers = {
      'Content-Type': 'application/json',
    };
    
    if (accessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $accessToken';
    }
    
    return headers;
  }

  // Get user data from shared preferences
  static Future<Map<String, String?>> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'user_id': prefs.getString('user_id'),
      'username': prefs.getString('username'),
      'firstname': prefs.getString('firstname'),
      'lastname': prefs.getString('lastname'),
      'permissions': prefs.getString('permissions'),
      'role': prefs.getString('role'),
      'table_id': prefs.getString('table_id'),
    };
  }

  // Get all categories
  static Future<Map<String, dynamic>> getCategories() async {
    try {
      final url = await _buildUriWithLanguage('${await baseUrl}/api/categories');
      
      final headers = await getAuthHeaders();
      
      final response = await http.get(
        url,
        headers: headers,
      );

      // Handle 401 Unauthorized - token expired or invalid
      if (response.statusCode == 401) {
        await logout();
        return {
          'success': false,
          'error': 'Session expired. Please login again.',
          'unauthorized': true,
        };
      }

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'data': data['data'],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to fetch categories',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Connection error: ${e.toString()}',
      };
    }
  }

  // Get menu items (with optional category filter)
  static Future<Map<String, dynamic>> getMenuItems({int? categoryId}) async {
    try {
      String urlString = '${await baseUrl}/api/menu';
      if (categoryId != null) {
        urlString += '?category_id=$categoryId';
      }
      final url = await _buildUriWithLanguage(urlString);
      
      final headers = await getAuthHeaders();
      
      final response = await http.get(
        url,
        headers: headers,
      );

      // Handle 401 Unauthorized - token expired or invalid
      if (response.statusCode == 401) {
        await logout();
        return {
          'success': false,
          'error': 'Session expired. Please login again.',
          'unauthorized': true,
        };
      }

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'data': data['data'],
          'count': data['count'] ?? data['data'].length,
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to fetch menu items',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Connection error: ${e.toString()}',
      };
    }
  }

  static List<dynamic>? get cachedTopRevenueRaw => _cachedTopRevenueResponse?['data'] as List<dynamic>?;

  // Get top revenue / popular menu items (matches Sales Analytics top revenue)
  static Future<Map<String, dynamic>> getTopRevenueItems({int limit = 20, bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedTopRevenueResponse != null && _cachedTopRevenueTime != null) {
      if (DateTime.now().difference(_cachedTopRevenueTime!).inMinutes < 2) {
        return _cachedTopRevenueResponse!;
      }
    }

    try {
      final url = await _buildUriWithLanguage('${await baseUrl}/api/menu/top-revenue?limit=$limit');
      final headers = await getAuthHeaders();

      final response = await http.get(
        url,
        headers: headers,
      );

      if (response.statusCode == 401) {
        await logout();
        return {
          'success': false,
          'error': 'Session expired. Please login again.',
          'unauthorized': true,
        };
      }

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final result = {
          'success': true,
          'data': data['data'],
          'count': data['count'] ?? (data['data'] as List).length,
        };
        _cachedTopRevenueResponse = result;
        _cachedTopRevenueTime = DateTime.now();
        return result;
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to fetch top revenue items',
        };
      }
    } catch (e) {
      if (_cachedTopRevenueResponse != null) {
        return _cachedTopRevenueResponse!;
      }
      return {
        'success': false,
        'error': 'Connection error: ${e.toString()}',
      };
    }
  }

  // Get all restaurant tables
  static Future<Map<String, dynamic>> getTables() async {
    try {
      final url = await _buildUriWithLanguage('${await baseUrl}/api/tables');

      final headers = await getAuthHeaders();
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 401) {
        await logout();
        return {
          'success': false,
          'error': 'Session expired. Please login again.',
          'unauthorized': true,
        };
      }

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'data': data['data'],
        };
      }

      return {
        'success': false,
        'error': data['error'] ?? 'Failed to fetch tables',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Connection error: ${e.toString()}',
      };
    }
  }

  // Get waiter orders (orders table status)
  static Future<Map<String, dynamic>> getWaiterOrders() async {
    try {
      final url = await _buildUriWithLanguage('${await baseUrl}/api/waiter/orders');

      final headers = await getAuthHeaders();
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 401) {
        await logout();
        return {
          'success': false,
          'error': 'Session expired. Please login again.',
          'unauthorized': true,
        };
      }

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'data': data['data'],
        };
      }

      return {
        'success': false,
        'error': data['error'] ?? 'Failed to fetch orders',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Connection error: ${e.toString()}',
      };
    }
  }

  // Update order status (pending/confirmed/settled)
  static Future<Map<String, dynamic>> updateWaiterOrderStatus({
    required int orderId,
    required int status,
    String? paymentMethod,
    double? discountAmount,
    double? grandTotal,
    double? amountPaid,
    String? paymentRef,
    String? remarks,
  }) async {
    try {
      final url = Uri.parse('${await baseUrl}/api/waiter/orders/$orderId/status');
      final headers = await getAuthHeaders();

      final response = await http.patch(
        url,
        headers: headers,
        body: jsonEncode({
          'status': status,
          if (paymentMethod != null) 'payment_method': paymentMethod,
          if (discountAmount != null) 'discount_amount': discountAmount,
          if (grandTotal != null) 'grand_total': grandTotal,
          if (amountPaid != null) 'amount_paid': amountPaid,
          if (paymentRef != null) 'payment_ref': paymentRef,
          if (remarks != null) 'remarks': remarks,
        }),
      );

      if (response.statusCode == 401) {
        await logout();
        return {
          'success': false,
          'error': 'Session expired. Please login again.',
          'unauthorized': true,
        };
      }

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'data': data['data'],
        };
      }

      return {
        'success': false,
        'error': data['error'] ?? 'Failed to update order status',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Connection error: ${e.toString()}',
      };
    }
  }

  // Transfer table order (Lipat Mesa)
  static Future<Map<String, dynamic>> transferTableOrder({
    required int orderId,
    required int targetTableId,
  }) async {
    try {
      final url = Uri.parse('${await baseUrl}/api/waiter/orders/$orderId/transfer-table');
      final headers = await getAuthHeaders();

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({
          'target_table_id': targetTableId,
        }),
      );

      if (response.statusCode == 401) {
        await logout();
        return {
          'success': false,
          'error': 'Session expired. Please login again.',
          'unauthorized': true,
        };
      }

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'data': data['data'],
          'message': data['message'],
        };
      }

      return {
        'success': false,
        'error': data['error'] ?? 'Failed to transfer table order',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Connection error: ${e.toString()}',
      };
    }
  }

  // Create order
  // items: List of order items with menu_id, qty, unit_price, and optional status
  static Future<Map<String, dynamic>> createOrder({
    required String orderNo,
    int? tableId,
    String? orderType,
    double subtotal = 0.0,
    double taxAmount = 0.0,
    double serviceCharge = 0.0,
    double discountAmount = 0.0,
    double grandTotal = 0.0,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final url = Uri.parse('${await baseUrl}/api/orders');
      
      final headers = await getAuthHeaders();
      
      // Prepare request body
      final body = {
        'order_no': orderNo,
        if (tableId != null) 'table_id': tableId,
        if (orderType != null) 'order_type': orderType,
        'subtotal': subtotal,
        'tax_amount': taxAmount,
        'service_charge': serviceCharge,
        'discount_amount': discountAmount,
        'grand_total': grandTotal,
        'items': items,
      };
      
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(body),
      );

      // Handle 401 Unauthorized - token expired or invalid
      if (response.statusCode == 401) {
        await logout();
        return {
          'success': false,
          'error': 'Session expired. Please login again.',
          'unauthorized': true,
        };
      }

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (data['success'] == true) {
          return {
            'success': true,
            'data': data['data'],
          };
        } else {
          return {
            'success': false,
            'error': data['error'] ?? 'Failed to create order',
          };
        }
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to create order',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Connection error: ${e.toString()}',
      };
    }
  }

  // Add items to existing order (Additional Order)
  static Future<Map<String, dynamic>> addItemsToOrder({
    required int orderId,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final url = Uri.parse('${await baseUrl}/api/orders/$orderId/items');
      
      final headers = await getAuthHeaders();
      
      // Prepare request body
      final body = {
        'items': items,
      };
      
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(body),
      );

      // Handle 401 Unauthorized - token expired or invalid
      if (response.statusCode == 401) {
        await logout();
        return {
          'success': false,
          'error': 'Session expired. Please login again.',
          'unauthorized': true,
        };
      }

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (data['success'] == true) {
          return {
            'success': true,
            'data': data['data'],
          };
        } else {
          return {
            'success': false,
            'error': data['error'] ?? 'Failed to add items to order',
          };
        }
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to add items to order',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Connection error: ${e.toString()}',
      };
    }
  }

  // Get user orders from server (for syncing with local storage)
  static Future<Map<String, dynamic>> getUserOrders() async {
    try {
      final url = await _buildUriWithLanguage('${await baseUrl}/api/orders');
      
      final headers = await getAuthHeaders();
      
      final response = await http.get(
        url,
        headers: headers,
      );

      // Handle 401 Unauthorized - token expired or invalid
      if (response.statusCode == 401) {
        await logout();
        return {
          'success': false,
          'error': 'Session expired. Please login again.',
          'unauthorized': true,
        };
      }

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'data': data['data'],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to fetch orders',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Connection error: ${e.toString()}',
      };
    }
  }

  // Save orders to local storage
  static Future<void> saveOrders(List<Map<String, dynamic>> orders) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ordersJson = jsonEncode(orders);
      await prefs.setString('saved_orders', ordersJson);
    } catch (e) {
      debugPrint('Error saving orders: $e');
    }
  }

  // Load orders from local storage
  static Future<List<Map<String, dynamic>>> loadOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ordersJson = prefs.getString('saved_orders');
      if (ordersJson != null && ordersJson.isNotEmpty) {
        final orders = jsonDecode(ordersJson) as List;
        return orders.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('Error loading orders: $e');
    }
    return [];
  }

  // Preload images for better UX using http.get (caches in CachedNetworkImage automatically)
  static Future<void> preloadImages(List<String> imageUrls, {int maxConcurrent = 3}) async {
    if (imageUrls.isEmpty) return;
    
    // Filter out null or empty URLs
    final validUrls = imageUrls.where((url) => url.isNotEmpty && url.startsWith('http')).toList();
    if (validUrls.isEmpty) return;
    
    // Preload images in batches to avoid overwhelming the network
    for (int i = 0; i < validUrls.length; i += maxConcurrent) {
      final batch = validUrls.skip(i).take(maxConcurrent).toList();
      await Future.wait(
        batch.map((url) async {
          try {
            final uri = Uri.parse(url);
            await http.get(uri).timeout(
              const Duration(seconds: 5),
              onTimeout: () => throw Exception('Timeout'),
            );
          } catch (e) {
            // Silently fail - preloading is optional
          }
        }),
      );
    }
  }

  // Replace items in an existing order
  static Future<Map<String, dynamic>> replaceOrderItems({
    required int orderId,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final url = Uri.parse('${await baseUrl}/api/orders/$orderId/items');
      final headers = await getAuthHeaders();

      final response = await http.put(
        url,
        headers: headers,
        body: jsonEncode({
          'items': items,
        }),
      );

      if (response.statusCode == 401) {
        await logout();
        return {
          'success': false,
          'error': 'Session expired. Please login again.',
          'unauthorized': true,
        };
      }

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'data': data['data'],
        };
      }

      return {
        'success': false,
        'error': data['error'] ?? 'Failed to update order items',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Connection error: ${e.toString()}',
      };
    }
  }

  // Kitchen APIs
  static Future<Map<String, dynamic>> getKitchenOrders() async {
    try {
      final url = await _buildUriWithLanguage('${await baseUrl}/api/kitchen/orders');
      final headers = await getAuthHeaders();
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 401) {
        await logout();
        return {'success': false, 'error': 'Session expired', 'unauthorized': true};
      }

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'data': data['data']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Failed to fetch kitchen orders'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: ${e.toString()}'};
    }
  }

  static Future<Map<String, dynamic>> updateKitchenOrderStatus(int orderId, int status) async {
    try {
      final url = Uri.parse('${await baseUrl}/api/kitchen/orders/$orderId/status');
      final headers = await getAuthHeaders();
      // Using POST instead of PATCH to avoid CORS issues on some servers
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({'status': status}),
      );

      if (response.statusCode == 401) {
        await logout();
        return {'success': false, 'error': 'Session expired', 'unauthorized': true};
      }

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Failed to update order status'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: ${e.toString()}'};
    }
  }
}


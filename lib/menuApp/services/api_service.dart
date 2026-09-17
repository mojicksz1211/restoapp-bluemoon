import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/app_config.dart';
import '../../shared/globals.dart';
import 'socket_service.dart';

class ApiService {
  // Cached base URL to avoid repeated async calls
  static String? _cachedBaseUrl;
  // WiFi-connected-but-no-internet is the worst case for a bare http call —
  // the OS's own TCP connect timeout can run 60s+ before a SocketException
  // is even thrown, which feels like the app is frozen. Every request below
  // caps at this instead, so the existing offline fallbacks kick in fast.
  static const Duration _httpTimeout = Duration(seconds: 8);

  // Get base URL from config
  static Future<String> get baseUrl async {
    if (_cachedBaseUrl == null) {
      _cachedBaseUrl = await AppConfig.getBaseUrl();
    }
    return _cachedBaseUrl!;
  }
  
  // Clear cached URL (call this when URL changes)
  static void clearBaseUrlCache() {
    _cachedBaseUrl = null;
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
      ).timeout(_httpTimeout);

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
        // Branch — keeps realtime socket rooms scoped to this user's branch.
        if (data['data']['branch_id'] != null) {
          await prefs.setString('branch_id', data['data']['branch_id'].toString());
        } else {
          await prefs.remove('branch_id');
        }
        if (data['data']['branch_name'] != null) {
          await prefs.setString('branch_name', data['data']['branch_name'].toString());
        }
        // Floor scope — restricts waiter/cashier accounts to Ground Floor or
        // 2nd Floor tables only. Null/absent means unscoped (sees both).
        if (data['data']['floor'] != null) {
          await prefs.setString('floor', data['data']['floor'].toString());
        } else {
          await prefs.remove('floor');
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
      final response = await http.get(url, headers: headers).timeout(_httpTimeout);
      
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
    _cachedBaseUrl = null;
    // Tear the socket all the way down so the next login always starts a
    // brand-new connection (fresh branch id, no leftover reconnection state
    // from a session that never managed to connect).
    SocketService.disconnect();
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
      'branch_id': prefs.getString('branch_id'),
      'branch_name': prefs.getString('branch_name'),
    };
  }

  /// This user's branch id, or null for multi-branch/admin accounts.
  static Future<int?> getBranchId() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('branch_id');
    return raw == null ? null : int.tryParse(raw);
  }

  // Get all categories
  static Future<Map<String, dynamic>> getCategories() async {
    try {
      final url = await _buildUriWithLanguage('${await baseUrl}/api/categories');
      
      final headers = await getAuthHeaders();
      
      final response = await http.get(
        url,
        headers: headers,
      ).timeout(_httpTimeout);

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
      ).timeout(_httpTimeout);

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
      ).timeout(_httpTimeout);

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
          // Table already has an open order server-side (e.g. a waiter started one
          // for this table on another device): caller should append to it instead.
          if (data['code'] == 'ACTIVE_ORDER_EXISTS') 'code': data['code'],
          if (data['existing_order_id'] != null) 'existing_order_id': data['existing_order_id'],
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
      ).timeout(_httpTimeout);

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
      final userData = await getUserData();
      final tableId = userData['table_id'];
      final url = Uri.parse('${await baseUrl}/api/orders').replace(
        queryParameters: tableId != null && tableId.isNotEmpty
            ? {
                'table_id': tableId,
              }
            : null,
      );
      
      final headers = await getAuthHeaders();
      
      final response = await http.get(
        url,
        headers: headers,
      ).timeout(_httpTimeout);

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

  // Kitchen APIs
  static Future<Map<String, dynamic>> getKitchenOrders() async {
    try {
      final url = Uri.parse('${await baseUrl}/api/kitchen/orders');
      final headers = await getAuthHeaders();
      final response = await http.get(url, headers: headers).timeout(_httpTimeout);

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
      ).timeout(_httpTimeout);

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


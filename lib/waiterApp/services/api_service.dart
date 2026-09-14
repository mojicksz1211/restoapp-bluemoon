import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/app_config.dart';
import '../../shared/globals.dart';
import '../../shared/offline_sync_service.dart';
import 'socket_service.dart';

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
        // Branch — needed so realtime socket rooms and event filtering stay
        // scoped to this user's branch.
        if (data['data']['branch_id'] != null) {
          await prefs.setString('branch_id', data['data']['branch_id'].toString());
        } else {
          await prefs.remove('branch_id');
        }
        if (data['data']['branch_name'] != null) {
          await prefs.setString('branch_name', data['data']['branch_name'].toString());
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
      final response = await http.get(url, headers: headers);

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
        final catList = List<Map<String, dynamic>>.from(data['data']);
        unawaited(OfflineSyncService.instance.saveCachedCategories(catList));
        return {
          'success': true,
          'data': catList,
        };
      } else {
        final cached = await OfflineSyncService.instance.getCachedCategories();
        if (cached != null && cached.isNotEmpty) {
          return {'success': true, 'data': cached, 'is_offline': true};
        }
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to fetch categories',
        };
      }
    } catch (e) {
      final cached = await OfflineSyncService.instance.getCachedCategories();
      if (cached != null && cached.isNotEmpty) {
        return {'success': true, 'data': cached, 'is_offline': true};
      }
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
      final response = await http.get(url, headers: headers);

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
        final menuList = List<Map<String, dynamic>>.from(data['data']);
        if (categoryId == null) {
          unawaited(OfflineSyncService.instance.saveCachedMenu(menuList));
        }
        return {
          'success': true,
          'data': menuList,
          'count': data['count'] ?? menuList.length,
        };
      } else {
        final cached = await OfflineSyncService.instance.getCachedMenu();
        if (cached != null && cached.isNotEmpty) {
          var list = cached;
          if (categoryId != null) {
            list = list.where((m) => (m['category_id'] as num?)?.toInt() == categoryId).toList();
          }
          return {
            'success': true,
            'data': list,
            'count': list.length,
            'is_offline': true,
          };
        }
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to fetch menu items',
        };
      }
    } catch (e) {
      final cached = await OfflineSyncService.instance.getCachedMenu();
      if (cached != null && cached.isNotEmpty) {
        var list = cached;
        if (categoryId != null) {
          list = list.where((m) => (m['category_id'] as num?)?.toInt() == categoryId).toList();
        }
        return {
          'success': true,
          'data': list,
          'count': list.length,
          'is_offline': true,
        };
      }
      return {
        'success': false,
        'error': 'Connection error: ${e.toString()}',
      };
    }
  }

  static List<dynamic>? get cachedTopRevenueRaw => _cachedTopRevenueResponse?['data'] as List<dynamic>?;

  // Get top revenue / popular menu items (matches Sales Analytics top revenue)
  // Set once the backend answers /api/menu/top-revenue with 404/501 (older
  // server without the route) so we stop re-probing it every couple of minutes.
  static bool _topRevenueEndpointMissing = false;

  static Future<Map<String, dynamic>> getTopRevenueItems({int limit = 20, bool forceRefresh = false}) async {
    if (_topRevenueEndpointMissing && !forceRefresh) {
      return {'success': false, 'error': 'top-revenue endpoint unavailable', 'unavailable': true};
    }
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

      if (response.statusCode == 404 || response.statusCode == 501) {
        _topRevenueEndpointMissing = true;
        return {'success': false, 'error': 'top-revenue endpoint unavailable', 'unavailable': true};
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
        final tablesList = List<Map<String, dynamic>>.from(data['data']);
        unawaited(OfflineSyncService.instance.saveCachedTables(tablesList));
        return {
          'success': true,
          'data': tablesList,
        };
      }

      final cached = await OfflineSyncService.instance.getCachedTables();
      if (cached != null && cached.isNotEmpty) {
        return {'success': true, 'data': cached, 'is_offline': true};
      }

      return {
        'success': false,
        'error': data['error'] ?? 'Failed to fetch tables',
      };
    } catch (e) {
      final cached = await OfflineSyncService.instance.getCachedTables();
      if (cached != null && cached.isNotEmpty) {
        return {'success': true, 'data': cached, 'is_offline': true};
      }
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
        final serverOrders = List<Map<String, dynamic>>.from(data['data']);

        // Preserve any local offline pending orders that haven't synced yet
        final localOrders = await OfflineSyncService.instance.getCachedOrders();
        final List<Map<String, dynamic>> merged = [];
        final Set<dynamic> serverOrderNos = serverOrders.map((o) => o['order_no']).toSet();

        if (localOrders != null) {
          for (final lo in localOrders) {
            final id = (lo['order_id'] ?? lo['IDNo'] ?? lo['id'] as num?)?.toInt() ?? 0;
            if (id < 0 && !serverOrderNos.contains(lo['order_no'])) {
              merged.add(lo);
            }
          }
        }
        merged.addAll(serverOrders);

        unawaited(OfflineSyncService.instance.saveCachedOrders(merged));
        return {
          'success': true,
          'data': merged,
        };
      }

      final cached = await OfflineSyncService.instance.getCachedOrders();
      if (cached != null) {
        return {'success': true, 'data': cached, 'is_offline': true};
      }

      return {
        'success': false,
        'error': data['error'] ?? 'Failed to fetch orders',
      };
    } catch (e) {
      final cached = await OfflineSyncService.instance.getCachedOrders();
      if (cached != null) {
        return {'success': true, 'data': cached, 'is_offline': true};
      }
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
        unawaited(OfflineSyncService.instance.updateLocalOrderStatus(
          orderId: orderId,
          status: status,
          paymentMethod: paymentMethod,
          discountAmount: discountAmount,
          grandTotal: grandTotal,
          amountPaid: amountPaid,
          paymentRef: paymentRef,
          remarks: remarks,
        ));
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
      // Offline fallback: update local status & queue action
      await OfflineSyncService.instance.updateLocalOrderStatus(
        orderId: orderId,
        status: status,
        paymentMethod: paymentMethod,
        discountAmount: discountAmount,
        grandTotal: grandTotal,
        amountPaid: amountPaid,
        paymentRef: paymentRef,
        remarks: remarks,
      );
      await OfflineSyncService.instance.enqueueAction(
        type: 'update_status',
        orderId: orderId,
        payload: {
          'status': status,
          if (paymentMethod != null) 'payment_method': paymentMethod,
          if (discountAmount != null) 'discount_amount': discountAmount,
          if (grandTotal != null) 'grand_total': grandTotal,
          if (amountPaid != null) 'amount_paid': amountPaid,
          if (paymentRef != null) 'payment_ref': paymentRef,
          if (remarks != null) 'remarks': remarks,
        },
      );
      return {
        'success': true,
        'data': {'order_id': orderId, 'status': status, 'is_offline': true},
        'is_offline': true,
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
        unawaited(OfflineSyncService.instance.transferLocalTableOrder(orderId, targetTableId));
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
      await OfflineSyncService.instance.transferLocalTableOrder(orderId, targetTableId);
      await OfflineSyncService.instance.enqueueAction(
        type: 'transfer_table',
        orderId: orderId,
        payload: {'target_table_id': targetTableId},
      );
      return {
        'success': true,
        'data': {'order_id': orderId, 'new_table_id': targetTableId, 'is_offline': true},
        'message': 'Table transfer saved locally (Offline)',
        'is_offline': true,
      };
    }
  }

  // Extend room charge — adds `qty` unit(s) (0.5 steps, same as admin's
  // manual-order room charge stepper) of the table's room charge to the
  // order's service charge and recomputes the grand total.
  static Future<Map<String, dynamic>> extendRoomCharge({
    required int orderId,
    double qty = 1.0,
  }) async {
    try {
      final url = Uri.parse('${await baseUrl}/api/waiter/orders/$orderId/extend-room-charge');
      final headers = await getAuthHeaders();

      final response = await http.post(url, headers: headers, body: jsonEncode({'qty': qty}));

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
        unawaited(OfflineSyncService.instance.extendLocalRoomCharge(orderId, qty: qty));
        return {
          'success': true,
          'data': data['data'],
        };
      }

      return {
        'success': false,
        'error': data['error'] ?? 'Failed to extend room charge',
      };
    } catch (e) {
      await OfflineSyncService.instance.extendLocalRoomCharge(orderId, qty: qty);
      await OfflineSyncService.instance.enqueueAction(
        type: 'extend_room_charge',
        orderId: orderId,
        payload: {'qty': qty},
      );
      return {
        'success': true,
        'data': {'order_id': orderId, 'is_offline': true},
        'is_offline': true,
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
      // Offline fallback: create local order with unique temp negative ID & enqueue
      final tempId = OfflineSyncService.instance.generateTempOrderId();
      final offlineOrderData = {
        'order_id': tempId,
        'order_no': orderNo,
        'table_id': tableId,
        'order_type': orderType,
        'status': 3, // PENDING
        'subtotal': subtotal,
        'tax_amount': taxAmount,
        'service_charge': serviceCharge,
        'discount_amount': discountAmount,
        'grand_total': grandTotal,
        'encoded_dt': DateTime.now().toIso8601String(),
        'is_offline': true,
        'items': items.map((it) => {
          'menu_id': it['menu_id'],
          'qty': it['qty'],
          'unit_price': it['unit_price'],
          'line_total': ((it['qty'] as num?)?.toDouble() ?? 1.0) * ((it['unit_price'] as num?)?.toDouble() ?? 0.0),
          'status': it['status'] ?? 3,
          if (it['remarks'] != null) 'remarks': it['remarks'],
        }).toList(),
      };

      await OfflineSyncService.instance.addLocalOfflineOrder(offlineOrderData);
      await OfflineSyncService.instance.enqueueAction(
        type: 'create_order',
        orderId: tempId,
        tempId: tempId,
        payload: {
          'order_no': orderNo,
          if (tableId != null) 'table_id': tableId,
          if (orderType != null) 'order_type': orderType,
          'subtotal': subtotal,
          'tax_amount': taxAmount,
          'service_charge': serviceCharge,
          'discount_amount': discountAmount,
          'grand_total': grandTotal,
          // Send the original offline timestamp so the server records the actual
          // order time, not the later sync time.
          'encoded_dt': DateTime.now().toIso8601String(),
          'items': items,
        },
      );

      return {
        'success': true,
        'data': {
          'order_id': tempId,
          'order_no': orderNo,
          'table_id': tableId,
          'is_offline': true,
        },
        'is_offline': true,
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
      await OfflineSyncService.instance.addItemsToLocalOrder(orderId, items);
      await OfflineSyncService.instance.enqueueAction(
        type: 'add_items',
        orderId: orderId,
        payload: {'items': items},
      );
      return {
        'success': true,
        'data': {'order_id': orderId, 'is_offline': true},
        'is_offline': true,
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


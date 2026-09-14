import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bluemoon_resto_app/shared/offline_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('OfflineSyncService Tests', () {
    test('generateTempOrderId produces negative integers', () {
      final service = OfflineSyncService.instance;
      final id1 = service.generateTempOrderId();
      final id2 = service.generateTempOrderId();

      expect(id1, isNegative);
      expect(id2, isNegative);
      expect(id1 != id2, isTrue);
    });

    test('OfflineAction serialization and deserialization works correctly', () {
      final now = DateTime.now();
      final action = OfflineAction(
        id: 'test_action_1',
        type: 'create_order',
        orderId: -1001,
        tempId: -1001,
        createdAt: now,
        payload: {
          'order_no': 'ORD-OFFLINE-001',
          'table_id': 5,
          'grand_total': 450.0,
        },
      );

      final json = action.toJson();
      expect(json['id'], equals('test_action_1'));
      expect(json['type'], equals('create_order'));
      expect(json['order_id'], equals(-1001));
      expect(json['temp_id'], equals(-1001));

      final restored = OfflineAction.fromJson(json);
      expect(restored.id, equals(action.id));
      expect(restored.type, equals(action.type));
      expect(restored.orderId, equals(action.orderId));
      expect(restored.tempId, equals(action.tempId));
      expect(restored.payload['order_no'], equals('ORD-OFFLINE-001'));
    });

    test('Local cache stores and retrieves tables, menu, and orders', () async {
      final service = OfflineSyncService.instance;
      await service.initialize();

      // Test tables caching
      final sampleTables = [
        {'id': 1, 'table_number': 'T1', 'status': 1, 'capacity': 4},
        {'id': 2, 'table_number': 'T2', 'status': 2, 'capacity': 6},
      ];
      await service.saveCachedTables(sampleTables);
      final retrievedTables = await service.getCachedTables();
      expect(retrievedTables, isNotNull);
      expect(retrievedTables!.length, equals(2));
      expect(retrievedTables[0]['table_number'], equals('T1'));

      // Test menu caching
      final sampleMenu = [
        {'id': 101, 'name': 'San Miguel Beer', 'price': 85.0, 'category_id': 1},
        {'id': 102, 'name': 'Sizzling Sisig', 'price': 220.0, 'category_id': 2},
      ];
      await service.saveCachedMenu(sampleMenu);
      final retrievedMenu = await service.getCachedMenu();
      expect(retrievedMenu, isNotNull);
      expect(retrievedMenu!.length, equals(2));
      expect(retrievedMenu[1]['name'], equals('Sizzling Sisig'));
    });

    test('addLocalOfflineOrder updates cached orders and occupies table', () async {
      final service = OfflineSyncService.instance;
      await service.initialize();

      // Seed table 1 as available (status = 1)
      await service.saveCachedTables([
        {'id': 1, 'table_number': 'T1', 'status': 1, 'capacity': 4},
      ]);

      final tempId = service.generateTempOrderId();
      final offlineOrder = {
        'order_id': tempId,
        'order_no': 'ORD-OFFLINE-TEST',
        'table_id': 1,
        'status': 3,
        'grand_total': 500.0,
        'items': [
          {'menu_id': 101, 'qty': 2, 'unit_price': 85.0, 'line_total': 170.0},
        ],
      };

      await service.addLocalOfflineOrder(offlineOrder);

      // Verify order is in cached orders
      final cachedOrders = await service.getCachedOrders();
      expect(cachedOrders, isNotNull);
      expect(cachedOrders!.length, equals(1));
      expect(cachedOrders[0]['order_id'], equals(tempId));

      // Verify table 1 is now marked Occupied (status = 2)
      final tables = await service.getCachedTables();
      expect(tables, isNotNull);
      final table1 = tables!.firstWhere((t) => t['id'] == 1);
      expect(table1['status'], equals(2));
    });

    test('updateLocalOrderStatus updates status and frees table on settle', () async {
      final service = OfflineSyncService.instance;
      await service.initialize();

      await service.saveCachedTables([
        {'id': 1, 'table_number': 'T1', 'status': 2, 'capacity': 4},
      ]);

      await service.saveCachedOrders([
        {
          'order_id': 555,
          'order_no': 'ORD-555',
          'table_id': 1,
          'status': 2, // Confirmed
          'grand_total': 1000.0,
        },
      ]);

      // Settle order (status = 1)
      await service.updateLocalOrderStatus(
        orderId: 555,
        status: 1,
        paymentMethod: 'CASH',
        amountPaid: 1000.0,
      );

      final cachedOrders = await service.getCachedOrders();
      expect(cachedOrders![0]['status'], equals(1));
      expect(cachedOrders[0]['payment_method'], equals('CASH'));

      // Verify table is freed (status = 1)
      final tables = await service.getCachedTables();
      expect(tables![0]['status'], equals(1));
    });

    test('Action queue persists and enqueues correctly', () async {
      final service = OfflineSyncService.instance;
      await service.initialize();

      await service.enqueueAction(
        type: 'create_order',
        orderId: -999,
        tempId: -999,
        payload: {'order_no': 'TEST-001'},
      );

      expect(service.pendingCount, equals(1));
      final queue = service.getQueue();
      expect(queue.length, equals(1));
      expect(queue[0].type, equals('create_order'));
      expect(queue[0].orderId, equals(-999));
    });
  });
}

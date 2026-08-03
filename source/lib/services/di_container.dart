import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'openwrt_service.dart';
import 'storage_service.dart';
import '../models/router_connection.dart';

final sl = GetIt.instance;

Future<void> setupDi() async {
  final prefs = await SharedPreferences.getInstance();
  sl.registerLazySingleton<SharedPreferences>(() => prefs);
}

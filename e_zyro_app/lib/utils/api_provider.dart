import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

Future<ApiService> getApiService() async {
  final prefs = await SharedPreferences.getInstance();
  return ApiService(prefs);
}

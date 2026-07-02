import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/app_constants.dart';
import '../models/chat_models.dart';

class ChatService {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  final _mensajesCtrl = StreamController<MensajeChat>.broadcast();
  final _historialCtrl = StreamController<List<MensajeChat>>.broadcast();
  final _connectedCtrl = StreamController<bool>.broadcast();

  /// Eventos de control del servidor (no son chat): p. ej.
  /// 'borrador_actualizado', 'requerimiento_actualizado'. Permiten refrescar
  /// el borrador / la recepción en tiempo real desde el detalle del servicio.
  final _eventosCtrl = StreamController<String>.broadcast();
  Stream<String> get eventos => _eventosCtrl.stream;

  bool _isConnected = false;
  bool _disposed = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  // room puede ser "{proyectoId}" o "servicio/{servicioId}"
  String? _room;
  String? _token;

  Stream<MensajeChat> get mensajes => _mensajesCtrl.stream;
  Stream<List<MensajeChat>> get historial => _historialCtrl.stream;
  Stream<bool> get connectionStatus => _connectedCtrl.stream;
  bool get isConnected => _isConnected;

  static const _maxReconnects = 5;
  static const _delays = [1, 3, 5, 10, 20];

  void connect(String room, String token) {
    _room = room;
    _token = token;
    _reconnectAttempts = 0;
    _doConnect();
  }

  void _doConnect() {
    if (_disposed || _room == null) return;

    _sub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}

    final wsBase = AppConstants.baseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');

    final uri = Uri.parse('$wsBase/ws/chat/$_room?token=$_token');

    try {
      _channel = WebSocketChannel.connect(uri);
      _sub = _channel!.stream.listen(
        _onData,
        onError: (_) => _onDisconnected(),
        onDone: _onDisconnected,
        cancelOnError: false,
      );
      _setConnected(true);
    } catch (_) {
      _onDisconnected();
    }
  }

  void _onData(dynamic raw) {
    if (_disposed) return;
    try {
      final decoded = jsonDecode(raw as String) as Map<String, dynamic>;

      // El backend envía un paquete inicial con el historial completo
      if (decoded['tipo'] == 'historial') {
        final lista = (decoded['mensajes'] as List? ?? [])
            .map((m) => MensajeChat.fromJson(m as Map<String, dynamic>))
            .toList();
        if (!_historialCtrl.isClosed) _historialCtrl.add(lista);
        return;
      }

      if (decoded['tipo'] == 'error') return;

      // Eventos de control del servidor (no son mensajes de chat).
      final tipo = decoded['tipo'] as String?;
      if (tipo == 'borrador_actualizado' ||
          tipo == 'requerimiento_actualizado' ||
          tipo == 'servicio_completado_retorno') {
        if (!_eventosCtrl.isClosed) _eventosCtrl.add(tipo!);
        return;
      }

      final msg = MensajeChat.fromJson(decoded);
      if (!_mensajesCtrl.isClosed) _mensajesCtrl.add(msg);
    } catch (_) {}
  }

  void _onDisconnected() {
    if (_disposed) return;
    _setConnected(false);
    if (_reconnectAttempts < _maxReconnects) {
      final delay = _delays[_reconnectAttempts];
      _reconnectAttempts++;
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(Duration(seconds: delay), _doConnect);
    }
  }

  void _setConnected(bool value) {
    if (_isConnected == value) return;
    _isConnected = value;
    if (!_connectedCtrl.isClosed) _connectedCtrl.add(value);
  }

  void send(String texto, {String? destinatarioId}) {
    final t = texto.trim();
    if (!_isConnected || _channel == null || t.isEmpty) return;
    try {
      _channel!.sink.add(jsonEncode({
        'contenido': t,
        'destinatario_id': destinatarioId,
      }));
    } catch (_) {}
  }

  void reconnect() {
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _doConnect();
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _mensajesCtrl.close();
    _historialCtrl.close();
    _connectedCtrl.close();
    _eventosCtrl.close();
  }
}

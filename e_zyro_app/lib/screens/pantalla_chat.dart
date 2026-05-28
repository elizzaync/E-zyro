import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_models.dart';
import '../services/chat_service.dart';

class ChatTab extends StatefulWidget {
  /// room puede ser "{proyectoId}" o "servicio/{servicioId}"
  final String room;

  /// Mapa de userId → fotoUrl para mostrar avatares del equipo.
  /// El backend no envía la foto en el WS, así que se resuelve localmente.
  final Map<String, String> fotosPorId;

  const ChatTab({super.key, required this.room, this.fotosPorId = const {}});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _service = ChatService();
  final _mensajes = <MensajeChat>[];
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  bool _isConnected = false;
  bool _showFab = false;
  String _myId = ''; // UUID del usuario actual (del JWT)
  String _myName = ''; // nombre para fallback

  StreamSubscription<MensajeChat>? _msgSub;
  StreamSubscription<List<MensajeChat>>? _histSub;
  StreamSubscription<bool>? _connSub;

  static const _green = Color(0xFF8FD11B);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollCtrl.addListener(_onScroll);
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _myName = prefs.getString('user_name') ?? '';
    final token = prefs.getString('auth_token') ?? '';
    _myId = _extractIdFromToken(token);

    _connSub = _service.connectionStatus.listen((connected) {
      if (!mounted) return;
      setState(() => _isConnected = connected);
    });

    // Historial: reemplaza la lista completa de una vez
    _histSub = _service.historial.listen((msgs) {
      if (!mounted) return;
      setState(() {
        _mensajes.clear();
        _mensajes.addAll(msgs);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    });

    // Mensajes nuevos en tiempo real
    _msgSub = _service.mensajes.listen((msg) {
      if (!mounted) return;
      setState(() => _mensajes.add(msg));
      _maybeScrollToBottom();
    });

    _service.connect(widget.room, token);
  }

  /// Extrae el campo 'id' del payload JWT sin verificar firma.
  String _extractIdFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return '';
      final payload = parts[1];
      final padded = payload.padRight((payload.length + 3) & ~3, '=');
      final decoded = utf8.decode(base64.decode(padded));
      final json = jsonDecode(decoded) as Map<String, dynamic>;
      return json['id'] as String? ?? json['sub'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    final atBottom = pos.maxScrollExtent - pos.pixels < 150;
    if (!atBottom != _showFab) setState(() => _showFab = !atBottom);
  }

  /// Scrolls to bottom only if the user is already near the bottom.
  void _maybeScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      final pos = _scrollCtrl.position;
      if (pos.maxScrollExtent - pos.pixels < 200) {
        _scrollCtrl.animateTo(
          pos.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _sendMessage() {
    final texto = _inputCtrl.text.trim();
    if (texto.isEmpty || !_isConnected) return;
    _service.send(texto);
    _inputCtrl.clear();
    // Scroll to bottom after send regardless of position
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isConnected) {
      _service.reconnect();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollCtrl.removeListener(_onScroll);
    _msgSub?.cancel();
    _histSub?.cancel();
    _connSub?.cancel();
    _service.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // ── Barra de estado de conexión ────────────────────────────────────
        _ConnectionBar(
          isConnected: _isConnected,
          onReconnect: _service.reconnect,
        ),

        // ── Lista de mensajes ──────────────────────────────────────────────
        Expanded(
          child: _mensajes.isEmpty
              ? _EmptyState(isConnected: _isConnected)
              : Stack(
                  children: [
                    ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      itemCount: _mensajes.length,
                      itemBuilder: (_, i) {
                        final msg = _mensajes[i];
                        final isMine =
                            msg.tipo == TipoMensaje.mensaje &&
                            (_myId.isNotEmpty
                                ? msg.remitenteId == _myId
                                : msg.autor == _myName);

                        // Show author header only on first message of a group
                        final showAuthor =
                            !isMine &&
                            msg.tipo == TipoMensaje.mensaje &&
                            (i == 0 ||
                                _mensajes[i - 1].autor != msg.autor ||
                                _mensajes[i - 1].tipo == TipoMensaje.sistema);

                        // Show date separator when day changes
                        final showDate =
                            i == 0 ||
                            !_sameDay(_mensajes[i - 1].fecha, msg.fecha);

                        // Resuelve la foto: primero del WS, luego del mapa de equipo
                        final fotoUrl = (msg.fotoUrl?.isNotEmpty == true)
                            ? msg.fotoUrl
                            : (msg.remitenteId != null
                                  ? widget.fotosPorId[msg.remitenteId!]
                                  : null);

                        return Column(
                          children: [
                            if (showDate) _DateChip(fecha: msg.fecha),
                            _MessageBubble(
                              msg: msg,
                              isMine: isMine,
                              showAuthor: showAuthor,
                              isDark: isDark,
                              fotoUrl: fotoUrl,
                            ),
                          ],
                        );
                      },
                    ),

                    // FAB para bajar al final
                    if (_showFab)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: FloatingActionButton.small(
                          heroTag: 'chat_scroll_fab_${widget.room}',
                          onPressed: _scrollToBottom,
                          backgroundColor: _green,
                          foregroundColor: Colors.black,
                          elevation: 4,
                          child: const Icon(Icons.arrow_downward, size: 18),
                        ),
                      ),
                  ],
                ),
        ),

        // ── Barra de entrada ───────────────────────────────────────────────
        _InputBar(
          controller: _inputCtrl,
          isConnected: _isConnected,
          isDark: isDark,
          onSend: _sendMessage,
        ),
      ],
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ─── Barra de estado de conexión ─────────────────────────────────────────────

class _ConnectionBar extends StatelessWidget {
  final bool isConnected;
  final VoidCallback onReconnect;

  const _ConnectionBar({required this.isConnected, required this.onReconnect});

  static const _green = Color(0xFF8FD11B);
  static const _amber = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: isConnected
          ? _green.withValues(alpha: isDark ? 0.12 : 0.08)
          : _amber.withValues(alpha: isDark ? 0.15 : 0.10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isConnected ? _green : _amber,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isConnected
                  ? 'Chat en tiempo real activo'
                  : 'Sin conexión — reconectando…',
              style: TextStyle(
                fontSize: 12,
                color: isConnected ? _green : _amber,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (!isConnected)
            TextButton(
              onPressed: onReconnect,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Reconectar',
                style: TextStyle(
                  color: _amber,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Separador de fecha ───────────────────────────────────────────────────────

class _DateChip extends StatelessWidget {
  final DateTime fecha;
  const _DateChip({required this.fecha});

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(fecha.year, fecha.month, fecha.day);
    if (day == today) return 'Hoy';
    if (day == today.subtract(const Duration(days: 1))) return 'Ayer';
    return DateFormat('d MMM yyyy', 'es').format(fecha);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _label(),
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Burbuja de mensaje ───────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final MensajeChat msg;
  final bool isMine;
  final bool showAuthor;
  final bool isDark;
  final String? fotoUrl;

  const _MessageBubble({
    required this.msg,
    required this.isMine,
    required this.showAuthor,
    required this.isDark,
    this.fotoUrl,
  });

  static const _green = Color(0xFF8FD11B);

  @override
  Widget build(BuildContext context) {
    // Sistema: mensaje centrado
    if (msg.tipo == TipoMensaje.sistema) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              msg.texto,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(top: showAuthor ? 8 : 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          // Avatar (only for others)
          if (!isMine)
            Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 2),
              child: showAuthor
                  ? _Avatar(name: msg.autor, fotoUrl: fotoUrl)
                  : const SizedBox(width: 28),
            ),

          // Bubble
          Flexible(
            child: Column(
              crossAxisAlignment: isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (showAuthor && !isMine)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 3),
                    child: Text(
                      msg.autor,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _avatarColor(msg.autor),
                      ),
                    ),
                  ),
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isMine
                        ? _green
                        : isDark
                        ? Colors.grey.shade800
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMine ? 16 : 4),
                      bottomRight: Radius.circular(isMine ? 4 : 16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        msg.texto,
                        style: TextStyle(
                          fontSize: 14,
                          color: isMine
                              ? Colors.black
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('HH:mm').format(msg.fecha),
                        style: TextStyle(
                          fontSize: 10,
                          color: isMine ? Colors.black54 : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _avatarColor(String name) {
    const palette = [
      Color(0xFF3B82F6), // blue
      Color(0xFF8B5CF6), // purple
      Color(0xFFF59E0B), // amber
      Color(0xFF10B981), // emerald
      Color(0xFFEF4444), // red
      Color(0xFF06B6D4), // cyan
      Color(0xFFF97316), // orange
      Color(0xFFEC4899), // pink
    ];
    return palette[name.hashCode.abs() % palette.length];
  }
}

// ─── Avatar con foto o inicial ────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String name;
  final String? fotoUrl;
  const _Avatar({required this.name, this.fotoUrl});

  Color get _color {
    const palette = [
      Color(0xFF3B82F6),
      Color(0xFF8B5CF6),
      Color(0xFFF59E0B),
      Color(0xFF10B981),
      Color(0xFFEF4444),
      Color(0xFF06B6D4),
      Color(0xFFF97316),
      Color(0xFFEC4899),
    ];
    return palette[name.hashCode.abs() % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    if (fotoUrl != null && fotoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 14,
        backgroundColor: _color.withValues(alpha: 0.15),
        backgroundImage: CachedNetworkImageProvider(fotoUrl!),
        onBackgroundImageError: (_, _) {},
      );
    }
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: 14,
      backgroundColor: _color.withValues(alpha: 0.20),
      child: Text(
        initial,
        style: TextStyle(
          color: _color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ─── Barra de entrada de texto ────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isConnected;
  final bool isDark;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.isConnected,
    required this.isDark,
    required this.onSend,
  });

  static const _green = Color(0xFF8FD11B);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Campo de texto
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: controller,
                  enabled: isConnected,
                  maxLines: 4,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: isConnected
                        ? 'Escribe un mensaje…'
                        : 'Sin conexión',
                    hintStyle: const TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Botón enviar
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isConnected
                    ? _green
                    : Colors.grey.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: isConnected ? onSend : null,
                icon: const Icon(Icons.send_rounded, size: 20),
                color: isConnected ? Colors.black : Colors.grey,
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Estado vacío ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool isConnected;
  const _EmptyState({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isConnected ? Icons.chat_bubble_outline : Icons.wifi_off_outlined,
            size: 52,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            isConnected
                ? 'No hay mensajes aún.\n¡Sé el primero en escribir!'
                : 'Conectando al chat…',
            style: const TextStyle(color: Colors.grey, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          if (!isConnected) ...[
            const SizedBox(height: 16),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Color(0xFF8FD11B)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

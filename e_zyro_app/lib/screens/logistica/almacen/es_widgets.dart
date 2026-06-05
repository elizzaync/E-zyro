// es_widgets.dart — widgets Style-E reutilizables para el panel de Almacén.
// Portado del prototipo; `withOpacity` → `withValues(alpha:)` para el linter.

import 'package:flutter/material.dart';
import 'es_tokens.dart';

// ── Icon mapping (Material icons en el estilo de marca) ──────────────────────
class ESIcons {
  static const box     = Icons.inventory_2_outlined;     // Material
  static const wrench  = Icons.handyman_outlined;        // Equipo
  static const cart    = Icons.shopping_cart_outlined;   // Compra
  static const stock   = Icons.warehouse_outlined;
  static const clock   = Icons.schedule;
  static const check   = Icons.check_rounded;
  static const alert   = Icons.warning_amber_rounded;
  static const undo    = Icons.undo_rounded;
  static const filter  = Icons.tune_rounded;
  static const back    = Icons.arrow_back_rounded;
  static const pin     = Icons.place_outlined;
  static const truck   = Icons.local_shipping_outlined;
  static const link    = Icons.link_rounded;
  static const search  = Icons.search_rounded;
  static const arrow   = Icons.arrow_forward_rounded;
  static const bell    = Icons.notifications_none_rounded;
}

// ── Tarjeta tonal / neutra ───────────────────────────────────────────────────
class ESCard extends StatelessWidget {
  final Widget child;
  final Color? accent;       // si se pasa → contenedor tonal de ese color
  final EdgeInsetsGeometry padding;
  const ESCard({super.key, required this.child, this.accent, this.padding = const EdgeInsets.all(14)});

  @override
  Widget build(BuildContext context) {
    final tonal = accent != null;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tonal ? esTint(accent!, 0.09) : ESC.surface,
        borderRadius: BorderRadius.circular(ESC.radius),
        border: tonal ? null : Border.all(color: ESC.line),
        boxShadow: tonal ? null : [
          BoxShadow(color: const Color(0xFF1A2912).withValues(alpha: 0.05), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: child,
    );
  }
}

// ── Status pill ──────────────────────────────────────────────────────────────
class StatusPill extends StatelessWidget {
  final String status;
  const StatusPill(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = esStatusColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(999)),
      child: Text(status, style: pj(size: 11.5, weight: FontWeight.w700, color: c.fg, spacing: 0.1)),
    );
  }
}

// ── Type badge (Material / Equipo) ───────────────────────────────────────────
class TypeBadge extends StatelessWidget {
  final String type; // 'Material' | 'Equipo'
  const TypeBadge(this.type, {super.key});
  @override
  Widget build(BuildContext context) {
    final isMat = type == 'Material';
    final fg = isMat ? ESC.brandDeep : ESC.equip;
    final bg = isMat ? ESC.matBg : ESC.equipBg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(isMat ? ESIcons.box : ESIcons.wrench, size: 14, color: fg),
        const SizedBox(width: 5),
        Text(type, style: pj(size: 11.5, weight: FontWeight.w700, color: fg)),
      ]),
    );
  }
}

// ── Stock chip ───────────────────────────────────────────────────────────────
class StockChip extends StatelessWidget {
  final bool ok;
  const StockChip(this.ok, {super.key});
  @override
  Widget build(BuildContext context) {
    final fg = ok ? ESC.stock : ESC.nostock;
    final bg = ok ? ESC.stockBg : ESC.nostockBg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(7)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ok ? ESIcons.check : ESIcons.cart, size: 12, color: fg),
        const SizedBox(width: 4),
        Text(ok ? 'En stock' : 'Req. compra', style: pj(size: 10.5, weight: FontWeight.w700, color: fg)),
      ]),
    );
  }
}

// ── Segmented control (≤3 opciones) ──────────────────────────────────────────
class ESSeg {
  final String label;
  final IconData? icon;
  final int? count;
  final Color? color;
  const ESSeg(this.label, {this.icon, this.count, this.color});
}

class ESSegmented extends StatelessWidget {
  final List<ESSeg> items;
  final int selected;
  final ValueChanged<int>? onChanged;
  const ESSegmented({super.key, required this.items, this.selected = 0, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFFE3ECD3), borderRadius: BorderRadius.circular(999)),
      child: Row(children: [
        for (int i = 0; i < items.length; i++)
          Expanded(child: _seg(items[i], i == selected, () => onChanged?.call(i))),
      ]),
    );
  }

  Widget _seg(ESSeg it, bool on, VoidCallback tap) {
    final accent = it.color ?? ESC.brandDeep;
    return GestureDetector(
      onTap: tap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: on ? ESC.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: on ? [BoxShadow(color: const Color(0xFF1A2912).withValues(alpha: 0.10), blurRadius: 6, offset: const Offset(0, 2))] : null,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
          if (it.icon != null) ...[Icon(it.icon, size: 15, color: on ? accent : ESC.inkSub), const SizedBox(width: 5)],
          Flexible(child: Text(it.label, overflow: TextOverflow.ellipsis, style: pj(size: 13, weight: FontWeight.w700, color: on ? accent : ESC.inkSub))),
          if (it.count != null) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: on ? esTint(accent, 0.14) : const Color(0x0F1A2912), borderRadius: BorderRadius.circular(999)),
              child: Text('${it.count}', style: pj(size: 11, weight: FontWeight.w700, color: on ? accent : ESC.inkSub)),
            ),
          ],
        ]),
      ),
    );
  }
}

// ── Pestañas pill deslizables (4+ opciones) ──────────────────────────────────
class ESPills extends StatelessWidget {
  final List<String> items;
  final int selected;
  final ValueChanged<int>? onChanged;
  const ESPills({super.key, required this.items, this.selected = 0, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final on = i == selected;
          return GestureDetector(
            onTap: () => onChanged?.call(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? ESC.brand : ESC.surface,
                borderRadius: BorderRadius.circular(999),
                border: on ? null : Border.all(color: ESC.line, width: 1.5),
                boxShadow: on ? [BoxShadow(color: ESC.brand.withValues(alpha: 0.28), blurRadius: 12, offset: const Offset(0, 5))] : null,
              ),
              child: Text(items[i], style: pj(size: 13, weight: FontWeight.w700, color: on ? Colors.white : ESC.inkSub)),
            ),
          );
        },
      ),
    );
  }
}

// ── Avatar ───────────────────────────────────────────────────────────────────
class ESAvatar extends StatelessWidget {
  final String letter;
  final Color color;
  final double size;
  const ESAvatar(this.letter, {super.key, this.color = ESC.brandDeep, this.size = 28});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(color: esTint(color, 0.16), borderRadius: BorderRadius.circular(size > 32 ? 12 : 9)),
      alignment: Alignment.center,
      child: Text(letter, style: pj(size: size * 0.4, weight: FontWeight.w800, color: color)),
    );
  }
}

// ── Progress bar ─────────────────────────────────────────────────────────────
class ESProgress extends StatelessWidget {
  final int value, max;
  final Color color;
  const ESProgress({super.key, required this.value, required this.max, this.color = ESC.brand});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: max == 0 ? 0 : value / max, minHeight: 7,
            backgroundColor: ESC.matBg, valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Text('$value/$max', style: pj(size: 12, weight: FontWeight.w700, color: ESC.inkSub)),
    ]);
  }
}

// ── Botón ────────────────────────────────────────────────────────────────────
enum ESBtnKind { primary, secondary, soft, danger }

class ESButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final ESBtnKind kind;
  final Color? color;
  final bool expand;
  final VoidCallback? onTap;
  const ESButton(this.label, {super.key, this.icon, this.kind = ESBtnKind.primary, this.color, this.expand = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = color ?? ESC.brand;
    late Color bg, fg; Border? border; List<BoxShadow>? shadow;
    switch (kind) {
      case ESBtnKind.primary:
        bg = accent; fg = Colors.white;
        shadow = [BoxShadow(color: accent.withValues(alpha: 0.32), blurRadius: 18, offset: const Offset(0, 8))];
        break;
      case ESBtnKind.secondary:
        bg = ESC.surface; fg = ESC.ink; border = Border.all(color: ESC.lineStrong, width: 1.5);
        break;
      case ESBtnKind.soft:
        bg = esTint(accent, 0.14); fg = accent;
        break;
      case ESBtnKind.danger:
        bg = ESC.surface; fg = ESC.vencido; border = Border.all(color: ESC.vencido.withValues(alpha: 0.4), width: 1.5);
        break;
    }
    final btn = GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: border, boxShadow: shadow),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 8)],
          Text(label, style: pj(size: 15, weight: FontWeight.w700, color: fg)),
        ]),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

// ── Barra superior del panel (back + título + trailing) — sin bottom nav ─────
class ESPanelBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool back;
  final Widget? trailing;
  const ESPanelBar({super.key, required this.title, this.subtitle, this.back = true, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(color: ESC.surface, border: Border(bottom: BorderSide(color: ESC.line))),
      child: SafeArea(
        bottom: false,
        child: Row(children: [
          if (back) ...[
            _roundBtn(context, ESIcons.back, () => Navigator.maybePop(context)),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: pj(size: 19, weight: FontWeight.w800, color: ESC.ink, spacing: -0.4)),
              if (subtitle != null) Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(subtitle!, style: pj(size: 12, weight: FontWeight.w500, color: ESC.inkSub)),
              ),
            ]),
          ),
          ?trailing,
        ]),
      ),
    );
  }

  static Widget _roundBtn(BuildContext context, IconData ic, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(width: 38, height: 38, decoration: BoxDecoration(color: ESC.bg, borderRadius: BorderRadius.circular(12)), child: Icon(ic, size: 19, color: ESC.ink)),
  );
}

// Etiqueta de sección pequeña (uppercase)
class ESSectionLabel extends StatelessWidget {
  final String text;
  final String? action;
  const ESSectionLabel(this.text, {super.key, this.action});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(text.toUpperCase(), style: pj(size: 12, weight: FontWeight.w700, color: ESC.inkFaint, spacing: 1.1)),
        if (action != null) Text(action!, style: pj(size: 13, weight: FontWeight.w600, color: ESC.brandDeep)),
      ]),
    );
  }
}

// Botón redondo trailing para la barra superior
class ESBarIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const ESBarIcon(this.icon, {super.key, this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(width: 38, height: 38, decoration: BoxDecoration(color: ESC.bg, borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 18, color: ESC.ink)),
  );
}

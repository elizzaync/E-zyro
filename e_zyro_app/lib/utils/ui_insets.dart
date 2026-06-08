import 'package:flutter/material.dart';

/// Padding inferior que suma el inset de la barra de navegación / gestos del
/// sistema (`MediaQuery.viewPaddingOf(context).bottom`) a un margen propio de
/// la pantalla, para que el contenido (listas, FABs, botones de acción) no
/// quede tapado por la barra del sistema en dispositivos con gestos o nav bar.
double bottomSafeInset(BuildContext context, [double extra = 16]) =>
    extra + MediaQuery.viewPaddingOf(context).bottom;

/// Atajo para usar directamente como `padding` de un `ListView`/`Column` cuyo
/// último elemento puede quedar tapado por la barra de navegación del sistema.
EdgeInsets bottomSafePadding(BuildContext context,
        {double left = 16, double top = 16, double right = 16, double extra = 16}) =>
    EdgeInsets.fromLTRB(left, top, right, bottomSafeInset(context, extra));

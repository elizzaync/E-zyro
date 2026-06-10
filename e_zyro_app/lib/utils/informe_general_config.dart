/// Diccionarios de precarga del modal "Generar Informe" (Informe General de
/// Pozos a Tierra). Port 1:1 de `informe-general.config.ts` del frontend
/// Angular (a su vez migrado del PHP heredado): EPPS_CONFIG, MATERIALES_CONFIG,
/// HERRAMIENTAS_CONFIG y `determinarTipoBase`.
///
/// Los DEFAULTS por tipo de equipo viven aquí (cliente); el backend solo aporta
/// lo realmente solicitado/retirado del servicio. El merge (sin duplicados por
/// nombre) se hace en la UI, igual que en Angular.
library;

import '../models/intervencion_models.dart';

/// Tipo base del informe según los equipos seleccionados.
enum TipoBaseInforme { tableros, pozos, ups, otro }

extension TipoBaseInformeApi on TipoBaseInforme {
  /// Valor exacto que espera el backend en `tipo_base`.
  String get api => switch (this) {
        TipoBaseInforme.tableros => 'TABLEROS',
        TipoBaseInforme.pozos => 'POZOS',
        TipoBaseInforme.ups => 'UPS',
        TipoBaseInforme.otro => 'OTRO',
      };
}

/// Réplica de la lógica del frontend: si algún tipo contiene TABLERO/POZO/UPS
/// (o TRANS. AISLAMIENTO → UPS) lo usa; en caso contrario cae a OTRO.
TipoBaseInforme determinarTipoBase(Iterable<String?> tipos) {
  for (final t in tipos.map((t) => (t ?? '').toUpperCase())) {
    if (t.contains('TABLERO')) return TipoBaseInforme.tableros;
    if (t.contains('POZO')) return TipoBaseInforme.pozos;
    if (t.contains('UPS') || t.contains('TRANS. AISLAMIENTO')) {
      return TipoBaseInforme.ups;
    }
  }
  return TipoBaseInforme.otro;
}

const Map<TipoBaseInforme, List<String>> kEppsConfig = {
  TipoBaseInforme.tableros: [
    'CASCO DE SEGURIDAD',
    'LENTES DE SEGURIDAD',
    'BOTAS DE SEGURIDAD',
    'PROTECTORES DE OIDO',
    'CHALECOS DE SEGURIDAD',
  ],
  TipoBaseInforme.pozos: [
    'CASCO DE SEGURIDAD',
    'LENTES DE SEGURIDAD',
    'BOTAS DE SEGURIDAD',
    'PROTECTORES DE OIDO',
    'CHALECOS DE SEGURIDAD',
  ],
  TipoBaseInforme.ups: [
    'CASCO DE SEGURIDAD',
    'LENTES DE SEGURIDAD',
    'BOTAS DE SEGURIDAD',
    'PROTECTORES DE OIDO',
    'CHALECOS DE SEGURIDAD',
  ],
  TipoBaseInforme.otro: [
    'CASCO DE SEGURIDAD',
    'CARETA DIELÉCTRICA',
    'LENTES DE SEGURIDAD',
    'BOTAS DE SEGURIDAD',
    'CHALECOS DE SEGURIDAD',
    'GUANTES DIELÉCTRICOS',
  ],
};

const Map<TipoBaseInforme, List<MaterialInforme>> kMaterialesConfig = {
  TipoBaseInforme.tableros: [
    MaterialInforme(nombre: 'SOLVENTE DIELÉCTRICO', unidad: 'Ud.'),
    MaterialInforme(nombre: 'CREMA LIMPIADORA', unidad: 'Ud.'),
    MaterialInforme(nombre: 'TRAPO INDUSTRIAL', unidad: 'Ud.'),
    MaterialInforme(nombre: 'SEÑALÉTICAS', unidad: 'Ud.'),
    MaterialInforme(nombre: 'BROCHA', unidad: 'Ud.'),
    MaterialInforme(nombre: 'TERMINALES', unidad: 'Ud.'),
  ],
  TipoBaseInforme.pozos: [
    MaterialInforme(nombre: 'PINTURA TRÁFICO AMARILLA', unidad: 'Ud.'),
    MaterialInforme(nombre: 'SPRAY NEGRO', unidad: 'Ud.'),
    MaterialInforme(nombre: 'LIJA', unidad: 'Ud.'),
    MaterialInforme(nombre: 'THOR GEL', unidad: 'Ud.'),
    MaterialInforme(nombre: 'TRAPO INDUSTRIAL', unidad: 'Ud.'),
    MaterialInforme(nombre: 'SEÑALÉTICA', unidad: 'Ud.'),
    MaterialInforme(nombre: 'THINNER', unidad: 'Ud.'),
  ],
  TipoBaseInforme.ups: [
    MaterialInforme(nombre: 'SOLVENTE DIELÉCTRICO', unidad: 'Ud.'),
    MaterialInforme(nombre: 'CREMA LIMPIADORA', unidad: 'Ud.'),
    MaterialInforme(nombre: 'TRAPO INDUSTRIAL', unidad: 'Ud.'),
  ],
  TipoBaseInforme.otro: [
    MaterialInforme(nombre: 'SOLVENTE DIELÉCTRICO', unidad: 'GLN.'),
    MaterialInforme(nombre: 'CREMA LIMPIADORA', unidad: 'UND.'),
    MaterialInforme(nombre: 'TAPAS DE RESERVA', unidad: 'UND.'),
    MaterialInforme(nombre: 'CINTILLOS', unidad: 'UND.'),
    MaterialInforme(nombre: 'BROCHA', unidad: 'UND.'),
    MaterialInforme(nombre: 'TERMINALES', unidad: 'UND.'),
    MaterialInforme(nombre: 'SEÑALÉTICA', unidad: 'UND.'),
    MaterialInforme(nombre: 'PINTURA TRÁFICO AMARILLA', unidad: 'GLN.'),
    MaterialInforme(nombre: 'SPRITE NEGRO', unidad: 'UND.'),
    MaterialInforme(nombre: 'LIJAS', unidad: 'UND.'),
    MaterialInforme(nombre: 'THOR GEL', unidad: 'UND.'),
    MaterialInforme(nombre: 'CONECTOR TIERRA CABLE', unidad: 'UND.'),
    MaterialInforme(nombre: 'TRAPOS INDUSTRIALES', unidad: 'UND.'),
    MaterialInforme(nombre: 'THINER', unidad: 'GLN.'),
  ],
};

const Map<TipoBaseInforme, List<HerramientaInforme>> kHerramientasConfig = {
  TipoBaseInforme.tableros: [
    HerramientaInforme(nombre: 'JUEGO DE ALICATES', marca: 'Dieléctrico'),
    HerramientaInforme(nombre: 'JUEGO DE DESARMADORES', marca: 'Dieléctrico'),
    HerramientaInforme(nombre: 'BOLSA PORTAHERRAMIENTAS'),
    HerramientaInforme(nombre: 'MEGOHMETRO'),
    HerramientaInforme(nombre: 'PINZA AMPERIMÉTRICA'),
    HerramientaInforme(nombre: 'CÁMARA TERMOGRÁFICA'),
    HerramientaInforme(nombre: 'SOPLADOR DE AIRE'),
  ],
  TipoBaseInforme.pozos: [
    HerramientaInforme(nombre: 'JUEGO DE ALICATES', marca: 'Dieléctrico'),
    HerramientaInforme(nombre: 'JUEGO DE DESARMADORES', marca: 'Dieléctrico'),
    HerramientaInforme(nombre: 'BROCHA'),
    HerramientaInforme(nombre: 'LLAVES BOCA CORONA'),
    HerramientaInforme(nombre: 'CINCEL PLANO'),
    HerramientaInforme(nombre: 'LLAVE FRANCESA'),
    HerramientaInforme(nombre: 'BALDE'),
  ],
  TipoBaseInforme.ups: [
    HerramientaInforme(nombre: 'JUEGO DE ALICATES', marca: 'Dieléctrico'),
    HerramientaInforme(nombre: 'JUEGO DE DESARMADORES', marca: 'Dieléctrico'),
    HerramientaInforme(nombre: 'BROCHA'),
  ],
  TipoBaseInforme.otro: [
    HerramientaInforme(
        nombre: 'JUEGO DE DESARMADORES DIELÉCTRICOS',
        marca: 'Marca Stanley, 6 piezas'),
    HerramientaInforme(nombre: 'BOLSA PORTAHERRAMIENTAS'),
    HerramientaInforme(nombre: 'JUEGO DE ALICATES DIELÉCTRICOS'),
    HerramientaInforme(nombre: 'PINZA AMPERIMÉTRICA', marca: 'Marca FLUKE'),
    HerramientaInforme(nombre: 'CÁMARA TERMOGRÁFICA', marca: 'Marca FLUKE'),
    HerramientaInforme(nombre: 'SOPLADOR INALÁMBRICO', marca: 'Marca BOSCH'),
    HerramientaInforme(nombre: 'MEGÓHMETRO DIGITAL', marca: 'Marca SANWA'),
    HerramientaInforme(nombre: 'TELURÓMETRO', marca: 'Marca Kyoritsu'),
    HerramientaInforme(nombre: 'BROCHA', marca: 'Generico'),
    HerramientaInforme(nombre: 'LLAVES BOCA CORONA', marca: 'Marca Stanley'),
    HerramientaInforme(nombre: 'CINCEL PLANO'),
    HerramientaInforme(nombre: 'LLAVE FRANCESA'),
    HerramientaInforme(nombre: 'PATA DE CABRA'),
    HerramientaInforme(nombre: 'COMBA'),
    HerramientaInforme(nombre: 'BALDE'),
  ],
};

/// Mapa lugar → dirección de aeropuerto para la Carta de Garantía.
/// Réplica del diccionario `AEROPUERTOS` del componente Angular.
const Map<String, String> kAeropuertos = {
  'AREQUIPA': 'Aeropuerto Internacional Alfredo Rodríguez Ballón, Arequipa',
  'AYACUCHO': 'Aeropuerto Coronel FAP Alfredo Mendívil Duarte',
  'TRUJILLO':
      'Aeropuerto Internacional Capitán FAP Carlos Martínez de Pinillos',
  'LIMA': 'Aeropuerto Internacional Jorge Chávez, Lima',
  'CUSCO': 'Aeropuerto Internacional Alejandro Velasco Astete, Cusco',
  'PIURA':
      'Aeropuerto Internacional Capitán FAP Guillermo Concha Ibérico, Piura',
  'CHICLAYO':
      'Aeropuerto Internacional Capitán FAP José A. Quiñones Gonzales, Chiclayo',
  'IQU': 'Aeropuerto Internacional Coronel FAP Francisco Secada Vignetta, Iquitos',
  'IQUITOS':
      'Aeropuerto Internacional Coronel FAP Francisco Secada Vignetta, Iquitos',
  'PUCALLPA':
      'Aeropuerto Internacional Cap. FAP David Abensur Rengifo, Pucallpa',
  'JULIACA': 'Aeropuerto Internacional Inca Manco Cápac, Juliaca',
  'TACNA':
      'Aeropuerto Internacional Coronel FAP Carlos Ciriani Santa Rosa, Tacna',
  'TUMBES': 'Aeropuerto Internacional Pedro Canga Rodríguez, Tumbes',
};

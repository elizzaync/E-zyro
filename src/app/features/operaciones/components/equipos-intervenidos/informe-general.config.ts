/**
 * Diccionarios de precarga del modal "Generar Informe".
 * Migrados del PHP heredado (REPARACION.PHP): $eppsConfig, $materialesConfig,
 * $herramientasConfig y la lógica de `tipoBase`.
 *
 * Los DEFAULTS por tipo de equipo viven aquí (frontend); el backend solo aporta
 * lo realmente solicitado/retirado del servicio. El merge (sin duplicados) se
 * hace en el componente.
 */

export interface MaterialItem { nombre: string; unidad: string; caracteristicas: string; }
export interface HerramientaItem { serie: string; nombre: string; marca: string; }

export type TipoBase = 'TABLEROS' | 'POZOS' | 'UPS' | 'OTRO';

/**
 * Determina el tipo base a partir de los tipos de los equipos seleccionados.
 * Réplica de la lógica del PHP: si algún tipo contiene TABLERO/POZO/UPS lo usa,
 * en caso contrario cae a 'OTRO'.
 */
export function determinarTipoBase(tipos: (string | null | undefined)[]): TipoBase {
  const norm = tipos.map(t => (t ?? '').toUpperCase());
  for (const t of norm) {
    if (t.includes('TABLERO')) return 'TABLEROS';
    if (t.includes('POZO')) return 'POZOS';
    if (t.includes('UPS') || t.includes('TRANS. AISLAMIENTO')) return 'UPS';
  }
  return 'OTRO';
}

export const EPPS_CONFIG: Record<TipoBase, string[]> = {
  TABLEROS: ['CASCO DE SEGURIDAD', 'LENTES DE SEGURIDAD', 'BOTAS DE SEGURIDAD', 'PROTECTORES DE OIDO', 'CHALECOS DE SEGURIDAD'],
  POZOS:    ['CASCO DE SEGURIDAD', 'LENTES DE SEGURIDAD', 'BOTAS DE SEGURIDAD', 'PROTECTORES DE OIDO', 'CHALECOS DE SEGURIDAD'],
  UPS:      ['CASCO DE SEGURIDAD', 'LENTES DE SEGURIDAD', 'BOTAS DE SEGURIDAD', 'PROTECTORES DE OIDO', 'CHALECOS DE SEGURIDAD'],
  OTRO:     ['CASCO DE SEGURIDAD', 'CARETA DIELÉCTRICA', 'LENTES DE SEGURIDAD', 'BOTAS DE SEGURIDAD', 'CHALECOS DE SEGURIDAD', 'GUANTES DIELÉCTRICOS'],
};

export const MATERIALES_CONFIG: Record<TipoBase, MaterialItem[]> = {
  TABLEROS: [
    { nombre: 'SOLVENTE DIELÉCTRICO', unidad: 'Ud.', caracteristicas: '-' },
    { nombre: 'CREMA LIMPIADORA',     unidad: 'Ud.', caracteristicas: '-' },
    { nombre: 'TRAPO INDUSTRIAL',     unidad: 'Ud.', caracteristicas: '-' },
    { nombre: 'SEÑALÉTICAS',          unidad: 'Ud.', caracteristicas: '-' },
    { nombre: 'BROCHA',               unidad: 'Ud.', caracteristicas: '-' },
    { nombre: 'TERMINALES',           unidad: 'Ud.', caracteristicas: '-' },
  ],
  POZOS: [
    { nombre: 'PINTURA TRÁFICO AMARILLA', unidad: 'Ud.', caracteristicas: '-' },
    { nombre: 'SPRAY NEGRO',              unidad: 'Ud.', caracteristicas: '-' },
    { nombre: 'LIJA',                     unidad: 'Ud.', caracteristicas: '-' },
    { nombre: 'THOR GEL',                 unidad: 'Ud.', caracteristicas: '-' },
    { nombre: 'TRAPO INDUSTRIAL',         unidad: 'Ud.', caracteristicas: '-' },
    { nombre: 'SEÑALÉTICA',               unidad: 'Ud.', caracteristicas: '-' },
    { nombre: 'THINNER',                  unidad: 'Ud.', caracteristicas: '-' },
  ],
  UPS: [
    { nombre: 'SOLVENTE DIELÉCTRICO', unidad: 'Ud.', caracteristicas: '-' },
    { nombre: 'CREMA LIMPIADORA',     unidad: 'Ud.', caracteristicas: '-' },
    { nombre: 'TRAPO INDUSTRIAL',     unidad: 'Ud.', caracteristicas: '-' },
  ],
  OTRO: [
    { nombre: 'SOLVENTE DIELÉCTRICO',    unidad: 'GLN.', caracteristicas: '-' },
    { nombre: 'CREMA LIMPIADORA',        unidad: 'UND.', caracteristicas: '-' },
    { nombre: 'TAPAS DE RESERVA',        unidad: 'UND.', caracteristicas: '-' },
    { nombre: 'CINTILLOS',               unidad: 'UND.', caracteristicas: '-' },
    { nombre: 'BROCHA',                  unidad: 'UND.', caracteristicas: '-' },
    { nombre: 'TERMINALES',              unidad: 'UND.', caracteristicas: '-' },
    { nombre: 'SEÑALÉTICA',              unidad: 'UND.', caracteristicas: '-' },
    { nombre: 'PINTURA TRÁFICO AMARILLA', unidad: 'GLN.', caracteristicas: '-' },
    { nombre: 'SPRITE NEGRO',            unidad: 'UND.', caracteristicas: '-' },
    { nombre: 'LIJAS',                   unidad: 'UND.', caracteristicas: '-' },
    { nombre: 'THOR GEL',                unidad: 'UND.', caracteristicas: '-' },
    { nombre: 'CONECTOR TIERRA CABLE',   unidad: 'UND.', caracteristicas: '-' },
    { nombre: 'TRAPOS INDUSTRIALES',     unidad: 'UND.', caracteristicas: '-' },
    { nombre: 'THINER',                  unidad: 'GLN.', caracteristicas: '-' },
  ],
};

export const HERRAMIENTAS_CONFIG: Record<TipoBase, HerramientaItem[]> = {
  TABLEROS: [
    { serie: '-', nombre: 'JUEGO DE ALICATES',       marca: 'Dieléctrico' },
    { serie: '-', nombre: 'JUEGO DE DESARMADORES',   marca: 'Dieléctrico' },
    { serie: '-', nombre: 'BOLSA PORTAHERRAMIENTAS', marca: '-' },
    { serie: '-', nombre: 'MEGOHMETRO',              marca: '-' },
    { serie: '-', nombre: 'PINZA AMPERIMÉTRICA',     marca: '-' },
    { serie: '-', nombre: 'CÁMARA TERMOGRÁFICA',     marca: '-' },
    { serie: '-', nombre: 'SOPLADOR DE AIRE',        marca: '-' },
  ],
  POZOS: [
    { serie: '-', nombre: 'JUEGO DE ALICATES',     marca: 'Dieléctrico' },
    { serie: '-', nombre: 'JUEGO DE DESARMADORES', marca: 'Dieléctrico' },
    { serie: '-', nombre: 'BROCHA',                marca: '-' },
    { serie: '-', nombre: 'LLAVES BOCA CORONA',    marca: '-' },
    { serie: '-', nombre: 'CINCEL PLANO',          marca: '-' },
    { serie: '-', nombre: 'LLAVE FRANCESA',        marca: '-' },
    { serie: '-', nombre: 'BALDE',                 marca: '-' },
  ],
  UPS: [
    { serie: '-', nombre: 'JUEGO DE ALICATES',     marca: 'Dieléctrico' },
    { serie: '-', nombre: 'JUEGO DE DESARMADORES', marca: 'Dieléctrico' },
    { serie: '-', nombre: 'BROCHA',                marca: '-' },
  ],
  OTRO: [
    { serie: '-', nombre: 'JUEGO DE DESARMADORES DIELÉCTRICOS', marca: 'Marca Stanley, 6 piezas' },
    { serie: '-', nombre: 'BOLSA PORTAHERRAMIENTAS',           marca: '-' },
    { serie: '-', nombre: 'JUEGO DE ALICATES DIELÉCTRICOS',    marca: '-' },
    { serie: '-', nombre: 'PINZA AMPERIMÉTRICA',               marca: 'Marca FLUKE' },
    { serie: '-', nombre: 'CÁMARA TERMOGRÁFICA',               marca: 'Marca FLUKE' },
    { serie: '-', nombre: 'SOPLADOR INALÁMBRICO',              marca: 'Marca BOSCH' },
    { serie: '-', nombre: 'MEGÓHMETRO DIGITAL',                marca: 'Marca SANWA' },
    { serie: '-', nombre: 'TELURÓMETRO',                       marca: 'Marca Kyoritsu' },
    { serie: '-', nombre: 'BROCHA',                            marca: 'Generico' },
    { serie: '-', nombre: 'LLAVES BOCA CORONA',                marca: 'Marca Stanley' },
    { serie: '-', nombre: 'CINCEL PLANO',                      marca: '-' },
    { serie: '-', nombre: 'LLAVE FRANCESA',                    marca: '-' },
    { serie: '-', nombre: 'PATA DE CABRA',                     marca: '-' },
    { serie: '-', nombre: 'COMBA',                             marca: '-' },
    { serie: '-', nombre: 'BALDE',                             marca: '-' },
  ],
};

<?php
ini_set('display_errors', 1);
error_reporting(E_ALL);

if ($_SERVER['REQUEST_METHOD'] == 'GET') {

    require_once __DIR__ . "/../../../../src/Database/Conexion.php";
    require_once __DIR__ . "/../../../../src/Models/EmpresasSolicitantes.php";
    require_once __DIR__ . "/../../../../src/Models/Empleado.php";
    require_once __DIR__ . "/../../../../src/Models/Articulos.php";

    $c = new conectar();
    $conexion = $c->conexion();
    $claseEmpresa = new empresa();
    $tableros = array_filter(array_map('intval', explode(',', $_GET['tableros'] ?? '')));
    $ids = implode(',', $tableros);

    $result          = mysqli_query($conexion, "SELECT id_equipo, nombre_equipo, descripcion, tipo_equipo, provincia, zona, id_empresa, usuario_registro, usuario_update, created_at, updated_at FROM equipos_mtto WHERE id_equipo IN ($ids)");
    $resultEmpleados = mysqli_query($conexion, "SELECT id_empleado, nombrecom FROM empleado");
    $resultServicios = mysqli_query($conexion, "
    SELECT
        s.id_servicios,
        s.nombreservicios,
        z.nombre,
        CASE
            WHEN s.tipo_documento_cliente IS NOT NULL
            AND s.tipo_documento_cliente != ''
            THEN s.tipo_documento_cliente
            ELSE 'SIN DOC'
        END AS tiene_oc
    FROM servicios s
    LEFT JOIN zonas z ON z.id = s.id_zona
    WHERE z.id != 68
    AND s.estado = 'Iniciado'
    ORDER BY s.id_servicios DESC
");

    if ($result):

        // ── Pre-cargar materiales y herramientas por servicio ──
        $mapaServicios = [];
        $resTodosServicios = mysqli_query($conexion, "SELECT id_servicios FROM servicios");
        while ($srv = mysqli_fetch_assoc($resTodosServicios)) {
            $idSrv = intval($srv['id_servicios']);

            // Buscar salidas vinculadas a este servicio via salida_destino
            $resSalidas = mysqli_query($conexion, "
        SELECT sd.id_salida
        FROM salida_destino sd
        WHERE sd.id_destino = $idSrv
        AND sd.tipo_Destino = 'servicio'
    ");
            $idsSalida = [];
            while ($sal = mysqli_fetch_assoc($resSalidas)) {
                $idsSalida[] = intval($sal['id_salida']);
            }
            if (empty($idsSalida)) continue;
            $idsStr = implode(',', $idsSalida);

            $resMat = mysqli_query($conexion, "
        SELECT m.nombre, m.descripcion, SUM(sm.cantidad) AS cantidad
        FROM salida_material sm
        INNER JOIN materiales m ON m.id_material = sm.id_material
        WHERE sm.id_salida IN ($idsStr)
        GROUP BY sm.id_material
        ORDER BY m.nombre ASC
    ");
            $mats = [];
            while ($mat = mysqli_fetch_assoc($resMat)) {
                $mats[] = ['nombre' => $mat['nombre'], 'descripcion' => $mat['descripcion'] ?? '-'];
            }

            $resHerr = mysqli_query($conexion, "
        SELECT a.nombre, a.descripcion, a.serie, SUM(se.cantidad) AS cantidad
        FROM salida_equipo se
        INNER JOIN articulos a ON a.id_producto = se.id_producto
        WHERE se.id_salida IN ($idsStr)
        GROUP BY se.id_producto
        ORDER BY a.nombre ASC
    ");
            $herrs = [];
            while ($herr = mysqli_fetch_assoc($resHerr)) {
                $herrs[] = ['nombre' => $herr['nombre'], 'descripcion' => $herr['descripcion'] ?? '-', 'serie' => $herr['serie'] ?? '-'];
            }

            if (!empty($mats) || !empty($herrs)) {
                $mapaServicios[$idSrv] = ['materiales' => $mats, 'herramientas' => $herrs];
            }
        }
?>

        <div class="container-fluid">
            <div class="mb-4">
                <h5>Equipos Seleccionados</h5>
                <div style="max-height: 200px; overflow-y: auto;">
                    <table id="equiposTable" class="table table-bordered table-sm">
                        <thead class="table-light">
                            <tr>
                                <th>ID</th>
                                <th>Tipo</th>
                                <th>Nombre Equipo</th>
                                <th>Provincia</th>
                                <th>Zona</th>
                                <th>Empresa</th>
                                <th>Ult. Modificacion</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php while ($row = mysqli_fetch_assoc($result)) {
                                $fecha = $row['updated_at'] ?: $row['created_at']; ?>
                                <tr>
                                    <td><?= $row['id_equipo'] ?></td>
                                    <td><?= $row['tipo_equipo'] ?></td>
                                    <td><?= $row['nombre_equipo'] ?></td>
                                    <td><?= $row['provincia'] ?></td>
                                    <td><?= $row['zona'] ?></td>
                                    <td><?= $claseEmpresa->obtenNombreEmpresa($row['id_empresa']) ?></td>
                                    <td><?= date('d-m-Y H:i:s', strtotime($fecha)) ?></td>
                                </tr>
                            <?php } ?>
                            <?php
                            // Recolectar tipos de los equipos seleccionados
                            $tipos = [];
                            mysqli_data_seek($result, 0); // Resetear cursor
                            // Mejor: hacer una segunda query directa
                            $resTipos = mysqli_query(
                                $conexion,
                                "SELECT DISTINCT TRIM(tipo_equipo) AS tipo_equipo FROM equipos_mtto WHERE id_equipo IN ($ids)"
                            );
                            while ($t = mysqli_fetch_assoc($resTipos)) {
                                $tipos[] = strtoupper(trim($t['tipo_equipo']));
                            }

                            // ── Determinar tipo base para precargar listas ──
                            $tipoBase = 'OTRO';
                            foreach ($tipos as $t) {
                                if (str_contains($t, 'TABLERO')) {
                                    $tipoBase = 'TABLEROS';
                                    break;
                                }
                                if (str_contains($t, 'POZO')) {
                                    $tipoBase = 'POZOS';
                                    break;
                                }
                                if (str_contains($t, 'UPS') || str_contains($t, 'TRANS. AISLAMIENTO')) {
                                    $tipoBase = 'UPS';
                                    break;
                                }
                            }

                            // ── Datos por tipo ──
                            $eppsConfig = [
                                'TABLEROS' => ['CASCO DE SEGURIDAD', 'LENTES DE SEGURIDAD', 'BOTAS DE SEGURIDAD', 'PROTECTORES DE OIDO', 'CHALECOS DE SEGURIDAD'],
                                'POZOS'    => ['CASCO DE SEGURIDAD', 'LENTES DE SEGURIDAD', 'BOTAS DE SEGURIDAD', 'PROTECTORES DE OIDO', 'CHALECOS DE SEGURIDAD'],
                                'UPS'      => ['CASCO DE SEGURIDAD', 'LENTES DE SEGURIDAD', 'BOTAS DE SEGURIDAD', 'PROTECTORES DE OIDO', 'CHALECOS DE SEGURIDAD'],
                                'OTRO'     => ['CASCO DE SEGURIDAD', 'CARETA DIELÉCTRICA', 'LENTES DE SEGURIDAD', 'BOTAS DE SEGURIDAD', 'CHALECOS DE SEGURIDAD', 'GUANTES DIELÉCTRICOS'],
                            ];

                            $materialesConfig = [
                                'TABLEROS' => [
                                    ['nombre' => 'SOLVENTE DIELÉCTRICO', 'unidad' => 'Ud.', 'caract' => '-'],
                                    ['nombre' => 'CREMA LIMPIADORA',     'unidad' => 'Ud.', 'caract' => '-'],
                                    ['nombre' => 'TRAPO INDUSTRIAL',     'unidad' => 'Ud.', 'caract' => '-'],
                                    ['nombre' => 'SEÑALÉTICAS',          'unidad' => 'Ud.', 'caract' => '-'],
                                    ['nombre' => 'BROCHA',               'unidad' => 'Ud.', 'caract' => '-'],
                                    ['nombre' => 'TERMINALES',           'unidad' => 'Ud.', 'caract' => '-'],
                                ],
                                'POZOS' => [
                                    ['nombre' => 'PINTURA TRÁFICO AMARILLA', 'unidad' => 'Ud.', 'caract' => '-'],
                                    ['nombre' => 'SPRAY NEGRO',              'unidad' => 'Ud.', 'caract' => '-'],
                                    ['nombre' => 'LIJA',                     'unidad' => 'Ud.', 'caract' => '-'],
                                    ['nombre' => 'THOR GEL',                 'unidad' => 'Ud.', 'caract' => '-'],
                                    ['nombre' => 'TRAPO INDUSTRIAL',         'unidad' => 'Ud.', 'caract' => '-'],
                                    ['nombre' => 'SEÑALÉTICA',               'unidad' => 'Ud.', 'caract' => '-'],
                                    ['nombre' => 'THINNER',                  'unidad' => 'Ud.', 'caract' => '-'],
                                ],
                                'UPS' => [
                                    ['nombre' => 'SOLVENTE DIELÉCTRICO', 'unidad' => 'Ud.', 'caract' => '-'],
                                    ['nombre' => 'CREMA LIMPIADORA',    'unidad' => 'Ud.', 'caract' => '-'],
                                    ['nombre' => 'TRAPO INDUSTRIAL',    'unidad' => 'Ud.', 'caract' => '-'],
                                ],
                                'OTRO' => [
                                    ['nombre' => 'SOLVENTE DIELÉCTRICO',    'unidad' => 'GLN.', 'caract' => '-'],
                                    ['nombre' => 'CREMA LIMPIADORA',         'unidad' => 'UND.', 'caract' => '-'],
                                    ['nombre' => 'TAPAS DE RESERVA',         'unidad' => 'UND.', 'caract' => '-'],
                                    ['nombre' => 'CINTILLOS',                'unidad' => 'UND.', 'caract' => '-'],
                                    ['nombre' => 'BROCHA',                   'unidad' => 'UND.', 'caract' => '-'],
                                    ['nombre' => 'TERMINALES',               'unidad' => 'UND.', 'caract' => '-'],
                                    ['nombre' => 'SEÑALÉTICA',               'unidad' => 'UND.', 'caract' => '-'],
                                    ['nombre' => 'PINTURA TRÁFICO AMARILLA', 'unidad' => 'GLN.', 'caract' => '-'],
                                    ['nombre' => 'SPRITE NEGRO',             'unidad' => 'UND.', 'caract' => '-'],
                                    ['nombre' => 'LIJAS',                    'unidad' => 'UND.', 'caract' => '-'],
                                    ['nombre' => 'THOR GEL',                 'unidad' => 'UND.', 'caract' => '-'],
                                    ['nombre' => 'CONECTOR TIERRA CABLE',    'unidad' => 'UND.', 'caract' => '-'],
                                    ['nombre' => 'TRAPOS INDUSTRIALES',      'unidad' => 'UND.', 'caract' => '-'],
                                    ['nombre' => 'THINER',                   'unidad' => 'GLN.', 'caract' => '-'],
                                ],
                            ];

                            $herramientasConfig = [
                                'TABLEROS' => [
                                    ['serie' => '-', 'nombre' => 'JUEGO DE ALICATES',        'marca' => 'Dieléctrico'],
                                    ['serie' => '-', 'nombre' => 'JUEGO DE DESARMADORES',     'marca' => 'Dieléctrico'],
                                    ['serie' => '-', 'nombre' => 'BOLSA PORTAHERRAMIENTAS',   'marca' => '-'],
                                    ['serie' => '-', 'nombre' => 'MEGOHMETRO',                'marca' => '-'],
                                    ['serie' => '-', 'nombre' => 'PINZA AMPERIMÉTRICA',       'marca' => '-'],
                                    ['serie' => '-', 'nombre' => 'CÁMARA TERMOGRÁFICA',       'marca' => '-'],
                                    ['serie' => '-', 'nombre' => 'SOPLADOR DE AIRE',          'marca' => '-'],
                                ],
                                'POZOS' => [
                                    ['serie' => '-', 'nombre' => 'JUEGO DE ALICATES',      'marca' => 'Dieléctrico'],
                                    ['serie' => '-', 'nombre' => 'JUEGO DE DESARMADORES',   'marca' => 'Dieléctrico'],
                                    ['serie' => '-', 'nombre' => 'BROCHA',                  'marca' => '-'],
                                    ['serie' => '-', 'nombre' => 'LLAVES BOCA CORONA',      'marca' => '-'],
                                    ['serie' => '-', 'nombre' => 'CINCEL PLANO',            'marca' => '-'],
                                    ['serie' => '-', 'nombre' => 'LLAVE FRANCESA',          'marca' => '-'],
                                    ['serie' => '-', 'nombre' => 'BALDE',                   'marca' => '-'],
                                ],
                                'UPS' => [
                                    ['serie' => '-', 'nombre' => 'JUEGO DE ALICATES',     'marca' => 'Dieléctrico'],
                                    ['serie' => '-', 'nombre' => 'JUEGO DE DESARMADORES',  'marca' => 'Dieléctrico'],
                                    ['serie' => '-', 'nombre' => 'BROCHA',                 'marca' => '-'],
                                ],
                                'OTRO' => [
                                    ['serie' => '-', 'nombre' => 'JUEGO DE DESARMADORES DIELÉCTRICOS', 'marca' => 'Marca Stanley, 6 piezas'],
                                    ['serie' => '-', 'nombre' => 'BOLSA PORTAHERRAMIENTAS',            'marca' => '-'],
                                    ['serie' => '-', 'nombre' => 'JUEGO DE ALICATES DIELÉCTRICOS',     'marca' => '-'],
                                    ['serie' => '-', 'nombre' => 'PINZA AMPERIMÉTRICA',                'marca' => 'Marca FLUKE'],
                                    ['serie' => '-', 'nombre' => 'CÁMARA TERMOGRÁFICA',                'marca' => 'Marca FLUKE'],
                                    ['serie' => '-', 'nombre' => 'SOPLADOR INALÁMBRICO',               'marca' => 'Marca BOSCH'],
                                    ['serie' => '-', 'nombre' => 'MEGÓHMETRO DIGITAL',                 'marca' => 'Marca SANWA'],
                                    ['serie' => '-', 'nombre' => 'TELURÓMETRO',                        'marca' => 'Marca Kyoritsu'],
                                    ['serie' => '-', 'nombre' => 'BROCHA',                             'marca' => 'Generico'],
                                    ['serie' => '-', 'nombre' => 'LLAVES BOCA CORONA',                 'marca' => 'Marca Stanley'],
                                    ['serie' => '-', 'nombre' => 'CINCEL PLANO',                       'marca' => '-'],
                                    ['serie' => '-', 'nombre' => 'LLAVE FRANCESA',                     'marca' => '-'],
                                    ['serie' => '-', 'nombre' => 'PATA DE CABRA',                      'marca' => '-'],
                                    ['serie' => '-', 'nombre' => 'COMBA',                              'marca' => '-'],
                                    ['serie' => '-', 'nombre' => 'BALDE',                              'marca' => '-'],
                                ],
                            ];

                            $epps         = $eppsConfig[$tipoBase];
                            $materiales   = $materialesConfig[$tipoBase];
                            $herramientas = $herramientasConfig[$tipoBase];
                            ?>
                            <input type="hidden" id="tipoEquipoModal" value="<?= htmlspecialchars(implode(',', $tipos)) ?>">
                        </tbody>
                    </table>
                </div>
            </div>

            <div class="mb-3">
                <label for="servicioInforme" class="form-label">Servicio Asociado</label>
                <select class="form-select" id="servicioInforme" name="servicioInforme">
                    <option value="">Seleccione un Servicio</option>
                    <?php while ($serv = mysqli_fetch_assoc($resultServicios)): ?>
                        <option value="<?= $serv['id_servicios'] ?>">
                            <?= $serv['nombreservicios'] . ' - (' . $serv['nombre'] . ') | OC: ' . $serv['tiene_oc'] ?>
                        </option>
                    <?php endwhile; ?>
                </select>
            </div>

            <div class="mb-3">
                <label for="eppsUsados" class="form-label">EPPs Usadas</label>
                <div class="input-group">
                    <input type="text" id="eppsUsados" class="form-control" placeholder="Agregar EPP...">
                    <button class="btn btn-outline-primary" type="button" id="agregarEppBtn">Agregar</button>
                </div>
                <div class="mt-2" style="max-height: 180px; overflow-y: auto;">
                    <table class="table table-bordered table-sm" id="eppsTable">
                        <thead class="table-light">
                            <tr>
                                <th>EPP</th>
                                <th>Acción</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($epps as $epp): ?>
                                <tr>
                                    <td><?= htmlspecialchars($epp) ?></td>
                                    <td><button type="button" class="btn btn-danger btn-sm remove-btn">Eliminar</button></td>
                                </tr>
                            <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
            </div>

            <div class="mb-3">
                <label for="herramientasUsadas" class="form-label">Herramientas Usadas</label>
                <div class="input-group">
                    <input type="text" id="herramientasUsadas" class="form-control" placeholder="Agregar herramienta...">
                    <button class="btn btn-outline-secondary" type="button" id="agregarHerramientaTextoBtn"><i class="fas fa-plus"></i></button>
                    <button class="btn btn-success" type="button" data-bs-toggle="modal" data-bs-target="#modalHerramientasCalibracion">Agregar desde catálogo</button>
                </div>
                <div class="mt-2" style="max-height: 160px; overflow-y: auto;">
                    <table class="table table-bordered table-sm" id="herramientasTable">
                        <thead class="table-light">
                            <tr>
                                <th>Serie</th>
                                <th>Herramienta</th>
                                <th>Marca</th>
                                <th>PDF</th>
                                <th>Acción</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($herramientas as $h): ?>
                                <tr>
                                    <td><?= htmlspecialchars($h['serie']) ?></td>
                                    <td><?= htmlspecialchars($h['nombre']) ?></td>
                                    <td><input type="text" class="form-control" value="<?= htmlspecialchars($h['marca']) ?>"></td>
                                    <td>-</td>
                                    <td><button type="button" class="btn btn-danger btn-sm remove-btn">Eliminar</button></td>
                                </tr>
                            <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
            </div>

            <div class="mb-3">
                <label for="materialesUsados" class="form-label">Materiales Usados</label>
                <div class="input-group">
                    <input type="text" id="materialesUsados" class="form-control" placeholder="Agregar material...">
                    <button class="btn btn-outline-primary" type="button" id="agregarMaterialBtn">Agregar</button>
                </div>
                <div class="mt-2" style="max-height: 160px; overflow-y: auto;">
                    <table class="table table-bordered table-sm" id="materialesTable">
                        <thead class="table-light">
                            <tr>
                                <th>Material</th>
                                <th>Unidad</th>
                                <th>Características</th>
                                <th>Acción</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($materiales as $m): ?>
                                <tr>
                                    <td><?= htmlspecialchars($m['nombre']) ?></td>
                                    <td><input type="text" class="form-control" value="<?= htmlspecialchars($m['unidad']) ?>"></td>
                                    <td><input type="text" class="form-control" value="<?= htmlspecialchars($m['caract']) ?>"></td>
                                    <td><button type="button" class="btn btn-danger btn-sm remove-btn">Eliminar</button></td>
                                </tr>
                            <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
            </div>

            <div class="mb-3">
                <label for="empleadoInforme" class="form-label">Personal Asignado</label>
                <select class="form-select" name="empleadoInforme" id="empleadoInforme" style="width: 100%;">
                    <option value="">Seleccione un empleado</option>
                    <?php while ($emp = mysqli_fetch_assoc($resultEmpleados)) { ?>
                        <option value="<?= $emp['id_empleado'] ?>"><?= $emp['nombrecom'] ?></option>
                    <?php } ?>
                </select>
                <button type="button" id="agregarPersonalBtn" class="btn btn-primary mt-2">Agregar Personal</button>
            </div>

            <div class="mt-2" style="max-height: 160px; overflow-y: auto;">
                <table class="table table-bordered table-sm" id="personalTable">
                    <thead class="table-light">
                        <tr>
                            <th>ID</th>
                            <th>Personal</th>
                            <th>Rol</th>
                            <th>Acción</th>
                        </tr>
                    </thead>
                    <tbody></tbody>
                </table>
            </div>
        </div>

<?php else:
        echo '<p>No se encontraron equipos seleccionados.</p>';
    endif;
} else {
    echo '<p>Solicitud inválida.</p>';
} ?>

<div id="loadingModalInforme" class="loading-modal" style="display: none;">
    <div class="loading-content">
        <div class="spinner-border text-primary" role="status"></div>
        <p class="mt-2">Cargando...</p>
    </div>
</div>

<script>
    (function() {

        const mapaServicios = <?= json_encode($mapaServicios ?? []) ?>;

        $(document).ready(function() {

            function agregarElemento(inputId, tablaId, columnas, validacionDuplicado = true) {
                const valor = $(`#${inputId}`).val().trim().toUpperCase();
                if (!valor) return;
                if (validacionDuplicado && $(`#${tablaId} tbody tr`).filter(function() {
                        return $(this).find('td:first').text() === valor;
                    }).length > 0) {
                    alertify.error(`${valor} ya ha sido agregado.`);
                    return;
                }
                const fila = `<tr>${columnas(valor)}</tr>`;
                $(`#${tablaId} tbody`).append(fila);
                $(`#${inputId}`).val('');
            }

            $('#agregarEppBtn').click(() => agregarElemento('eppsUsados', 'eppsTable', (val) => `
            <td>${val}</td>
            <td><button type="button" class="btn btn-danger btn-sm remove-btn">Eliminar</button></td>`));

            $('#eppsUsados').on('keypress', function(e) {
                if (e.which === 13) {
                    e.preventDefault();
                    $('#agregarEppBtn').click();
                }
            });

            $('#agregarMaterialBtn').click(() => agregarElemento('materialesUsados', 'materialesTable', (val) => `
            <td>${val}</td>
            <td><input type="text" class="form-control" value="UND"></td>
            <td><input type="text" class="form-control" value="-"></td>
            <td><button type="button" class="btn btn-danger btn-sm remove-btn">Eliminar</button></td>`));

            $('#materialesUsados').on('keypress', function(e) {
                if (e.which === 13) {
                    e.preventDefault();
                    $('#agregarMaterialBtn').click();
                }
            });

            $('#agregarHerramientaTextoBtn').click(() => agregarElemento('herramientasUsadas', 'herramientasTable', (val) => `
            <td>-</td>
            <td>${val}</td>
            <td><input type="text" class="form-control" value="-"></td>
            <td>-</td>
            <td><button type="button" class="btn btn-danger btn-sm remove-btn">Eliminar</button></td>`));

            $('#herramientasUsadas').on('keypress', function(e) {
                if (e.which === 13) {
                    e.preventDefault();
                    $('#agregarHerramientaTextoBtn').click();
                }
            });

            $(document).on('click', '.remove-btn', function() {
                $(this).closest('tr').remove();
            });

            $('#agregarPersonalBtn').click(function() {
                const empleadoId = $('#empleadoInforme').val();
                const empleadoNombre = $('#empleadoInforme option:selected').text();
                if (!empleadoId) {
                    alertify.error('Seleccione un empleado válido');
                    return;
                }

                const yaExiste = $('#personalTable tbody tr').filter(function() {
                    return $(this).find('td:nth-child(2)').text() === empleadoNombre;
                }).length > 0;

                if (yaExiste) {
                    alertify.error('El personal ya ha sido agregado.');
                    return;
                }

                $('#personalTable tbody').append(`
                <tr>
                    <td>${empleadoId}</td>
                    <td>${empleadoNombre}</td>
                    <td>
                        <select class="form-select rol-select">
                            <option value="Supervisor">Supervisor</option>
                            <option value="Técnico">Técnico</option>
                        </select>
                    </td>
                    <td><button type="button" class="btn btn-danger btn-sm remove-person-btn">Eliminar</button></td>
                </tr>`);

                $('#empleadoInforme option[value="' + empleadoId + '"]').prop('disabled', true);
                $('#empleadoInforme').val(null).trigger('change');
            });

            $('#personalTable').on('click', '.remove-person-btn', function() {
                const empleadoId = $(this).closest('tr').find('td:first').text();
                $('#empleadoInforme option[value="' + empleadoId + '"]').prop('disabled', false);
                $(this).closest('tr').remove();
            });

            $('#empleadoInforme').select2({
                dropdownParent: $('#empleadoInforme').closest('.modal').length ?
                    $('#empleadoInforme').closest('.modal') : $(document.body),
                placeholder: "Seleccione un empleado",
                allowClear: true,
                width: '100%'
            });

            $('#servicioInforme').select2({
                dropdownParent: $('#servicioInforme').closest('.modal').length ?
                    $('#servicioInforme').closest('.modal') : $(document.body),
                placeholder: "Seleccione un servicio",
                allowClear: true,
                width: '100%'
            });

            $('#servicioInforme').on('change', function() {
                const idServicio = $(this).val();
                if (!idServicio) return;
                const datos = mapaServicios[idServicio];
                if (!datos || (datos.materiales.length === 0 && datos.herramientas.length === 0)) {
                    alertify.warning('No se encontraron salidas registradas para este servicio.');
                    return;
                }
                if (datos.materiales.length > 0) {
                    $('#materialesTable tbody').empty();
                    datos.materiales.forEach(function(mat) {
                        $('#materialesTable tbody').append(`
                        <tr>
                            <td>${mat.nombre}</td>
                            <td><input type="text" class="form-control" value="UND."></td>
                            <td><input type="text" class="form-control" value="${mat.descripcion}"></td>
                            <td><button type="button" class="btn btn-danger btn-sm remove-btn">Eliminar</button></td>
                        </tr>`);
                    });
                }
                if (datos.herramientas.length > 0) {
                    $('#herramientasTable tbody').empty();
                    datos.herramientas.forEach(function(herr) {
                        $('#herramientasTable tbody').append(`
                        <tr>
                            <td>${herr.serie}</td>
                            <td>${herr.nombre}</td>
                            <td><input type="text" class="form-control" value="${herr.descripcion}"></td>
                            <td>-</td>
                            <td><button type="button" class="btn btn-danger btn-sm remove-btn">Eliminar</button></td>
                        </tr>`);
                    });
                }
                alertify.success('Materiales y herramientas cargados del servicio.');
            });

        });

    })();
</script>
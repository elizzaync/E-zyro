<?php
//inicio.php
session_start();

// Validación de sesión
if (!isset($_SESSION['usuario'])) {
    header("location:../index.php");
    exit();
}

// Conexión a base de datos
require_once __DIR__ . "/../../src/Database/Conexion.php";
$c = new conectar();
$conexion = $c->conexion();
$idusuario = $_SESSION['iduser'];

// 1. Consulta para la tabla principal
$sql_mantenimientos = "SELECT m.id_mantenimiento, m.estado, m.tipo_mantenimiento, m.fecha_programada,
                              a.nombre AS equipo, a.serie
                       FROM mantenimiento_equipos m
                       INNER JOIN articulos a ON m.id_producto = a.id_producto
                       ORDER BY m.fecha_programada DESC";
$result_mantenimientos = mysqli_query($conexion, $sql_mantenimientos);

// 2. Consulta para Modal: Equipos operativos
$sql_articulos = "SELECT id_producto, nombre, serie FROM articulos WHERE operativo = 1 ORDER BY nombre ASC";
$result_articulos = mysqli_query($conexion, $sql_articulos);

// 3. NUEVO: Consulta para Modal: Empleados vigentes (Técnicos/Responsables)
$sql_empleados = "SELECT id_empleado, nombrecom, cargo FROM empleado WHERE vigente = 1 ORDER BY nombrecom ASC";
$result_empleados = mysqli_query($conexion, $sql_empleados);
?>

<!DOCTYPE html>
<html lang="es">

<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <title>Mantenimiento - Sistema ERP</title>

    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="icon" type="image/ico" href="../assets/img/logo.ico" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Open+Sans:wght@300;400;600&family=Raleway:wght@200;400;600&family=Work+Sans:wght@400;600;800&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.0/font/bootstrap-icons.css">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">

    <link href="https://cdn.jsdelivr.net/npm/select2@4.1.0-rc.0/dist/css/select2.min.css" rel="stylesheet" />
    <link rel="stylesheet" href="../assets/css/inicio.css">
    <?php require_once "menu.php"; ?>
</head>

<body>
    <script src="../assets/js/sidebar.js?v=<?php echo time(); ?>"></script>

    <main class="main-content">
        <div class="container-fluid p-4">

            <div class="card shadow-sm border-0 mb-4" style="border-radius: 10px;">
                <div class="card-body d-flex align-items-center">
                    <div class="icon-circle bg-light text-success me-3 d-flex justify-content-center align-items-center" style="width: 60px; height: 60px; border-radius: 50%;">
                        <i class="bi bi-tools fs-2" style="color: #a4ce3a;"></i>
                    </div>
                    <div>
                        <h2 class="mb-1 fw-bold" style="color: #2c3e50;">Mantenimiento de Equipos</h2>
                        <p class="text-muted mb-0">Gestione el mantenimiento preventivo y correctivo de sus activos</p>
                    </div>
                </div>
            </div>

            <div class="d-flex mb-4">
                <button type="button" class="btn btn-success me-2" data-bs-toggle="modal" data-bs-target="#modalAgregarMantenimiento" style="background-color: #00a65a; border-color: #008d4c;">
                    <i class="bi bi-plus-circle"></i> Agregar Mantenimiento
                </button>
                <button class="btn btn-danger" style="background-color: #dd4b39; border-color: #d73925;">
                    <i class="bi bi-file-earmark-pdf"></i> Reporte PDF
                </button>
            </div>

            <div class="card shadow-sm border-0" style="border-radius: 10px;">
                <div class="card-body">
                    <div class="table-responsive">
                        <table class="table table-hover table-striped align-middle" id="tablaMantenimientos" style="width: 100%;">
                            <thead class="bg-light text-muted" style="border-bottom: 2px solid #dee2e6;">
                                <tr>
                                    <th class="fw-semibold">N° ORDEN</th>
                                    <th class="fw-semibold">EQUIPO / HERRAMIENTA</th>
                                    <th class="fw-semibold text-center">SERIE</th>
                                    <th class="fw-semibold text-center">TIPO</th>
                                    <th class="fw-semibold text-center">FECHA PROG.</th>
                                    <th class="fw-semibold text-center">ESTADO</th>
                                </tr>
                            </thead>
                            <tbody>
                                <?php while ($row = mysqli_fetch_assoc($result_mantenimientos)) {
                                    $badgeClass = 'bg-secondary';
                                    if ($row['estado'] == 'Programado') $badgeClass = 'bg-warning text-dark';
                                    if ($row['estado'] == 'En Proceso') $badgeClass = 'bg-primary';
                                    if ($row['estado'] == 'Finalizado') $badgeClass = 'bg-success';
                                    if ($row['estado'] == 'Cancelado') $badgeClass = 'bg-danger';
                                ?>
                                    <tr>
                                        <td class="text-muted fw-bold">MT-<?php echo str_pad($row['id_mantenimiento'], 4, "0", STR_PAD_LEFT); ?></td>
                                        <td><?php echo $row['equipo']; ?></td>
                                        <td class="text-center text-muted"><?php echo $row['serie']; ?></td>
                                        <td class="text-center"><?php echo $row['tipo_mantenimiento']; ?></td>
                                        <td class="text-center"><?php echo date("d/m/Y", strtotime($row['fecha_programada'])); ?></td>
                                        <td class="text-center">
                                            <span class="badge <?php echo $badgeClass; ?>"><?php echo $row['estado']; ?></span>
                                        </td>
                                    </tr>
                                <?php } ?>
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>

        </div>
    </main>

    <div class="modal fade" id="modalAgregarMantenimiento" tabindex="-1" aria-labelledby="modalLabel" aria-hidden="true">
        <div class="modal-dialog modal-lg">
            <div class="modal-content">
                <div class="modal-header" style="background-color: #f8f9fa;">
                    <h5 class="modal-title fw-bold" id="modalLabel"><i class="bi bi-wrench"></i> Programar Mantenimiento</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>

                <form action="../../src/Controllers/Inventario/procesar_mantenimiento.php" method="POST">
                    <div class="modal-body">

                        <div class="mb-3">
                            <label class="form-label fw-bold">Seleccionar Herramienta / Equipo</label>
                            <select class="form-select" name="id_producto" id="selectEquipo" style="width: 100%;" required>
                                <option value="" disabled selected></option>
                                <?php while ($art = mysqli_fetch_assoc($result_articulos)) { ?>
                                    <option value="<?php echo $art['id_producto']; ?>">
                                        <?php echo $art['nombre'] . " (Serie: " . ($art['serie'] != '' ? $art['serie'] : 'S/N') . ")"; ?>
                                    </option>
                                <?php } ?>
                            </select>
                            <small class="text-muted mt-1 d-block">Puede buscar por nombre de herramienta o serie.</small>
                        </div>

                        <div class="row">
                            <div class="col-md-6 mb-3">
                                <label class="form-label fw-bold">Tipo de Mantenimiento</label>
                                <select class="form-select" name="tipo_mantenimiento" required>
                                    <option value="Preventivo">Preventivo</option>
                                    <option value="Correctivo">Correctivo</option>
                                    <option value="Predictivo">Predictivo</option>
                                </select>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label fw-bold">Fecha Programada</label>
                                <input type="date" class="form-control" name="fecha_programada" required>
                            </div>
                        </div>

                        <div class="row">
                            <div class="col-md-6 mb-3">
                                <label class="form-label fw-bold">Próximo Mantenimiento (En meses)</label>
                                <input type="number" class="form-control" name="proximo_mantenimiento_meses" placeholder="Ej: 3, 6, 12..." required>
                                <small class="text-muted mt-1 d-block">Indique cada cuántos meses se repite.</small>
                            </div>

                            <div class="col-md-6 mb-3">
                                <label class="form-label fw-bold">Técnico Responsable</label>
                                <select class="form-select" name="id_tecnico" id="selectTecnico" style="width: 100%;" required>
                                    <option value="" disabled selected></option>
                                    <?php while ($emp = mysqli_fetch_assoc($result_empleados)) { ?>
                                        <option value="<?php echo $emp['id_empleado']; ?>">
                                            <?php echo $emp['nombrecom'] . " - " . $emp['cargo']; ?>
                                        </option>
                                    <?php } ?>
                                </select>
                            </div>
                        </div>

                        <div class="mb-3">
                            <label class="form-label fw-bold">Descripción del Problema / Motivo</label>
                            <textarea class="form-control" name="descripcion_problema" rows="3" placeholder="Detalle por qué el equipo ingresa a mantenimiento..."></textarea>
                        </div>

                        <input type="hidden" name="id_usuario_registro" value="<?php echo $idusuario; ?>">

                    </div>
                    <div class="modal-footer" style="background-color: #f8f9fa;">
                        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancelar</button>
                        <button type="submit" class="btn btn-success" style="background-color: #00a65a; border-color: #008d4c;">Guardar Registro</button>
                    </div>
                </form>
            </div>
        </div>
    </div>

    <script src="https://code.jquery.com/jquery-3.7.0.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/select2@4.1.0-rc.0/dist/js/select2.min.js"></script>

    <script>
        $(document).ready(function() {
            // Inicializar buscador de equipos
            $('#selectEquipo').select2({
                dropdownParent: $('#modalAgregarMantenimiento'),
                placeholder: "Buscar herramienta o serie...",
                allowClear: true,
                language: {
                    noResults: () => "No se encontraron equipos"
                }
            });

            // Inicializar buscador de personal
            $('#selectTecnico').select2({
                dropdownParent: $('#modalAgregarMantenimiento'),
                placeholder: "Buscar técnico asignado...",
                allowClear: true,
                language: {
                    noResults: () => "No se encontró el empleado"
                }
            });

            $('#modalAgregarMantenimiento').on('shown.bs.modal', function() {
                $('#selectEquipo').select2('close');
                $('#selectTecnico').select2('close');
            });
        });
    </script>
</body>

</html>
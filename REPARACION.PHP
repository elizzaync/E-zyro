<?php
session_start();
if (!isset($_SESSION['usuario']) || !in_array($_SESSION['privilegio'], array("SuperAdmin", "Logistica", "JefeOperaciones", "Supervisor", "Administracion", "Arquitectura"), true)) {
    header("location:../../index.php");
    exit();
}
require_once __DIR__ . "/../../../../src/Database/Conexion.php";
require_once __DIR__ . "/../../../../src/Models/Empleado.php";
require_once __DIR__ . "/../../../../src/Models/Requerimientos.php";
require_once __DIR__ . "/../servicios/Servicios.php";
require_once __DIR__ . "/../../../../src/Models/Zonas.php";
require_once __DIR__ . "/../../../vendor/autoload.php"; // PHPWord

use PhpOffice\PhpWord\PhpWord;
use PhpOffice\PhpWord\IOFactory;
use PhpOffice\PhpWord\Style\Font;
use PhpOffice\PhpWord\SimpleType\Jc;
use PhpOffice\PhpWord\Shared\Converter;

$claseServicio = new servicios();
$claseZona = new zonas();
$c = new conectar();
$conexion = $c->conexion();

// ==========================================
// LÓGICA DE DATOS
// ==========================================
$equipos = $_POST['equipos'] ?? [];
$epps = $_POST['epps'] ?? [];
$herramientas = $_POST['herramientas'] ?? [];
$materiales = $_POST['materiales'] ?? [];
$personal = $_POST['personal'] ?? [];
$idServicio = $_POST['servicio'] ?? '';
$oc = $_POST['oc'] ?? 'SIN-OC';
$tipoEquipo = $_POST['tipo'] ?? 'TABLEROS';
$nombreServicio = $_POST['nombre_servicio'] ?? 'MANTENIMIENTO PREVENTIVO TABLEROS ELÉCTRICOS';

if (is_string($equipos)) $equipos = json_decode($equipos, true);
if (is_string($epps)) $epps = json_decode($epps, true);
if (is_string($herramientas)) $herramientas = json_decode($herramientas, true);
if (is_string($materiales)) $materiales = json_decode($materiales, true);
if (is_string($personal)) $personal = json_decode($personal, true);

if (!empty($equipos) && is_array($equipos)) {
    $idTableroStr = implode(',', $equipos);
    $sql = "SELECT
                em.nombre_equipo,
                em.descripcion,
                em.provincia,
                em.zona,
                es.nombre AS empresa_solicitante
            FROM
                equipos_mtto em
            LEFT JOIN
                empresas_solicitantes es ON es.id = em.id_empresa
            WHERE
                em.id_equipo IN ($idTableroStr)";

    $result = mysqli_query($conexion, $sql);
    if (!$result) {
        die('Error en la consulta SQL: ' . mysqli_error($conexion));
    }
} else {
    die('No se enviaron equipos.');
}

$zonas = [];
$empresasSolicitantes = [];
$nombresEquipos = [];
while ($datos = mysqli_fetch_assoc($result)) {
    $nombresEquipos[] = $datos['nombre_equipo'];
    $zonas[] = $datos['zona'];
    $empresasSolicitantes[] = $datos['empresa_solicitante'];
}
$zonasUnica = array_unique($zonas);
$empresasUnica = array_unique($empresasSolicitantes);
$zonasStr = implode(', ', $zonasUnica) ?: 'SIN ZONA';
$empresasStr = implode(', ', $empresasUnica) ?: 'TALMA SERVICIOS AEROPORTUARIOS S.A.';
$ubicacionFinal = strtoupper($empresasStr) . ' – ' . strtoupper($zonasStr);
$tituloDinamico = strtoupper($nombreServicio);
// Fechas dinámicas
$meses = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
$mesElegante = ucfirst(strtolower($meses[date('n') - 1]));
$mesActual = strtoupper($meses[date('n') - 1]);
$anioActual = date('Y');
$fechaActual = date('d/m/Y');
$fechaInicio = date('d/m/Y', strtotime('-4 days'));

$imagenesCache = [];
function resolverYConvertir($ruta)
{
    global $imagenesCache;
    if (isset($imagenesCache[$ruta])) return $imagenesCache[$ruta];
    $rutaFinal = resolverRutaImagen($ruta);
    if ($rutaFinal) {
        $rutaFinal = convertirWebpAJpegWord($rutaFinal);
    }
    $imagenesCache[$ruta] = $rutaFinal;
    return $rutaFinal;
}

function resolverRutaImagen($ruta)
{
    if (empty($ruta)) return false;
    $raiz = $_SERVER['DOCUMENT_ROOT'] . '/erp-system/src/storage/';
    $posibles = [
        $raiz . ltrim($ruta, '/'),
        $raiz . ltrim($ruta, './'),
        $ruta,
        $_SERVER['DOCUMENT_ROOT'] . '/' . ltrim($ruta, '/'),
    ];
    foreach ($posibles as $intento) {
        $real = realpath($intento);
        if ($real && file_exists($real)) return $real;
    }
    return false;
}

function convertirWebpAJpegWord($rutaWebp)
{
    if (!file_exists($rutaWebp)) return false;
    $infoImagen = @getimagesize($rutaWebp);
    if ($infoImagen && $infoImagen['mime'] === 'image/webp') {
        if (!function_exists('imagecreatefromwebp')) return $rutaWebp;
        $rutaJpg = str_replace('.webp', '.jpg', $rutaWebp);
        if (file_exists($rutaJpg)) return $rutaJpg;
        try {
            $imagen = @imagecreatefromwebp($rutaWebp);
            if (!$imagen) return $rutaWebp;
            imagejpeg($imagen, $rutaJpg, 90);
            imagedestroy($imagen);
            return $rutaJpg;
        } catch (Exception $e) {
            return $rutaWebp;
        }
    }
    return $rutaWebp;
}

// ==========================================
// CREAR DOCUMENTO WORD Y ESTILOS
// ==========================================
$phpWord = new PhpWord();
$properties = $phpWord->getDocInfo();
$properties->setCreator('E-SYSTEM TIC PERU S.A.C.');
$properties->setTitle("INFORME MTTO. PREV. TABLEROS OC " . $oc);

$phpWord->setDefaultFontName('Arial');
$phpWord->setDefaultFontSize(11);

// Estilos de Títulos
$phpWord->addTitleStyle(1, array('name' => 'Arial', 'size' => 14, 'bold' => true, 'color' => '000000'), array('spaceAfter' => 240));
$phpWord->addTitleStyle(2, array('name' => 'Arial', 'size' => 12, 'bold' => true, 'color' => '000000'), array('spaceAfter' => 240));
$phpWord->addTitleStyle(3, array('name' => 'Arial', 'size' => 11, 'bold' => true, 'color' => '000000'), array('spaceAfter' => 240));

$phpWord->addFontStyle('portadaTitle', array('name' => 'Arial', 'size' => 24, 'bold' => true, 'color' => '000000'));
$phpWord->addFontStyle('portadaSub', array('name' => 'Arial', 'size' => 16, 'bold' => true, 'color' => '000000'));
$phpWord->addParagraphStyle('centerAlign', array('alignment' => Jc::CENTER, 'spaceAfter' => 150));
$phpWord->addParagraphStyle('justifyAlign', array('alignment' => Jc::BOTH, 'spaceAfter' => 150));
$tableStyle = array('borderSize' => 6, 'borderColor' => '000000', 'cellMargin' => 80);

// RUTAS DE LOGOS
$rutaLogoProfesional = __DIR__ . '/../../../assets/img/headerLogo.png';
$rutaLogoTalma = __DIR__ . '/../../../assets/img/talma.png';

// ==========================================
// SECCIÓN: PORTADA
// ==========================================
$section = $phpWord->addSection();

// ENCABEZADO EN PORTADA
$headerPortada = $section->addHeader();
$cellStyleP = ['borderSize' => 6, 'borderColor' => '000000', 'valign' => 'center'];
$hTableP = $headerPortada->addTable(['borderSize' => 6, 'borderColor' => '000000', 'cellMargin' => 40]);
$wLeft = 5500;
$wMid = 1700;
$wRight = 1800;

$hTableP->addRow(300);
$hTableP->addCell($wLeft, $cellStyleP)->addText("INFORME OC-{$oc} {$tituloDinamico}", ['bold' => true, 'size' => 8], ['alignment' => Jc::CENTER]);
$logoCellP = $hTableP->addCell($wMid + $wRight, array_merge($cellStyleP, ['gridSpan' => 2, 'vMerge' => 'restart']));
if (file_exists($rutaLogoProfesional)) {
    $logoCellP->addImage($rutaLogoProfesional, ['height' => 22, 'alignment' => Jc::CENTER]);
}
$hTableP->addRow(250);
$hTableP->addCell($wLeft, $cellStyleP)->addText("UBICACIÓN: {$ubicacionFinal}", ['bold' => true, 'size' => 8]);
$hTableP->addCell($wMid + $wRight, array_merge($cellStyleP, ['gridSpan' => 2, 'vMerge' => 'continue']));

$hTableP->addRow(230);
$hTableP->addCell($wLeft, array_merge($cellStyleP, ['vMerge' => 'restart']))->addText("ESPECIALIDAD: INSTALACIONES ELÉCTRICAS", ['bold' => true, 'size' => 8]);
$hTableP->addCell($wMid, $cellStyleP)->addText("Elaborado por:", ['size' => 7, 'bold' => true]);
$hTableP->addCell($wRight, $cellStyleP)->addText("Oficina de proyectos", ['size' => 7]);

$hTableP->addRow(230);
$hTableP->addCell($wLeft, array_merge($cellStyleP, ['vMerge' => 'continue']));
$hTableP->addCell($wMid, $cellStyleP)->addText("Revisado por:", ['size' => 7, 'bold' => true]);
$hTableP->addCell($wRight, $cellStyleP)->addText("Oficina de proyectos", ['size' => 7]);

$hTableP->addRow(230);
$hTableP->addCell($wLeft, array_merge($cellStyleP, ['vMerge' => 'continue']));
$hTableP->addCell($wMid, $cellStyleP)->addText("Aprobado por:", ['size' => 7, 'bold' => true]);
$hTableP->addCell($wRight, $cellStyleP)->addText("Oficina de proyectos", ['size' => 7]);
$headerPortada->addTextBreak(1);

// CONTENIDO PORTADA
$section->addTextBreak(4);
$section->addText('INFORME DE TRABAJO', 'portadaTitle', 'centerAlign');
$section->addText('OC – ' . $oc, 'portadaSub', 'centerAlign');
$section->addTextBreak(2);
$section->addText(strtoupper($nombreServicio), 'portadaSub', 'centerAlign');
$section->addText(strtoupper($empresasStr), 'portadaSub', 'centerAlign');
$section->addText(strtoupper($zonasStr), 'portadaSub', 'centerAlign');
$section->addText($mesActual . ' – ' . $anioActual, 'portadaSub', 'centerAlign');

$section->addTextBreak(4);

$tablePortada = $section->addTable(['borderSize' => 6, 'borderColor' => '000000', 'alignment' => Jc::CENTER, 'width' => 8000]);
$tablePortada->addRow(400, ['exactHeight' => true]);
$tablePortada->addCell(1000, ['bgColor' => 'F2F2F2'])->addText('N°',          ['bold' => true], 'centerAlign');
$tablePortada->addCell(4000, ['bgColor' => 'F2F2F2'])->addText('DESCRIPCIÓN', ['bold' => true], 'centerAlign');
$tablePortada->addCell(3000, ['bgColor' => 'F2F2F2'])->addText('FECHA',       ['bold' => true], 'centerAlign');

$tablePortada->addRow();
$tablePortada->addCell(1000)->addText('01', null, 'centerAlign');
$tablePortada->addCell(4000)->addText('Fecha de ejecución de trabajo', null, 'centerAlign');
$tablePortada->addCell(3000)->addText('          /          /          ', null, 'centerAlign');

// ==========================================
// SECCIÓN CON ENCABEZADO ESTRUCTURADO
// ==========================================
$sectionInfo = $phpWord->addSection();
$header = $sectionInfo->addHeader();

$cellStyle = ['borderSize' => 6, 'borderColor' => '000000', 'valign' => 'center'];

$headerTable = $header->addTable([
    'borderSize'  => 6,
    'borderColor' => '000000',
    'cellMargin'  => 40,
]);

$wLeft  = 5500;
$wMid   = 1700;
$wRight = 1800;

// --- FILA 1: Título | Logo (fusiona col B+C, filas 1-2) ---
$headerTable->addRow(300);
$headerTable->addCell($wLeft, $cellStyle)
    ->addText("INFORME OC-{$oc} {$tituloDinamico}", ['bold' => true, 'size' => 8], ['alignment' => Jc::CENTER]);
$logoCell = $headerTable->addCell($wMid + $wRight, array_merge($cellStyle, ['gridSpan' => 2, 'vMerge' => 'restart']));
if (file_exists($rutaLogoProfesional)) {
    $logoCell->addImage($rutaLogoProfesional, ['height' => 22, 'alignment' => Jc::CENTER]);
}

// --- FILA 2: Ubicación | Logo continúa ---
$headerTable->addRow(250);
$headerTable->addCell($wLeft, $cellStyle)
    ->addText("UBICACIÓN: {$ubicacionFinal}", ['bold' => true, 'size' => 8]);
$headerTable->addCell($wMid + $wRight, array_merge($cellStyle, ['gridSpan' => 2, 'vMerge' => 'continue']));

// --- FILA 3: Especialidad (inicia fusión vertical) | Elaborado por ---
$headerTable->addRow(230);
$headerTable->addCell($wLeft, array_merge($cellStyle, ['vMerge' => 'restart']))
    ->addText("ESPECIALIDAD: INSTALACIONES ELÉCTRICAS", ['bold' => true, 'size' => 8]);
$headerTable->addCell($wMid, $cellStyle)->addText("Elaborado por:", ['size' => 7, 'bold' => true]);
$headerTable->addCell($wRight, $cellStyle)->addText("Oficina de proyectos", ['size' => 7]);

// --- FILA 4 ---
$headerTable->addRow(230);
$headerTable->addCell($wLeft, array_merge($cellStyle, ['vMerge' => 'continue']));
$headerTable->addCell($wMid, $cellStyle)->addText("Revisado por:", ['size' => 7, 'bold' => true]);
$headerTable->addCell($wRight, $cellStyle)->addText("Oficina de proyectos", ['size' => 7]);

// --- FILA 5 ---
$headerTable->addRow(230);
$headerTable->addCell($wLeft, array_merge($cellStyle, ['vMerge' => 'continue']));
$headerTable->addCell($wMid, $cellStyle)->addText("Aprobado por:", ['size' => 7, 'bold' => true]);
$headerTable->addCell($wRight, $cellStyle)->addText("Oficina de proyectos", ['size' => 7]);

$header->addTextBreak(1);

// PIE DE PÁGINA
$footer = $sectionInfo->addFooter();
$footerTable = $footer->addTable(['width' => 100 * 50, 'unit' => 'pct']);
$footerTable->addRow();
$footerTable->addCell(5000)->addText("E-system Tic Perú S.A.C. / $mesElegante $anioActual", ['size' => 9, 'color' => '666666'], ['alignment' => Jc::LEFT]);
$footerTable->addCell(5000)->addPreserveText('Página {PAGE} de {NUMPAGES}', ['size' => 9, 'color' => '666666'], ['alignment' => Jc::RIGHT]);
// ==========================================
// ÍNDICE
// ==========================================
$sectionInfo->addPageBreak(); // <-- salto ANTES del índice
$sectionInfo->addText('Contenido', ['name' => 'Arial', 'size' => 14, 'bold' => true], 'centerAlign');
$sectionInfo->addTextBreak(1);
$fontStyleTOC = ['name' => 'Arial', 'size' => 9, 'color' => '000000'];
$sectionInfo->addTOC($fontStyleTOC, ['tabLeader' => \PhpOffice\PhpWord\Style\TOC::TAB_LEADER_DOT, 'depth' => 3]);
$sectionInfo->addPageBreak(); // <-- salto DESPUÉS del índice

// ==========================================
// CUERPO DEL INFORME TABLEROS
// ==========================================

$sectionInfo->addTitle('01. GENERALIDADES', 1);
$sectionInfo->addText("El mantenimiento de tableros eléctricos es el conjunto de actividades técnicas planificadas y sistemáticas destinadas a garantizar el correcto funcionamiento, seguridad, confiabilidad y vida útil de los tableros eléctricos dentro de una instalación.", null, 'justifyAlign');
$sectionInfo->addText("Este mantenimiento comprende la inspección, limpieza, ajuste, prueba y, de ser necesario, la reparación o reemplazo de los componentes eléctricos y mecánicos que conforman el tablero, tales como interruptores, barras, conexiones, protecciones, sistemas de control y señalización.", null, 'justifyAlign');
$sectionInfo->addText("Su finalidad principal es prevenir fallas, evitar interrupciones en el suministro eléctrico, reducir riesgos de accidentes (como cortocircuitos, sobrecalentamientos o incendios) y asegurar que el sistema opere conforme a las condiciones de diseño y a las normativas técnicas vigentes.", null, 'justifyAlign');
$sectionInfo->addText("El siguiente informe redacta de manera detallada los procedimientos empleados en el mantenimiento preventivo de tableros eléctricos en el área de $empresasStr – $zonasStr. Los criterios de ejecución, el personal comprometido, entre otros detalles considerados relevantes para el conocimiento del cliente.", null, 'justifyAlign');

$sectionInfo->addTitle('02. ALCANCE', 1);
$sectionInfo->addText("El trabajo de mantenimiento preventivo de tableros eléctricos en $empresasStr $zonasStr abarca la ejecución de actividades que garanticen el correcto funcionamiento del sistema, así mismo, el presente informe pretende explicar los procedimientos, materiales y equipos, así como la normativa aplicada para el desarrollo satisfactorio del mantenimiento.", null, 'justifyAlign');

$sectionInfo->addTitle('03. MARCO NORMATIVO', 1);
$sectionInfo->addTitle('03.1. NORMATIVA NACIONAL', 2);
$sectionInfo->addTitle('03.1.1. NORMA TÉCNICA DE CALIDAD DE LOS SERVICIOS ELÉCTRICOS', 3);
$sectionInfo->addText("Con el fin de asegurar un nivel satisfactorio en la prestación de servicios eléctricos y garantizar a los usuarios un suministro eléctrico continuo, adecuado, confiable y oportuno, se aprobó la Norma Técnica de Calidad de los Servicios Eléctricos mediante Decreto Supremo N° 020-97-EM, aplicable a todas las empresas que participan directa o indirectamente en la prestación y también en el uso de servicios eléctricos.", null, 'justifyAlign');

$sectionInfo->addTitle('03.1.2. CÓDIGO NACIONAL DE ELECTRICIDAD – UTILIZACIÓN 2006', 3);
$sectionInfo->addText("El código bajo comentario contiene reglas preventivas frente a los peligros derivados del uso de la electricidad a fin de salvaguardar las condiciones de seguridad de las personas, flora, fauna, propiedad, ambiente y patrimonio cultural de la Nación.", null, 'justifyAlign');
$sectionInfo->addText("Asimismo, establece medidas de prevención contra choques eléctricos e incendios, y las medidas apropiadas para la instalación, operación y mantenimiento de instalaciones eléctricas.", null, 'justifyAlign');

$sectionInfo->addTitle('03.1.3. REGLAMENTO DE SEGURIDAD Y SALUD EN EL TRABAJO CON ELECTRICIDAD 2013', 3);
$sectionInfo->addText("El presente reglamento es de aplicación obligatoria a todas las personas que participan en el desarrollo de las actividades relacionadas con el uso de la electricidad y/o con las instalaciones eléctricas; estando comprendidas las etapas de construcción, operación, mantenimiento, utilización, y trabajos de emergencias.", null, 'justifyAlign');

$sectionInfo->addTitle('03.2. NORMATIVA INTERNACIONAL', 2);
$sectionInfo->addTitle('03.2.1. NORMA PARA LA SEGURIDAD ELÉCTRICA EN LUGARES DE TRABAJO (NFPA 70E)', 3);
$sectionInfo->addText("Norma sobre las prácticas de trabajo relacionadas con la seguridad eléctrica, requerimientos de mantenimiento relacionados con la seguridad y otros controles administrativos en los lugares de trabajo a fin de prevenir riesgos de la energía eléctrica.", null, 'justifyAlign');

$sectionInfo->addTitle('03.2.2. PRACTICAS RECOMENDADAS DE MANTENIMIENTO ELÉCTRICO (NFPA 70B)', 3);
$sectionInfo->addText("Tienen como propósito reducir peligros a la vida y propiedad que resulten de la falla o malfuncionamiento del sistema y equipo eléctrico de tipo industrial.", null, 'justifyAlign');

$sectionInfo->addTitle('03.2.3. ANSI/NETA 2021: Standard for Acceptance Testing Specifications', 3);
$sectionInfo->addText("El propósito de estas especificaciones es asegurar que todo equipo eléctrico probado, proporcionado por contratista o dueño, este operativo dentro de las tolerancias de la industria y del fabricante e instaladas de acuerdo con las especificaciones de diseño.", null, 'justifyAlign');

$sectionInfo->addTitle('04. OBJETIVOS', 1);
$objetivos = [
    'Asegurar la continuidad del servicio eléctrico: Evitar interrupciones no programadas que afecten la operación.',
    'Prevenir fallas y averías: Detectar y corregir oportunamente condiciones anómalas como sobrecalentamientos.',
    'Proteger a las personas y equipos: minimizar riesgos eléctricos como descargas, cortocircuitos e incendios.',
    'Optimizar el rendimiento del sistema eléctrico: Mantener los equipos en condiciones adecuadas para su correcto desempeño.',
    'Prolongar la vida útil de los equipos: reducir el desgaste prematuro de los componentes.',
    'Facilitar la detección temprana de fallas: Mediante inspecciones y pruebas periódicas (termografía, etc.).',
    'Cumplir con las buenas prácticas de mantenimiento eléctrico y las normativas técnicas vigentes.'
];
foreach ($objetivos as $obj) {
    $sectionInfo->addListItem($obj, 0, null, \PhpOffice\PhpWord\Style\ListItem::TYPE_BULLET_FILLED, 'justifyAlign');
}

$sectionInfo->addTitle('05. PROCEDIMIENTO SST IMPLÍCITOS', 1);
$sectionInfo->addTitle('05.1. USO DEL EPP DE ACUERDO AL TIPO DE TRABAJO', 2);
$sectionInfo->addText("Cada trabajador cuenta con el EPP correspondiente a la tarea encargada de acuerdo al cuadro de puestos y funciones. Así mismo, su uso debe ser de carácter obligatorio durante toda la ejecución de las actividades.", null, 'justifyAlign');

$tableEpps = $sectionInfo->addTable($tableStyle);
$tableEpps->addRow();
$tableEpps->addCell(5000, ['bgColor' => 'F2F2F2'])->addText('EPP', ['bold' => true], 'centerAlign');
$tableEpps->addCell(5000, ['bgColor' => 'F2F2F2'])->addText('ES NECESARIO', ['bold' => true], 'centerAlign');

foreach ($epps as $epp) {
    $esNecesario = 'SI – Plataforma SST';
    if (stripos($epp, 'CARETA') !== false || stripos($epp, 'ARNES') !== false) {
        $esNecesario = 'NO';
    } elseif (stripos($epp, 'PROTECTORES DE OIDO') !== false || stripos($epp, 'GUANTES') !== false) {
        $esNecesario = 'SI';
    }
    $tableEpps->addRow();
    $tableEpps->addCell(5000)->addText(strtoupper($epp), ['size' => 10]);
    $tableEpps->addCell(5000)->addText($esNecesario, ['size' => 10], 'centerAlign');
}

$sectionInfo->addTitle('05.2. PROCEDIMIENTO DE BLOQUEO Y ETIQUETADO LOTO', 2);
$sectionInfo->addText("ESTE PASO DEBE REALIZARSE DE CARÁCTER OBLIGATORIO PARA CUALQUIER TRABAJO QUE IMPLIQUE RIESGO ELECTRICO.", ['bold' => true], 'justifyAlign');

$etapas = ['Estudio de la energía peligrosa', 'Identificación de puntos de bloqueo.', 'Selección de dispositivos de bloqueo.', 'Determinación de la secuencia de bloqueo y desbloqueo.'];
foreach ($etapas as $e) {
    $sectionInfo->addListItem($e, 0, null, \PhpOffice\PhpWord\Style\ListItem::TYPE_BULLET_FILLED);
}

$sectionInfo->addTitle('06. PERSONAL COMPROMETIDO', 1);
$sectionInfo->addText("Se detalla el personal empleado para la ejecución del servicio, cargo y funciones acorde a las tareas que desarrollará.", null, 'justifyAlign');

$tablePersonal = $sectionInfo->addTable($tableStyle);
$tablePersonal->addRow();
$headersPersonal = ['APELLIDOS', 'NOMBRE', 'CARGO', 'RESPONSABILIDADES'];
foreach ($headersPersonal as $h) {
    $tablePersonal->addCell(2500, ['bgColor' => 'F2F2F2'])->addText($h, ['bold' => true, 'size' => 10], 'centerAlign');
}

$idsPersonal = array_map(fn($p) => intval($p['id']), $personal);
if (!empty($idsPersonal)) {
    $idsStr = implode(',', $idsPersonal);
    $sqlPersonal = "SELECT id_empleado, nombrecom FROM empleado WHERE id_empleado IN ($idsStr)";
    $resultPersonal = mysqli_query($conexion, $sqlPersonal);
    $mapaEmpleados = [];
    while ($row = mysqli_fetch_assoc($resultPersonal)) {
        $mapaEmpleados[$row['id_empleado']] = $row['nombrecom'];
    }

    foreach ($personal as $persona) {
        $nombreCompleto = $mapaEmpleados[intval($persona['id'])] ?? 'Desconocido';
        $partesNombre = explode(' ', $nombreCompleto);
        $apellidos = $partesNombre[0] . (isset($partesNombre[1]) ? ' ' . $partesNombre[1] : '');
        $nombres = isset($partesNombre[2]) ? implode(' ', array_slice($partesNombre, 2)) : '';

        $cargo = $persona['rol'] == 'Supervisor' ? 'Supervisor SOMA' : 'Técnico ejecutor';
        $resp = $persona['rol'] == 'Supervisor' ? 'Supervisión de seguridad' : 'Ejecución de trabajos';

        $tablePersonal->addRow();
        $tablePersonal->addCell(2500)->addText($apellidos, ['size' => 10]);
        $tablePersonal->addCell(2500)->addText($nombres, ['size' => 10]);
        $tablePersonal->addCell(2500)->addText($cargo, ['size' => 10]);
        $tablePersonal->addCell(2500)->addText($resp, ['size' => 10]);
    }
}

$sectionInfo->addTitle('07. LISTA DE MATERIALES, HERRAMIENTAS Y EQUIPOS EMPLEADOS', 1);

// Materiales
$tableMat = $sectionInfo->addTable($tableStyle);
$tableMat->addRow();
$tableMat->addCell(4000, ['bgColor' => 'F2F2F2'])->addText('MATERIALES', ['bold' => true, 'size' => 10], 'centerAlign');
$tableMat->addCell(2000, ['bgColor' => 'F2F2F2'])->addText('UNIDAD', ['bold' => true, 'size' => 10], 'centerAlign');
$tableMat->addCell(4000, ['bgColor' => 'F2F2F2'])->addText('CARACTERÍSTICAS', ['bold' => true, 'size' => 10], 'centerAlign');

if (!empty($materiales)) {
    foreach ($materiales as $mat) {
        $nMat = is_array($mat) ? ($mat['nombre'] ?? $mat['material'] ?? '-') : $mat;
        $tableMat->addRow();
        $tableMat->addCell(4000)->addText($nMat, ['size' => 10]);
        $tableMat->addCell(2000)->addText('Und.', ['size' => 10], 'centerAlign');
        $tableMat->addCell(4000)->addText('-', ['size' => 10], 'centerAlign');
    }
}

$sectionInfo->addTextBreak(1);

// Herramientas
$tableHerr = $sectionInfo->addTable($tableStyle);
$tableHerr->addRow();
$tableHerr->addCell(4000, ['bgColor' => 'F2F2F2'])->addText('HERRAMIENTAS Y EQUIPOS', ['bold' => true, 'size' => 10], 'centerAlign');
$tableHerr->addCell(2000, ['bgColor' => 'F2F2F2'])->addText('UNIDAD', ['bold' => true, 'size' => 10], 'centerAlign');
$tableHerr->addCell(4000, ['bgColor' => 'F2F2F2'])->addText('CARACTERÍSTICAS', ['bold' => true, 'size' => 10], 'centerAlign');

if (!empty($herramientas)) {
    foreach ($herramientas as $herr) {
        $nHerr = is_array($herr) ? ($herr['nombre'] ?? $herr['herramienta'] ?? '-') : $herr;
        $tableHerr->addRow();
        $tableHerr->addCell(4000)->addText($nHerr, ['size' => 10]);
        $tableHerr->addCell(2000)->addText('1 Ud.', ['size' => 10], 'centerAlign');
        $tableHerr->addCell(4000)->addText('Dieléctrico / Medición', ['size' => 10], 'centerAlign');
    }
}

$sectionInfo->addTitle('08. PROCEDIMIENTOS DE EJECUCIÓN', 1);
$sectionInfo->addTitle('08.1. PREPARATIVOS PREVIOS A LA EJECUCIÓN', 2);
$previos = [
    'Informar al coordinador del área sobre los trabajos que se van a realizar y el tiempo que durarán sin corriente eléctrica.',
    'Identificar la instalación donde se va a realizar el trabajo.',
    'Elaboración de ATS y Check List de herramientas.',
    'Delimitar la zona de trabajo previa coordinación.'
];
foreach ($previos as $p) {
    $sectionInfo->addListItem($p, 0, null, \PhpOffice\PhpWord\Style\ListItem::TYPE_BULLET_FILLED, 'justifyAlign');
}

$sectionInfo->addTitle('08.2. EJECUCIÓN DE TRABAJO', 2);
$ejecucion = [
    'Cada trabajador debe desprenderse de objetos metálicos.',
    'Utilizar los equipos de protección individual dieléctricos necesarios.',
    'Identificación visual del tablero a intervenir e inspección externa.',
    'Utilización de cámara termográfica para determinar la carga térmica.',
    'Verificar el código de colores en los conductores eléctricos (ITM´s, Interruptores diferenciales).',
    'Limpieza de tablero eléctrico con soplador inalámbrico y/o alámbrico.',
    'Ajuste de pernos en interruptores termomagnéticos y diferenciales.',
    'Orden y limpieza de la zona.'
];
foreach ($ejecucion as $e) {
    $sectionInfo->addListItem($e, 0, null, \PhpOffice\PhpWord\Style\ListItem::TYPE_BULLET_FILLED, 'justifyAlign');
}

// ==========================================
// SECCIÓN 09: EVIDENCIA FOTOGRÁFICA
// ==========================================
$sectionInfo->addPageBreak();
$sectionInfo->addTitle('09. EVIDENCIA FOTOGRÁFICA', 1);
$sectionInfo->addTextBreak(1);

$sqlFotos = "SELECT em.id_equipo, em.nombre_equipo, em.tipo_equipo, pe.id_procedimiento, pm.nombre_procedimiento, pe.observacion, pa.ruta
             FROM equipos_mtto em
             LEFT JOIN procedimiento_equipos pe ON em.id_equipo = pe.id_equipo
             LEFT JOIN procedimientos_mtto pm ON pm.id_procedimiento = pe.id_procedimiento
             LEFT JOIN procedimiento_archivos pa ON pe.id_procedimiento_equipo = pa.id_procedimiento_equipo
             WHERE em.id_equipo IN ($idTableroStr) AND pa.id_item = 1
             ORDER BY em.tipo_equipo, em.nombre_equipo, pe.id_procedimiento ASC";

$resultFotos = mysqli_query($conexion, $sqlFotos);
$equiposPorTipo = [];

// Solo guardamos fotos que realmente existen
while ($verFotos = mysqli_fetch_assoc($resultFotos)) {
    $rutaFinal = resolverYConvertir($verFotos['ruta'] ?? '');

    if ($rutaFinal) {
        $idEquipo = $verFotos['id_equipo'];
        if (!isset($equiposPorTipo[$idEquipo])) {
            $equiposPorTipo[$idEquipo] = ['nombre' => $verFotos['nombre_equipo'], 'fotos' => []];
        }

        $observacionLimpia = $verFotos['observacion'] ?: $verFotos['nombre_procedimiento'];
        $observacionLimpia = str_ireplace(['OBS:', 'OBS :'], '', $observacionLimpia);
        $observacionLimpia = trim($observacionLimpia);

        $equiposPorTipo[$idEquipo]['fotos'][] = [
            'procedimiento' => $verFotos['nombre_procedimiento'],
            'observacion'   => $observacionLimpia,
            'ruta'          => $rutaFinal
        ];
    }
}

// Dibujamos la cuadrícula, sin cuadros vacíos, con nombre individual por equipo
foreach ($equiposPorTipo as $id => $equipoData) {
    $sectionInfo->addText(
        "EJECUCIÓN DE MANTENIMIENTO PREVENTIVO - " . strtoupper($equipoData['nombre']),
        ['bold' => true, 'size' => 12],
        'centerAlign'
    );
    $sectionInfo->addTextBreak(1);

    $fotos  = $equipoData['fotos'];
    $count  = count($fotos);

    for ($i = 0; $i < $count; $i += 2) {
        if ($i + 1 < $count) {
            // Par de fotos: tabla de dos columnas
            $tableF = $sectionInfo->addTable([
                'borderSize'  => 6,
                'borderColor' => '000000',
                'cellMargin'  => 80,
                'width'       => 100 * 50,
                'unit'        => 'pct',
            ]);
            $tableF->addRow(3000, ['exactHeight' => true]);

            $cell1 = $tableF->addCell(5000, ['valign' => 'center']);
            $cell1->addImage($fotos[$i]['ruta'], ['width' => 200, 'height' => 150, 'alignment' => Jc::CENTER]);

            $cell2 = $tableF->addCell(5000, ['valign' => 'center']);
            $cell2->addImage($fotos[$i + 1]['ruta'], ['width' => 200, 'height' => 150, 'alignment' => Jc::CENTER]);

            $tableF->addRow();
            $tableF->addCell(5000)->addText($fotos[$i]['observacion'],       ['size' => 9], 'justifyAlign');
            $tableF->addCell(5000)->addText($fotos[$i + 1]['observacion'],   ['size' => 9], 'justifyAlign');
        } else {
            // Última foto sola: tabla de una columna centrada
            $tableF = $sectionInfo->addTable([
                'borderSize'  => 6,
                'borderColor' => '000000',
                'cellMargin'  => 80,
                'alignment'   => Jc::CENTER,
            ]);
            $tableF->addRow(3000, ['exactHeight' => true]);

            $cell1 = $tableF->addCell(10000, ['valign' => 'center']);
            $cell1->addImage($fotos[$i]['ruta'], ['width' => 200, 'height' => 150, 'alignment' => Jc::CENTER]);

            $tableF->addRow();
            $tableF->addCell(10000)->addText($fotos[$i]['observacion'], ['size' => 9], 'justifyAlign');
        }

        $sectionInfo->addTextBreak(1);
    }
}
// ==========================================
// SECCIONES FINALES
// ==========================================
$sectionInfo->addTitle('10. CONCLUSIONES', 1);
$sectionInfo->addText("El manejo y manipulación de los equipos comprometidos se realizó con sumo cuidado y con los EPPS correspondientes.", null, 'justifyAlign');
$sectionInfo->addText("Se realizó el mantenimiento de tableros eléctricos en $empresasStr - $zonasStr (" . count($nombresEquipos) . " tableros eléctricos)", null, 'justifyAlign');
foreach (array_unique($nombresEquipos) as $eq) {
    $sectionInfo->addListItem($eq, 0, null, \PhpOffice\PhpWord\Style\ListItem::TYPE_BULLET_FILLED);
}

$sectionInfo->addTitle('11. OBSERVACIONES', 1);
$sectionInfo->addText("No se encontraron observaciones que comprometan la integridad de los equipos.", null, 'justifyAlign');

$sectionInfo->addTitle('12. RECOMENDACIONES', 1);
$sectionInfo->addText("Se recomienda realizar inspecciones y mantenimientos preventivos periódicos para conservar la seguridad, confiabilidad y vida útil del tablero eléctrico.", null, 'justifyAlign');

$sectionInfo->addTitle('13. ANEXOS', 1);
$sectionInfo->addText("CERTIFICADO DE CALIBRACIÓN DE PINZA AMPERIMÉTRICA.", null, 'justifyAlign');
$sectionInfo->addText("CERTIFICADO DE CALIBRACIÓN DE CÁMARA TERMOGRÁFICA.", null, 'justifyAlign');

// ==========================================
// GUARDAR DOCUMENTO
// ==========================================
$filename = 'INFORME_MTTO_TABLEROS_OC_' . $oc . '.docx';
header('Content-Type: application/vnd.openxmlformats-officedocument.wordprocessingml.document');
header('Content-Disposition: attachment;filename="' . $filename . '"');
header('Cache-Control: max-age=0');
$objWriter = IOFactory::createWriter($phpWord, 'Word2007');
$objWriter->save('php://output');
mysqli_close($conexion);
exit();

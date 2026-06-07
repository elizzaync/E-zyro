"""
Diccionarios de configuración de contenido por tipo de equipo.
Cada config define los textos estáticos del Word generado.
Usa {prov} como placeholder para la ubicación/provincia.
"""
from __future__ import annotations

# ─── Normativas compartidas (usadas en varios tipos) ────────────────────────

_NORM_NAC_011 = {
    "titulo": "03.1.1. NORMA TÉCNICA DE CALIDAD DE LOS SERVICIOS ELÉCTRICOS",
    "cuerpo": [
        "Con el fin de asegurar un nivel satisfactorio en la prestación de servicios eléctricos "
        "y garantizar a los usuarios un suministro eléctrico continuo, adecuado, confiable y "
        "oportuno, se aprobó la Norma Técnica de Calidad de los Servicios Eléctricos mediante "
        "Decreto Supremo N° 020-97-EM, aplicable a todas las empresas que participan directa o "
        "indirectamente en la prestación y también en el uso de servicios eléctricos.",
        "En el desarrollo de este informe, esta norma resulta relevante al establecer los "
        "indicadores de calidad y tolerancias para garantizar la calidad de producto.",
    ],
}
_NORM_NAC_011_SHORT = {
    "titulo": "03.1.1. NORMA TÉCNICA DE CALIDAD DE LOS SERVICIOS ELÉCTRICOS",
    "cuerpo": [
        "Aprobada mediante Decreto Supremo N° 020-97-EM, aplicable a todas las empresas que "
        "participan directa o indirectamente en la prestación y uso de servicios eléctricos.",
    ],
}
_NORM_NAC_012_FULL = {
    "titulo": "03.1.2. CÓDIGO NACIONAL DE ELECTRICIDAD – UTILIZACIÓN 2006",
    "cuerpo": [
        "El código bajo comentario contiene reglas preventivas frente a los peligros derivados "
        "del uso de la electricidad a fin de salvaguardar las condiciones de seguridad de las "
        "personas, flora, fauna, propiedad, ambiente y patrimonio cultural de la Nación.",
        "Asimismo, establece medidas de prevención contra choques eléctricos e incendios, y las "
        "medidas apropiadas para la instalación, operación y mantenimiento de instalaciones "
        "eléctricas.",
        "El código indica que, cumpliendo las reglas establecidas en el mismo, utilizando "
        "materiales y equipos eléctricos aprobados o certificados, y efectuando la instalación, "
        "operación y mantenimiento apropiados, con personal calificado y autorizado, se logrará "
        "una instalación esencialmente segura.",
        "El ámbito de aplicación del presente código comprende las instalaciones y equipos "
        "eléctricos en edificios, estructuras, predios y en general toda edificación destinada "
        "a vivienda, comercio, industria, recreación o servicios, que operan o puedan operar "
        "en el rango de baja tensión hasta 1,000 V, y en alta tensión desde más de 1,000 V "
        "hasta 36,000 V.",
    ],
}
_NORM_NAC_012_SHORT = {
    "titulo": "03.1.2. CÓDIGO NACIONAL DE ELECTRICIDAD – UTILIZACIÓN 2006",
    "cuerpo": [
        "Establece medidas de prevención contra choques eléctricos e incendios, y las medidas "
        "apropiadas para la instalación, operación y mantenimiento de instalaciones eléctricas.",
    ],
}
_NORM_NAC_012_MED = {
    "titulo": "03.1.2. CÓDIGO NACIONAL DE ELECTRICIDAD – UTILIZACIÓN 2006",
    "cuerpo": [
        "El código bajo comentario contiene reglas preventivas frente a los peligros derivados "
        "del uso de la electricidad a fin de salvaguardar las condiciones de seguridad de las "
        "personas, flora, fauna, propiedad, ambiente y patrimonio cultural de la Nación.",
        "Asimismo, establece medidas de prevención contra choques eléctricos e incendios, y las "
        "medidas apropiadas para la instalación, operación y mantenimiento de instalaciones "
        "eléctricas.",
    ],
}
_NORM_NAC_013_FULL = {
    "titulo": "03.1.3. REGLAMENTO DE SEGURIDAD Y SALUD EN EL TRABAJO CON ELECTRICIDAD 2013",
    "cuerpo": [
        "El presente reglamento es de aplicación obligatoria a todas las personas que participan "
        "en el desarrollo de las actividades relacionadas con el uso de la electricidad y/o con "
        "las instalaciones eléctricas; estando comprendidas las etapas de construcción, operación, "
        "mantenimiento, utilización, y trabajos de emergencias en las instalaciones eléctricas de "
        "generación, transmisión, distribución, incluyendo las conexiones para el suministro y "
        "comercialización.",
        "Básicamente, este reglamento tiene como objetivos: Proteger, preservar y mejorar "
        "continuamente la integridad psico-física de las personas que participan en el desarrollo "
        "de las actividades relacionadas con la electricidad; proteger a los usuarios y público en "
        "general contra los peligros de las instalaciones eléctricas; promover y mantener una "
        "cultura de prevención de riesgos laborales.",
    ],
}
_NORM_NAC_013_SHORT = {
    "titulo": "03.1.3. REGLAMENTO DE SEGURIDAD Y SALUD EN EL TRABAJO CON ELECTRICIDAD 2013",
    "cuerpo": [
        "Aplicación obligatoria a todas las personas que participan en el desarrollo de las "
        "actividades relacionadas con el uso de la electricidad y/o con las instalaciones "
        "eléctricas.",
    ],
}
_NORM_NAC_013_MED = {
    "titulo": "03.1.3. REGLAMENTO DE SEGURIDAD Y SALUD EN EL TRABAJO CON ELECTRICIDAD 2013",
    "cuerpo": [
        "El presente reglamento es de aplicación obligatoria a todas las personas que participan "
        "en el desarrollo de las actividades relacionadas con el uso de la electricidad y/o con "
        "las instalaciones eléctricas; estando comprendidas las etapas de construcción, operación, "
        "mantenimiento, utilización, y trabajos de emergencias.",
    ],
}
_NORM_INT_021_FULL = {
    "titulo": "03.2.1. NORMA PARA LA SEGURIDAD ELÉCTRICA EN LUGARES DE TRABAJO (NFPA 70E)",
    "cuerpo": [
        "Norma sobre las prácticas de trabajo relacionadas con la seguridad eléctrica, "
        "requerimientos de mantenimiento relacionados con la seguridad y otros controles "
        "administrativos en los lugares de trabajo a fin de prevenir riesgos de la energía "
        "eléctrica durante actividades tales como la instalación, inspección, operación, "
        "mantenimiento y demolición de conductores eléctricos, equipos eléctricos y conductores, "
        "equipos y canalizaciones de comunicación y señalización.",
        "De igual manera, esta norma incluye prácticas seguras de trabajo para empleados que "
        "desempeñan actividades que puedan exponerlos a peligros eléctricos.",
    ],
}
_NORM_INT_021_SHORT = {
    "titulo": "03.2.1. NORMA PARA LA SEGURIDAD ELÉCTRICA EN LUGARES DE TRABAJO (NFPA 70E)",
    "cuerpo": [
        "Norma sobre las prácticas de trabajo relacionadas con la seguridad eléctrica y "
        "requerimientos de mantenimiento a fin de prevenir riesgos de la energía eléctrica.",
    ],
}
_NORM_INT_022_FULL = {
    "titulo": "03.2.2. PRACTICAS RECOMENDADAS DE MANTENIMIENTO ELÉCTRICO (NFPA 70B)",
    "cuerpo": [
        "Tienen como propósito reducir peligros a la vida y propiedad que resulten de la falla "
        "o malfuncionamiento del sistema y equipo eléctrico de tipo industrial.",
        "En ese sentido, esta normativa establece recomendaciones para un efectivo mantenimiento "
        "eléctrico preventivo (EPM), especificando los requerimientos y consideraciones económicas "
        "que pueden ser utilizados para establecer un programa EPM.",
    ],
}
_NORM_INT_022_SHORT = {
    "titulo": "03.2.2. PRACTICAS RECOMENDADAS DE MANTENIMIENTO ELÉCTRICO (NFPA 70B)",
    "cuerpo": [
        "Propósito de reducir peligros a la vida y propiedad que resulten de la falla o "
        "malfuncionamiento del sistema y equipo eléctrico de tipo industrial.",
    ],
}
_NORM_INT_023_NETA = {
    "titulo": "03.2.3. ANSI/NETA 2021: Standard for Acceptance Testing Specifications",
    "cuerpo": [
        "El propósito de estas especificaciones es asegurar que todo equipo eléctrico probado, "
        "proporcionado por contratista o dueño, este operativo dentro de las tolerancias de la "
        "industria y del fabricante e instaladas de acuerdo con las especificaciones de diseño.",
        "Las especificaciones de las pruebas de aceptación se desarrollaron para ser utilizadas "
        "por los responsables de evaluar la idoneidad para la activación inicial de equipos y "
        "sistemas de energía eléctrica y para especificar pruebas de campo e inspecciones que "
        "aseguren que estos sistemas y aparatos funcionen satisfactoriamente.",
    ],
}
_NORM_INT_023_NETA_SHORT = {
    "titulo": "03.2.3. ANSI/NETA 2021: Standard for Acceptance Testing Specifications",
    "cuerpo": [
        "El propósito de estas especificaciones es asegurar que todo equipo eléctrico probado, "
        "proporcionado por contratista o dueño, este operativo dentro de las tolerancias de la "
        "industria y del fabricante e instaladas de acuerdo con las especificaciones de diseño.",
    ],
}
_NORM_INT_023_IEC = {
    "titulo": "03.2.3. IEC 62040 (1-2-3)",
    "cuerpo": ["Serie de normas para sistemas UPS aplicadas a nivel internacional."],
}
_NORM_INT_024_IEEE81 = {
    "titulo": "03.2.4. IEEE Std 81 - 2012: Guide for Measuring Earth Resistivity",
    "cuerpo": [
        "Mediante esta guía se pretende obtener e interpretar datos precisos y confiables para "
        "las mediciones de campo relacionados a los sistemas de puesta a tierra.",
    ],
}
_NORM_INT_024_IEEE1188 = {
    "titulo": "03.2.4. IEEE 1188",
    "cuerpo": [
        "Norma especializada para baterías VRLA utilizadas en UPS. Establece el procedimiento "
        "de inspección y pruebas de capacidad.",
    ],
}
_NORM_INT_025_IEC60076 = {
    "titulo": "03.2.5. IEC 60076",
    "cuerpo": [
        "Norma internacional principal para transformadores eléctricos. Define requisitos de "
        "diseño, parámetros eléctricos, pruebas de rutina y calentamiento.",
    ],
}
_NORM_INT_026_IEEE_C57 = {
    "titulo": "03.2.6. IEEE C57.12 / IEEE C57.94",
    "cuerpo": [
        "Normas emitidas por IEEE para transformadores secos y de aislamiento. Cubren pruebas "
        "de resistencia y relación de transformación.",
    ],
}
_NORM_NAC_014_NTP370 = {
    "titulo": "03.1.4. NTP 370.052:1999 MATERIALES QUE CONSTITUYEN EL POZO DE PUESTA A TIERRA",
    "cuerpo": [
        "Establece las condiciones que deben cumplir los materiales a ser utilizados en los pozos "
        "a tierra de protección que emplean electrodos de cobre. Comprende material circundante, "
        "elementos químicos para reducir la resistencia y recomendaciones para medición.",
    ],
}
_NORM_NAC_014_NTP_IEC = {
    "titulo": "03.1.4. NORMA TÉCNICA PERUANA NTP IEC 62040-1, NTP IEC 62040-2, NTP IEC 62040-3",
    "cuerpo": [
        "Adopta la IEC 62040-1 para Perú. Exige que las UPS cumplan condiciones de seguridad eléctrica.",
        "Adopta la IEC 62040-2. Regula la compatibilidad electromagnética (EMC) de las UPS.",
        "Adopta la IEC 62040-3. Define cómo se clasifican las UPS, su eficiencia y desempeño bajo carga.",
    ],
}

# ─── LOTO bullets compartidos ────────────────────────────────────────────────

_LOTO_BULLETS_SIMPLE = [
    "Aislar los circuitos a trabajar.",
    "Aplicación del dispositivo de bloqueo de fuentes de energía.",
    "Eliminar la energía almacenada a través de la línea tierra.",
]
_LOTO_BULLETS_ESTUDIO = [
    "Estudio de la energía peligrosa.",
    "Identificación de puntos de bloqueo.",
    "Selección de dispositivos de bloqueo.",
    "Determinación de la secuencia de bloqueo y desbloqueo.",
]
_LOTO_BULLETS_LUMINARIAS = _LOTO_BULLETS_ESTUDIO + [
    "Aislar los circuitos a trabajar.",
    "Aplicación del dispositivo de bloqueo de fuentes de energía.",
    "Eliminar la energía almacenada a través de la línea tierra. (Se debe liberar la tensión en el circuito)",
    "Se verifica la correcta ejecución de los procedimientos anteriores.",
    "Verificar que los componentes del circuito se encuentren intactos.",
    "Verificar el área para garantizar que todos los empleados afectados estén posicionados o alejados del área de manera segura.",
    "Notificar a todos los empleados afectados y al supervisor del sitio antes de volver a activar el suministro eléctrico.",
    "Retirar los dispositivos de bloqueo/etiquetado.",
    "Volver a activar el suministro eléctrico en el circuito intervenido.",
]

_LOTO_INTRO = (
    "ESTE PASO DEBE REALIZARSE DE CARÁCTER OBLIGATORIO PARA CUALQUIER TRABAJO "
    "QUE IMPLIQUE RIESGO ELECTRICO."
)
_LOTO_INTRO_EXTENDIDO = (
    "ESTE PASO DEBE REALIZARSE DE CARÁCTER OBLIGATORIO PARA CUALQUIER TRABAJO "
    "QUE IMPLIQUE RIESGO ELECTRICO Y NO SE DEBE OBVIAR BAJO NINGUN MOTIVO."
)

# ─── Personal intro compartido ───────────────────────────────────────────────

_PERSONAL_INTRO_BASE = [
    "Se detalla el personal empleado para la ejecución del servicio, cargo y funciones "
    "acorde a las tareas que desarrollará.",
]
_PERSONAL_INTRO_EXTENDIDO = [
    "Se detalla el personal empleado para la ejecución del servicio, cargo y funciones "
    "acorde a las tareas que desarrollará.",
    "El personal pertenece a la empresa, de ser un trabajador externo se indicará en el "
    "siguiente cuadro.",
    "De requerirse personal externo que no cuente con un contrato fijo por E-System se "
    "capacitará e informará de la metodología de trabajo, conjuntamente se supervisará dicho "
    "personal a fin verificar el estándar de calidad con el cual labora la empresa.",
]

# ─── Configuraciones por tipo ────────────────────────────────────────────────

CONFIGS: dict[str, dict] = {

    # ── POZOS A TIERRA ──────────────────────────────────────────────────────
    "pozos": {
        "titulo_documento": "MANTENIMIENTO PREVENTIVO POZO A TIERRA",
        "generalidades": [
            "Los sistemas de puesta a tierra son una parte importante de un sistema eléctrico, "
            "la importancia de este trabajo es ayudar a proporcionar una mayor seguridad a los "
            "usuarios del local al direccionar cualquier contacto indirecto de energía eléctrica "
            "a la puesta a tierra más cercana.",
            "Este mantenimiento comprende al conjunto de actividades técnicas programadas "
            "destinadas a verificar, conservar y optimizar las condiciones operativas del "
            "sistema de puesta a tierra, garantizando que su resistencia eléctrica se mantenga "
            "dentro de los parámetros establecidos por la normativa vigente y por los "
            "requerimientos de seguridad de la instalación.",
            "Este procedimiento tiene como finalidad asegurar la correcta disipación de "
            "corrientes de falla y descargas.",
            "El siguiente informe redacta de manera detallada los procedimientos empleados en "
            "el mantenimiento preventivo de pozo a tierra en TALMA - {prov}. Los criterios de "
            "ejecución, el personal comprometido, entre otros detalles considerados relevantes "
            "para el conocimiento del cliente.",
        ],
        "alcance": [
            "El mantenimiento preventivo de pozo a tierra en TALMA - {prov} abarca la ejecución "
            "de actividades que garanticen el correcto funcionamiento del sistema, así mismo, el "
            "presente informe pretende explicar los procedimientos, materiales y equipos, así como "
            "la normativa aplicada para el desarrollo satisfactorio del trabajo realizado.",
        ],
        "normativas": {
            "nacional": [
                {
                    "titulo": "03.1.1. NORMA TÉCNICA DE CALIDAD DE LOS SERVICIOS ELÉCTRICOS",
                    "cuerpo": [
                        "Con el fin de asegurar un nivel satisfactorio en la prestación de "
                        "servicios eléctricos y garantizar a los usuarios un suministro eléctrico "
                        "continuo, adecuado, confiable y oportuno, se aprobó la Norma Técnica de "
                        "Calidad de los Servicios Eléctricos mediante Decreto Supremo N° 020-97-EM.",
                    ],
                },
                {
                    "titulo": "03.1.2. CÓDIGO NACIONAL DE ELECTRICIDAD – UTILIZACIÓN 2006",
                    "cuerpo": [
                        "El código bajo comentario contiene reglas preventivas frente a los "
                        "peligros derivados del uso de la electricidad a fin de salvaguardar las "
                        "condiciones de seguridad de las personas, flora, fauna, propiedad, "
                        "ambiente y patrimonio cultural de la Nación.",
                    ],
                },
                {
                    "titulo": "03.1.3. REGLAMENTO DE SEGURIDAD Y SALUD EN EL TRABAJO CON ELECTRICIDAD 2013",
                    "cuerpo": [
                        "El presente reglamento es de aplicación obligatoria a todas las personas "
                        "que participan en el desarrollo de las actividades relacionadas con el uso "
                        "de la electricidad y/o con las instalaciones eléctricas.",
                    ],
                },
                _NORM_NAC_014_NTP370,
            ],
            "internacional": [
                {
                    "titulo": "03.2.1. NORMA PARA LA SEGURIDAD ELÉCTRICA EN LUGARES DE TRABAJO (NFPA 70E)",
                    "cuerpo": [
                        "Norma sobre las prácticas de trabajo relacionadas con la seguridad "
                        "eléctrica, requerimientos de mantenimiento relacionados con la seguridad "
                        "y otros controles administrativos en los lugares de trabajo a fin de "
                        "prevenir riesgos de la energía eléctrica.",
                    ],
                },
                {
                    "titulo": "03.2.2. PRACTICAS RECOMENDADAS DE MANTENIMIENTO ELÉCTRICO (NFPA 70B)",
                    "cuerpo": [
                        "Tienen como propósito reducir peligros a la vida y propiedad que resulten "
                        "de la falla o malfuncionamiento del sistema y equipo eléctrico.",
                    ],
                },
                {
                    "titulo": "03.2.3. ANSI/NETA 2021: Standard for Acceptance Testing Specifications",
                    "cuerpo": [
                        "El propósito de estas especificaciones es asegurar que todo equipo "
                        "eléctrico probado este operativo dentro de las tolerancias de la industria "
                        "y del fabricante e instaladas de acuerdo con las especificaciones de diseño.",
                    ],
                },
                _NORM_INT_024_IEEE81,
            ],
        },
        "objetivos": [
            "Descartar valores elevados (fueras de rango).",
            "Disminuir el riesgo de descargas eléctricas hacia el personal.",
            "Verificar la calidad de la tierra y el estado de los conectores CU.",
            "Verificar el Ohmiaje obtenido responda a la normativa del código nacional de "
            "electricidad de acuerdo a la función del local (MAX 15 OHM).",
            "Cumplir con los estándares de seguridad y salud en el trabajo a fin de garantizar "
            "la ejecución responsable de las actividades.",
            "Mantener un área despejada finalizando el mantenimiento.",
        ],
        "epp_intro": (
            "Cada trabajador cuenta con el EPP correspondiente a la tarea encargada de acuerdo "
            "al cuadro de puestos y funciones. Así mismo, se hace entrega de los EPPs indicados "
            "en la plataforma SST, los cuales son los indicados según el tipo de trabajo a realizar."
        ),
        "loto_intro": _LOTO_INTRO,
        "loto_bullets": _LOTO_BULLETS_SIMPLE,
        "personal_intro": _PERSONAL_INTRO_BASE,
        "preparativos": [
            "Verificar los permisos y autorizaciones.",
            "Elaboración de ATS.",
            "Verificar la zona de trabajo.",
            "Delimitar la zona de trabajo. Previa coordinación.",
            "Realizar un check list de la zona de trabajo.",
            "Revisar y elaborar el check list respectivo de las herramientas y equipos a utilizar en la tarea.",
        ],
        "ejecucion": [
            "Identificación del área del trabajo.",
            "Delimitar y señalizar lugar de trabajo.",
            "Realizar la limpieza de los mismos verificando que la caja de registro se encuentre en óptimas condiciones.",
            "Revisión de cables y verificación de estado de conductores.",
            "Realizar las mediciones correspondientes para obtener el valor inicial con el que se encontraron los pozos.",
            'De ser el caso, se procede a realizar el cambio del conector de Cu 3/4".',
            "Preparación de solución química THORGEL.",
            "Aplicar dosis química de THORGEL, esperar que la tierra absorba la primera dosis y luego aplicar la segunda dosis.",
            "Medir el valor final del pozo a tierra y anotarlo para plasmarlo en los protocolos correspondientes.",
            "Limpieza y pintado de la tapa de registro dejando señalizado con el código de cada puesta a tierra.",
            "Cambiar a una señalética fotoluminiscente del sistema de puesta a tierra.",
            "Anotar las mediciones y observaciones para la realización posterior del Informe Técnico.",
            "Orden y limpieza en la zona de trabajo.",
        ],
        "conclusiones": [
            "Se ejecutó el mantenimiento preventivo según lo indicado en el presente informe.",
            "Se efectúa la limpieza y lijado del electrodo y los cables para asegurar su buen desempeño.",
            "Se reemplazó al conector para así lograr tener un mejor agarre entre el cable y la varilla "
            "que se encuentra en el pozo a tierra.",
            "Se optimizó la conexión entre la varilla y los cables para asegurar su buen desempeño.",
            "Se evaluó el estado de las instalaciones y condicionantes de trabajo previamente a cualquier "
            "intervención realizado por E-SYSTEM TIC determinando que permita dichas actividades.",
        ],
        "observaciones": "No se encontraron observaciones operativas que impidan el funcionamiento habitual del sistema.",
        "recomendaciones": (
            "Se recomienda realizar el mantenimiento preventivo de manera anual para asegurar "
            "la operatividad y conductividad ideal del sistema de puesta a tierra."
        ),
        "tiene_anexos": False,
        "anexos": [],
    },

    # ── LUMINARIAS ──────────────────────────────────────────────────────────
    "luminarias": {
        "titulo_documento": "MANTENIMIENTO PREVENTIVO LUMINARIAS",
        "generalidades": [
            "El mantenimiento de luminarias es el conjunto de actividades técnicas planificadas "
            "y sistemáticas destinadas a garantizar el correcto funcionamiento, eficiencia "
            "lumínica, seguridad eléctrica y prolongación de la vida útil de los sistemas de "
            "iluminación, tanto en instalaciones interiores como exteriores.",
            "Este mantenimiento comprende acciones preventivas, predictivas y correctivas, tales "
            "como la limpieza de difusores y reflectores, verificación de conexiones eléctricas, "
            "revisión de componentes (balastos, drivers, portalámparas), medición de niveles de "
            "iluminación, y sustitución de lámparas o luminarias defectuosas.",
            "El siguiente informe redacta de manera detallada los procedimientos empleados en el "
            "mantenimiento preventivo de luminarias en el área de TALMA – {prov}. Los criterios "
            "de ejecución, el personal comprometido, entre otros detalles considerados relevantes "
            "para el conocimiento del cliente.",
        ],
        "alcance": [
            "El trabajo de mantenimiento preventivo de luminarias en TALMA – {prov} abarca la "
            "ejecución de actividades que garanticen el correcto funcionamiento del sistema, así "
            "mismo, el presente informe pretende explicar los procedimientos, materiales y equipos, "
            "así como la normativa aplicada para el desarrollo satisfactorio del mantenimiento.",
        ],
        "normativas": {
            "nacional": [_NORM_NAC_011, _NORM_NAC_012_FULL, _NORM_NAC_013_FULL],
            "internacional": [_NORM_INT_021_FULL, _NORM_INT_022_FULL, _NORM_INT_023_NETA],
        },
        "objetivos": [
            "Prevenir fallas eléctricas y mecánicas en las luminarias.",
            "Prolongar la vida útil de lámparas, drivers y demás componentes.",
            "Minimizar riesgos eléctricos (cortocircuitos, sobrecalentamientos).",
            "Notificar en caso se observe alguna falla o desperfecto en el sistema o instalaciones "
            "a fin de posteriormente el cliente pueda realizar los correctivos necesarios.",
            "Cumplir con las buenas prácticas de mantenimiento eléctrico y las normativas técnicas vigentes.",
        ],
        "epp_intro": (
            "Cada trabajador cuenta con el EPP correspondiente a la tarea encargada de acuerdo "
            "al cuadro de puestos y funciones. Así mismo, su uso debe ser de carácter obligatorio "
            "durante toda la ejecución de las actividades."
        ),
        "loto_intro": _LOTO_INTRO_EXTENDIDO,
        "loto_bullets": _LOTO_BULLETS_LUMINARIAS,
        "personal_intro": _PERSONAL_INTRO_EXTENDIDO,
        "preparativos": [
            "Informar al coordinador del área sobre los trabajos que se van a realizar y el tiempo "
            "que durarán en el área sin corriente eléctrica.",
            "Identificar la instalación donde se va a realizar el trabajo. Comprobar que las "
            "condiciones atmosféricas permiten el trabajo.",
            "Colocar la señalización vial si fuera necesario.",
            "Elaboración de ATS.",
            "Revisar y elaborar el CHECK LIST respectivo de las herramientas y equipos a utilizar en la tarea.",
            "Delimitar la zona de trabajo previa coordinación.",
            "Realizar un CHECK LIST de la zona de trabajo.",
            "Realizar un CHECK LIST de los equipos a intervenir.",
        ],
        "ejecucion": [
            "Inspeccionar la instalación donde se va a trabajar. Delimitar y señalizar el lugar de trabajo.",
            "Desprenderse de los objetos metálicos personales.",
            "Utilizar los equipos de protección individual necesarios en cada fase del trabajo.",
            "Limpieza de luminarias (retiro de polvo y suciedad) utilizando trapos industriales, soplador inalámbrico, escobas.",
            "Prueba de operatividad de equipos.",
            "Retirar todos los equipos, materiales y desechos del área.",
            "Orden y limpieza de la zona.",
        ],
        "conclusiones": [
            "El manejo y manipulación de los equipos comprometidos se realizó con sumo cuidado y con los EPPS correspondientes.",
            "Se realizó el mantenimiento de luminarias según lo indicado en el presente informe.",
        ],
        "observaciones": "No se encontraron observaciones.",
        "recomendaciones": "Se recomienda realizar el mantenimiento preventivo cada 6 o 12 meses según el entorno.",
        "tiene_anexos": True,
        "anexos": [],
    },

    # ── PARARRAYOS ──────────────────────────────────────────────────────────
    "pararrayos": {
        "titulo_documento": "MANTENIMIENTO PREVENTIVO PARARRAYOS",
        "generalidades": [
            "El mantenimiento de pararrayos es el conjunto de actividades técnicas orientadas a "
            "verificar, conservar y garantizar el correcto funcionamiento del sistema de protección "
            "contra descargas atmosféricas, asegurando que la energía del rayo sea conducida de "
            "forma segura hacia tierra sin afectar a las personas, equipos e infraestructura.",
            "Así mismo, garantizar que, ante la ocurrencia del fenómeno de descarga atmosférica, "
            "el sistema actúe de manera eficiente, disipando la corriente eléctrica hacia tierra "
            "sin generar riesgos eléctricos, incendios o daños en equipos sensibles.",
            "El siguiente informe redacta de manera detallada los procedimientos empleados en el "
            "mantenimiento preventivo de pararrayos en TALMA – {prov}. Los criterios de ejecución, "
            "el personal comprometido, entre otros detalles considerados relevantes para el "
            "conocimiento del cliente.",
        ],
        "alcance": [
            "El mantenimiento preventivo de pararrayos en TALMA – {prov} abarca la ejecución de "
            "actividades que garanticen el correcto funcionamiento del sistema, así mismo, el "
            "presente informe pretende explicar los procedimientos, materiales y equipos, así como "
            "la normativa aplicada para el desarrollo satisfactorio del trabajo realizado.",
        ],
        "normativas": {
            "nacional": [_NORM_NAC_011, _NORM_NAC_012_MED, _NORM_NAC_013_MED],
            "internacional": [_NORM_INT_021_FULL, _NORM_INT_022_FULL, _NORM_INT_023_NETA_SHORT],
        },
        "objetivos": [
            "Verificar la integridad física de los componentes del sistema.",
            "Comprobar la continuidad eléctrica de los conductores de bajada.",
            "Medir y asegurar valores adecuados del sistema de puesta a tierra.",
            "Detectar y corregir puntos de corrosión, sulfatación o conexiones defectuosas.",
            "Cumplir con las exigencias de normas técnicas nacionales e internacionales.",
            "Prevenir fallas ante eventos de descarga atmosférica.",
            "Notificar en caso se observe alguna falla o desperfecto en el sistema o instalaciones "
            "a fin de posteriormente el cliente pueda realizar los correctivos necesarios.",
            "Cumplir con las buenas prácticas de mantenimiento eléctrico y las normativas técnicas vigentes.",
        ],
        "epp_intro": (
            "Cada trabajador cuenta con el EPP correspondiente a la tarea encargada de acuerdo "
            "al cuadro de puestos y funciones. Así mismo, su uso debe ser de carácter obligatorio "
            "durante toda la ejecución de las actividades."
        ),
        "loto_intro": _LOTO_INTRO_EXTENDIDO,
        "loto_bullets": _LOTO_BULLETS_ESTUDIO,
        "personal_intro": _PERSONAL_INTRO_BASE,
        "preparativos": [
            "Verificar los permisos y autorizaciones.",
            "Elaboración de ATS.",
            "Verificar la zona de trabajo.",
            "Delimitar la zona de trabajo, Previa coordinación.",
            "Realizar un check list de la zona de trabajo.",
            "Revisar y elaborar el check list respectivo de las herramientas y equipos a utilizar en los trabajos.",
        ],
        "ejecucion": [
            "Mástil: Comprobación del estado de conservación y su fijación al mástil.",
            "Red conductora: Comprobación de la existencia y proceso de oxidación. Se deben revisar los anclajes y las oxidaciones.",
            "Toma de tierra: Comprobación de la continuidad eléctrica y la resistencia en ohms del cable, el estado de las abrazaderas y su tensado.",
            "Estudio de cobertura: Este servicio está orientando a determinar si la actual cobertura está lo suficientemente dimensionada para la seguridad de las dependencias.",
            "Limpieza de los cables de pararrayos.",
            "Retirar polvo mediante el uso de una pistola de aire.",
            "Limpieza con solvente dieléctrico de conexiones eléctricas.",
            "Reapretar todos los tornillos y tuercas, poniendo atención en cada componente que se esté reapretando para detectar si existen fallos.",
            "Orden y limpieza de la zona.",
        ],
        "conclusiones": [
            "El manejo y manipulación de los equipos comprometidos se realizó con sumo cuidado y con los EPPS correspondientes.",
            "Se realizó el mantenimiento preventivo de pararrayos sin inconvenientes.",
        ],
        "observaciones": "No se encontraron observaciones que comprometan la integridad de los equipos.",
        "recomendaciones": (
            "Se recomienda seguir con el cronograma de mantenimientos preventivos E-SYSTEM "
            "(cada 6 meses aprox.) a fin de prevenir fallas."
        ),
        "tiene_anexos": True,
        "anexos": [
            "CERTIFICADO DE CALIBRACIÓN DE PINZA AMPERIMÉTRICA.",
            "CERTIFICADO DE CALIBRACIÓN DE CÁMARA TERMOGRÁFICA.",
        ],
    },

    # ── TABLEROS ELÉCTRICOS ─────────────────────────────────────────────────
    "tableros": {
        "titulo_documento": "MANTENIMIENTO PREVENTIVO TABLEROS ELÉCTRICOS",
        "generalidades": [
            "El mantenimiento de tableros eléctricos es el conjunto de actividades técnicas "
            "planificadas y sistemáticas destinadas a garantizar el correcto funcionamiento, "
            "seguridad, confiabilidad y vida útil de los tableros eléctricos dentro de una "
            "instalación.",
            "Este mantenimiento comprende la inspección, limpieza, ajuste, prueba y, de ser "
            "necesario, la reparación o reemplazo de los componentes eléctricos y mecánicos que "
            "conforman el tablero, tales como interruptores, barras, conexiones, protecciones, "
            "sistemas de control y señalización.",
            "Su finalidad principal es prevenir fallas, evitar interrupciones en el suministro "
            "eléctrico, reducir riesgos de accidentes (como cortocircuitos, sobrecalentamientos "
            "o incendios) y asegurar que el sistema opere conforme a las condiciones de diseño y "
            "a las normativas técnicas vigentes.",
            "El siguiente informe redacta de manera detallada los procedimientos empleados en el "
            "mantenimiento preventivo de tableros eléctricos en el área de TALMA – {prov}. Los "
            "criterios de ejecución, el personal comprometido, entre otros detalles considerados "
            "relevantes para el conocimiento del cliente.",
        ],
        "alcance": [
            "El trabajo de mantenimiento preventivo de tableros eléctricos en TALMA {prov} abarca "
            "la ejecución de actividades que garanticen el correcto funcionamiento del sistema, así "
            "mismo, el presente informe pretende explicar los procedimientos, materiales y equipos, "
            "así como la normativa aplicada para el desarrollo satisfactorio del mantenimiento.",
        ],
        "normativas": {
            "nacional": [_NORM_NAC_011, _NORM_NAC_012_MED, _NORM_NAC_013_MED],
            "internacional": [_NORM_INT_021_SHORT, _NORM_INT_022_SHORT, _NORM_INT_023_NETA_SHORT],
        },
        "objetivos": [
            "Asegurar la continuidad del servicio eléctrico: Evitar interrupciones no programadas que afecten la operación.",
            "Prevenir fallas y averías: Detectar y corregir oportunamente condiciones anómalas como sobrecalentamientos.",
            "Proteger a las personas y equipos: minimizar riesgos eléctricos como descargas, cortocircuitos e incendios.",
            "Optimizar el rendimiento del sistema eléctrico: Mantener los equipos en condiciones adecuadas para su correcto desempeño.",
            "Prolongar la vida útil de los equipos: reducir el desgaste prematuro de los componentes.",
            "Facilitar la detección temprana de fallas: Mediante inspecciones y pruebas periódicas (termografía, etc.).",
            "Cumplir con las buenas prácticas de mantenimiento eléctrico y las normativas técnicas vigentes.",
        ],
        "epp_intro": (
            "Cada trabajador cuenta con el EPP correspondiente a la tarea encargada de acuerdo "
            "al cuadro de puestos y funciones. Así mismo, su uso debe ser de carácter obligatorio "
            "durante toda la ejecución de las actividades."
        ),
        "loto_intro": _LOTO_INTRO,
        "loto_bullets": _LOTO_BULLETS_ESTUDIO,
        "personal_intro": _PERSONAL_INTRO_BASE,
        "preparativos": [
            "Informar al coordinador del área sobre los trabajos que se van a realizar y el tiempo "
            "que durarán sin corriente eléctrica.",
            "Identificar la instalación donde se va a realizar el trabajo.",
            "Elaboración de ATS y Check List de herramientas.",
            "Delimitar la zona de trabajo previa coordinación.",
        ],
        "ejecucion": [
            "Cada trabajador debe desprenderse de objetos metálicos.",
            "Utilizar los equipos de protección individual dieléctricos necesarios.",
            "Identificación visual del tablero a intervenir e inspección externa.",
            "Utilización de cámara termográfica para determinar la carga térmica.",
            "Verificar el código de colores en los conductores eléctricos (ITM´s, Interruptores diferenciales).",
            "Limpieza de tablero eléctrico con soplador inalámbrico y/o alámbrico.",
            "Ajuste de pernos en interruptores termomagnéticos y diferenciales.",
            "Orden y limpieza de la zona.",
        ],
        "conclusiones": [
            "El manejo y manipulación de los equipos comprometidos se realizó con sumo cuidado y con los EPPS correspondientes.",
            "Se realizó el mantenimiento de tableros eléctricos según lo indicado en el presente informe.",
        ],
        "observaciones": "No se encontraron observaciones que comprometan la integridad de los equipos.",
        "recomendaciones": (
            "Se recomienda realizar inspecciones y mantenimientos preventivos periódicos para "
            "conservar la seguridad, confiabilidad y vida útil del tablero eléctrico."
        ),
        "tiene_anexos": True,
        "anexos": [
            "CERTIFICADO DE CALIBRACIÓN DE PINZA AMPERIMÉTRICA.",
            "CERTIFICADO DE CALIBRACIÓN DE CÁMARA TERMOGRÁFICA.",
        ],
    },

    # ── UPS ─────────────────────────────────────────────────────────────────
    "ups": {
        "titulo_documento": "MANTENIMIENTO PREVENTIVO UPS",
        "generalidades": [
            "Una UPS (Uninterruptible Power Supply) es un sistema de alimentación ininterrumpida "
            "que garantiza energía eléctrica continua y de calidad a cargas críticas (centros de "
            "datos, servidores, sistemas de telecomunicaciones, paneles de detección de incendios, "
            "etc.) frente a interrupciones, picos, ruidos eléctricos o variaciones de tensión.",
            "El mantenimiento preventivo consiste en un conjunto de actividades programadas "
            "destinadas a garantizar la continuidad, confiabilidad y calidad del suministro "
            "eléctrico, protegiéndolas frente a interrupciones y variaciones de tensión.",
            "El siguiente informe redacta de manera detallada los procedimientos empleados en el "
            "mantenimiento preventivo en el área de TALMA – {prov}. Los criterios de ejecución, "
            "el personal comprometido, entre otros detalles considerados relevantes para el "
            "conocimiento del cliente.",
        ],
        "alcance": [
            "El mantenimiento preventivo en TALMA – {prov} abarca la ejecución de actividades que "
            "garanticen el correcto funcionamiento del sistema, así mismo, el presente informe "
            "pretende explicar los procedimientos, materiales y equipos, así como la normativa "
            "aplicada para el desarrollo satisfactorio del trabajo realizado.",
        ],
        "normativas": {
            "nacional": [
                _NORM_NAC_011_SHORT,
                _NORM_NAC_012_SHORT,
                _NORM_NAC_013_SHORT,
                _NORM_NAC_014_NTP_IEC,
            ],
            "internacional": [
                _NORM_INT_021_SHORT,
                _NORM_INT_022_SHORT,
                _NORM_INT_023_IEC,
                _NORM_INT_024_IEEE1188,
            ],
        },
        "objetivos": [
            "Verificar el estado operativo de los módulos electrónicos del sistema de respaldo.",
            "Evaluar la condición y autonomía del banco de baterías.",
            "Detectar y corregir conexiones flojas, sulfatadas o recalentadas.",
            "Mantener una adecuada ventilación interna del equipo.",
            "Reducir el riesgo de fallas inesperadas en equipos críticos.",
            "Cumplir con las buenas prácticas de mantenimiento eléctrico y las normativas técnicas vigentes.",
        ],
        "epp_intro": (
            "Cada trabajador cuenta con el EPP correspondiente a la tarea encargada de acuerdo "
            "al cuadro de puestos y funciones."
        ),
        "loto_intro": _LOTO_INTRO,
        "loto_bullets": _LOTO_BULLETS_SIMPLE,
        "personal_intro": _PERSONAL_INTRO_BASE,
        "preparativos": [
            "Verificar los permisos y autorizaciones.",
            "Elaboración de ATS.",
            "Verificar la zona de trabajo.",
        ],
        "ejecucion": [
            "Delimitar y señalizar lugar de trabajo.",
            "Utilizar y verificar que contemos con los EPPS correspondientes.",
            "Revisar datos del equipo a intervenir.",
            "Des energización del equipo.",
            "Verificar la ausencia de tensión con instrumentos calibrados.",
            "Verificar estado del gabinete o carcasa (golpes, corrosión, pintura).",
            "Inspeccionar aisladores, borneras y soportes.",
            "Retiro de polvo con soplador inalámbrico, limpieza de bornes y conexiones.",
            "Ajuste de bornes.",
            "Mediciones de valores y verificación de ventiladores y alarmas.",
            "Orden y limpieza de la zona.",
        ],
        "conclusiones": [
            "Se realizó el mantenimiento preventivo del UPS sin inconvenientes.",
            "El manejo y manipulación de los equipos comprometidos se realizó con sumo cuidado y con los EPPS correspondientes.",
            "Se realizó la verificación del funcionamiento del equipo intervenido.",
            "Se evaluó el estado de las instalaciones y condicionantes de trabajo previamente a cualquier "
            "intervención realizada por E-SYSTEM TIC, determinando que permita dichas actividades.",
        ],
        "observaciones": "No se encontraron observaciones operativas.",
        "recomendaciones": (
            "Se recomienda seguir con el cronograma de mantenimientos preventivos E-SYSTEM "
            "(cada 6 meses aprox.) a fin de prevenir fallas."
        ),
        "tiene_anexos": False,
        "anexos": [],
    },

    # ── TRANSFORMADOR DE AISLAMIENTO ────────────────────────────────────────
    "transformador": {
        "titulo_documento": "MANTENIMIENTO PREVENTIVO TRANSFORMADOR DE AISLAMIENTO",
        "generalidades": [
            "Por su parte, un Transformador de Aislamiento es un equipo indispensable para aislar "
            "galvánicamente la carga de la red eléctrica, atenuando ruidos de línea, eliminando "
            "armónicos y proveyendo un neutro limpio para equipos electrónicos sensibles.",
            "El mantenimiento preventivo consiste en un conjunto de actividades programadas "
            "destinadas a garantizar la continuidad, confiabilidad y calidad del suministro "
            "eléctrico, protegiéndolas frente a interrupciones y variaciones de tensión.",
            "El siguiente informe redacta de manera detallada los procedimientos empleados en el "
            "mantenimiento preventivo en el área de TALMA – {prov}. Los criterios de ejecución, "
            "el personal comprometido, entre otros detalles considerados relevantes para el "
            "conocimiento del cliente.",
        ],
        "alcance": [
            "El mantenimiento preventivo en TALMA – {prov} abarca la ejecución de actividades que "
            "garanticen el correcto funcionamiento del sistema, así mismo, el presente informe "
            "pretende explicar los procedimientos, materiales y equipos, así como la normativa "
            "aplicada para el desarrollo satisfactorio del trabajo realizado.",
        ],
        "normativas": {
            "nacional": [_NORM_NAC_011_SHORT, _NORM_NAC_012_SHORT, _NORM_NAC_013_SHORT],
            "internacional": [
                _NORM_INT_021_SHORT,
                _NORM_INT_022_SHORT,
                _NORM_INT_025_IEC60076,
                _NORM_INT_026_IEEE_C57,
            ],
        },
        "objetivos": [
            "Verificar el estado operativo de los módulos electrónicos del sistema de respaldo.",
            "Evaluar la condición y autonomía del banco de baterías.",
            "Detectar y corregir conexiones flojas, sulfatadas o recalentadas.",
            "Mantener una adecuada ventilación interna del equipo.",
            "Reducir el riesgo de fallas inesperadas en equipos críticos.",
            "Cumplir con las buenas prácticas de mantenimiento eléctrico y las normativas técnicas vigentes.",
        ],
        "epp_intro": (
            "Cada trabajador cuenta con el EPP correspondiente a la tarea encargada de acuerdo "
            "al cuadro de puestos y funciones."
        ),
        "loto_intro": _LOTO_INTRO,
        "loto_bullets": _LOTO_BULLETS_SIMPLE,
        "personal_intro": _PERSONAL_INTRO_BASE,
        "preparativos": [
            "Verificar los permisos y autorizaciones.",
            "Elaboración de ATS.",
            "Verificar la zona de trabajo.",
        ],
        "ejecucion": [
            "Delimitar y señalizar lugar de trabajo.",
            "Utilizar y verificar que contemos con los EPPS correspondientes.",
            "Revisar datos del equipo a intervenir.",
            "Des energización del equipo.",
            "Verificar la ausencia de tensión con instrumentos calibrados.",
            "Verificar estado del gabinete o carcasa (golpes, corrosión, pintura).",
            "Inspeccionar aisladores, borneras y soportes.",
            "Retiro de polvo con soplador inalámbrico, limpieza de bornes y conexiones.",
            "Ajuste de bornes.",
            "Mediciones de valores y verificación de ventiladores y alarmas.",
            "Orden y limpieza de la zona.",
        ],
        "conclusiones": [
            "Se realizó el mantenimiento preventivo del transformador de aislamiento sin inconvenientes.",
            "El manejo y manipulación de los equipos comprometidos se realizó con sumo cuidado y con los EPPS correspondientes.",
            "Se realizó la verificación del funcionamiento del equipo intervenido.",
            "Se evaluó el estado de las instalaciones y condicionantes de trabajo previamente a cualquier "
            "intervención realizada por E-SYSTEM TIC, determinando que permita dichas actividades.",
        ],
        "observaciones": "No se encontraron observaciones operativas.",
        "recomendaciones": (
            "Se recomienda seguir con el cronograma de mantenimientos preventivos E-SYSTEM "
            "(cada 6 meses aprox.) a fin de prevenir fallas."
        ),
        "tiene_anexos": False,
        "anexos": [],
    },

    # ── UPS + TRANSFORMADOR DE AISLAMIENTO (combinado) ──────────────────────
    "ups_trans": {
        "titulo_documento": "MANTENIMIENTO PREVENTIVO UPS Y TRANS. DE AISLAMIENTO",
        "generalidades": [
            "Una UPS (Uninterruptible Power Supply) es un sistema de alimentación ininterrumpida "
            "que garantiza energía eléctrica continua y de calidad a cargas críticas (centros de "
            "datos, servidores, sistemas de telecomunicaciones, paneles de detección de incendios, "
            "etc.) frente a interrupciones, picos, ruidos eléctricos o variaciones de tensión.",
            "Por su parte, un Transformador de Aislamiento es un equipo indispensable para aislar "
            "galvánicamente la carga de la red eléctrica, atenuando ruidos de línea, eliminando "
            "armónicos y proveyendo un neutro limpio para equipos electrónicos sensibles.",
            "El mantenimiento preventivo consiste en un conjunto de actividades programadas "
            "destinadas a garantizar la continuidad, confiabilidad y calidad del suministro "
            "eléctrico, protegiéndolas frente a interrupciones y variaciones de tensión.",
            "El siguiente informe redacta de manera detallada los procedimientos empleados en el "
            "mantenimiento preventivo en el área de TALMA – {prov}. Los criterios de ejecución, "
            "el personal comprometido, entre otros detalles considerados relevantes para el "
            "conocimiento del cliente.",
        ],
        "alcance": [
            "El mantenimiento preventivo en TALMA – {prov} abarca la ejecución de actividades que "
            "garanticen el correcto funcionamiento del sistema, así mismo, el presente informe "
            "pretende explicar los procedimientos, materiales y equipos, así como la normativa "
            "aplicada para el desarrollo satisfactorio del trabajo realizado.",
        ],
        "normativas": {
            "nacional": [
                _NORM_NAC_011_SHORT,
                _NORM_NAC_012_SHORT,
                _NORM_NAC_013_SHORT,
                _NORM_NAC_014_NTP_IEC,
            ],
            "internacional": [
                _NORM_INT_021_SHORT,
                _NORM_INT_022_SHORT,
                _NORM_INT_023_IEC,
                _NORM_INT_024_IEEE1188,
                _NORM_INT_025_IEC60076,
                _NORM_INT_026_IEEE_C57,
            ],
        },
        "objetivos": [
            "Verificar el estado operativo de los módulos electrónicos del sistema de respaldo.",
            "Evaluar la condición y autonomía del banco de baterías.",
            "Detectar y corregir conexiones flojas, sulfatadas o recalentadas.",
            "Mantener una adecuada ventilación interna del equipo.",
            "Reducir el riesgo de fallas inesperadas en equipos críticos.",
            "Cumplir con las buenas prácticas de mantenimiento eléctrico y las normativas técnicas vigentes.",
        ],
        "epp_intro": (
            "Cada trabajador cuenta con el EPP correspondiente a la tarea encargada de acuerdo "
            "al cuadro de puestos y funciones."
        ),
        "loto_intro": _LOTO_INTRO,
        "loto_bullets": _LOTO_BULLETS_SIMPLE,
        "personal_intro": _PERSONAL_INTRO_BASE,
        "preparativos": [
            "Verificar los permisos y autorizaciones.",
            "Elaboración de ATS.",
            "Verificar la zona de trabajo.",
        ],
        "ejecucion": [
            "Delimitar y señalizar lugar de trabajo.",
            "Utilizar y verificar que contemos con los EPPS correspondientes.",
            "Revisar datos del equipo a intervenir.",
            "Des energización del equipo.",
            "Verificar la ausencia de tensión con instrumentos calibrados.",
            "Verificar estado del gabinete o carcasa (golpes, corrosión, pintura).",
            "Inspeccionar aisladores, borneras y soportes.",
            "Retiro de polvo con soplador inalámbrico, limpieza de bornes y conexiones.",
            "Ajuste de bornes.",
            "Mediciones de valores y verificación de ventiladores y alarmas.",
            "Orden y limpieza de la zona.",
        ],
        "conclusiones": [
            "Se realizó el mantenimiento preventivo del UPS sin inconvenientes.",
            "Se realizó el mantenimiento preventivo del transformador de aislamiento sin inconvenientes.",
            "El manejo y manipulación de los equipos comprometidos se realizó con sumo cuidado y con los EPPS correspondientes.",
            "Se realizó la verificación del funcionamiento del equipo intervenido.",
            "Se evaluó el estado de las instalaciones y condicionantes de trabajo previamente a cualquier "
            "intervención realizada por E-SYSTEM TIC, determinando que permita dichas actividades.",
        ],
        "observaciones": "No se encontraron observaciones operativas.",
        "recomendaciones": (
            "Se recomienda seguir con el cronograma de mantenimientos preventivos E-SYSTEM "
            "(cada 6 meses aprox.) a fin de prevenir fallas."
        ),
        "tiene_anexos": False,
        "anexos": [],
    },
}


def _tipo_from_equipos(equipos: list[dict]) -> str:
    """Derive the report type key from the equipos array."""
    tipos: set[str] = set()
    for eq in equipos:
        t = (eq.get("tipo") or "").upper()
        if "POZO" in t:
            tipos.add("pozos")
        elif "TABLERO" in t:
            tipos.add("tableros")
        elif "LUMINAR" in t:
            tipos.add("luminarias")
        elif "PARARR" in t:
            tipos.add("pararrayos")
        elif "UPS" in t:
            tipos.add("ups")
        elif "TRANS" in t or "AISLAMIENTO" in t:
            tipos.add("transformador")
    if tipos == {"ups", "transformador"}:
        return "ups_trans"
    if len(tipos) == 1:
        return tipos.pop()
    return "pozos"  # fallback


def get_config(equipos: list[dict], tipo_base_hint: str = "") -> dict:
    """Return the content config dict for the given equipment list."""
    # Try hint first (coarser, from frontend), then derive from equipo tipos
    hint = tipo_base_hint.lower()
    if hint in CONFIGS:
        return CONFIGS[hint]
    tipo = _tipo_from_equipos(equipos)
    return CONFIGS.get(tipo, CONFIGS["pozos"])

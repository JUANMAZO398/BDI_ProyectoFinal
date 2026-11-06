# Base de datos de paros de producción (vinilos y témperas)

Proyecto final de Bases de Datos I. Reemplaza el libro de Excel con macros que hoy hace de "base de datos" de los paros de producción de las líneas de envasado **Vinilos_1 a Vinilos_4**, con un modelo relacional normalizado (3FN) en **PostgreSQL**.

**Integrantes:** _Juan Jose Mazo Rodríguez_ · _Luis Felipe Meneses Cabezas_

## Problema
Las operarias anotan a mano la producción por hora, los códigos de paro y su duración (formato P-MTO-22). Mantenimiento lo transcribe a un Excel que presenta indicadores mensuales a la alta dirección. Ese Excel tiene 58 columnas, 18 grupos de columnas repetidas, fórmulas enlazadas a otros archivos que se rompen al copiarlas (`#VALUE!`, "YYYY") y datos derivados guardados. El diagnóstico completo está en [`docs/02_normalizacion.md`](docs/02_normalizacion.md).

## Estructura del repositorio
```
.
├── README.md
├── .gitignore
├── sql/
│   ├── 01_esquema.sql         # tablas, restricciones, índices y vistas
│   ├── 02_catalogos.sql       # máquinas, referencias, turnos, personas, códigos y subcódigos
│   ├── 03_migracion.sql       # carga del Excel -> modelo normalizado + verificación
│   ├── 04_consultas.sql       # consultas de negocio (productividad, códigos de paro, turnos…)
│   └── 05_restricciones.sql   # INSERT/UPDATE/DELETE y casos que la base rechaza
└── docs/
    ├── 01_modelo_conceptual_y_logico.md   # MER y modelo relacional (diagramas Mermaid)
    ├── 02_normalizacion.md                # 0FN -> 3FN, desnormalización y privacidad
    └── 03_diccionario_datos.md            # tablas y columnas
```

## Cómo reproducir la base de datos desde cero
Requisitos: PostgreSQL 14 o superior y DBeaver.

1. Cree una base de datos vacía (por ejemplo `paros_produccion`) y conéctese a ella desde DBeaver.
2. Abra cada archivo de `sql/` **en orden** y ejecútelo como script (**Alt + X**):
   `01_esquema.sql` → `02_catalogos.sql` → `03_migracion.sql` → `04_consultas.sql` → `05_restricciones.sql`
3. Al final de `03_migracion.sql` hay una consulta de verificación. Resultado esperado: 9 filas del Excel → 7 registros, 44 paros, 1984 minutos y 923 pacas, iguales en el Excel y en la base.
4. Para ver los rechazos de `05_restricciones.sql`, abra la pestaña de salida del servidor (*Output*).

Todos los scripts se pueden volver a ejecutar: `01_esquema.sql` borra y recrea los objetos.

## Modelo (resumen)
9 tablas: `maquina`, `referencia`, `maquina_referencia`, `turno`, `persona`, `codigo_paro`, `subcodigo_paro`, `registro_produccion` y `paro`. Las 18 columnas de códigos del Excel pasaron a filas de `paro`. Detalle en `docs/`.

## Estrategia de migración
1. Las filas de la hoja *Base de Datos* se cargan tal cual en una tabla temporal (`stg_excel`) con **solo datos primarios** (se descartan las fórmulas y las columnas calculadas).
2. Las filas que repiten fecha, máquina, turno, referencia y operaria se consolidan en un solo `registro_produccion`.
3. Las 18 columnas de código se convierten en filas de `paro` con `CROSS JOIN LATERAL (VALUES …)`.
4. Se verifica que filas, minutos y pacas coincidan entre origen y destino.

## Supuestos y limitaciones
- La **meta por hora** no estaba en el libro entregado: se definió en 52 pacas/hora (valor visto en el formato físico) en la tabla `stg_meta` de `03_migracion.sql`.
- La muestra tiene 9 filas (marzo de 2025). Los comparativos 2024 vs 2025 funcionan con los datos reales completos.
- Los subcódigos se tomaron de los gráficos del P-MTO-22; la lista puede estar incompleta.

## Datos personales
Los nombres reales de operarias y personal de mantenimiento **no se publican**. El repositorio usa seudónimos (`Operaria OP-001`, `Mantenimiento MT-001`) y el mapeo real se guarda fuera del repositorio (carpeta `privado/`, ignorada por Git). La vista `vw_persona_anonima` solo expone código y rol. Ver `docs/02_normalizacion.md`, sección 5.

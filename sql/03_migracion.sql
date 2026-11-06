-- 03_migracion.sql  |  Migración de la hoja 'Base de Datos' (9 filas) -> modelo normalizado.
-- Estrategia: (1) staging con las columnas originales SOLO con datos primarios (se descartan fórmulas y horas calculadas),
--             (2) cargar registro_produccion agrupando filas que son continuación del mismo registro,
--             (3) 'despivotar' las 18 columnas de código en filas de paro (LATERAL + VALUES),
--             (4) verificar integridad.

DROP TABLE IF EXISTS stg_excel;
CREATE TABLE stg_excel (
  n_fila INT, fecha DATE, maquina VARCHAR(20), operario VARCHAR(80), referencia VARCHAR(60), turno VARCHAR(30),
  pacas INT, horas NUMERIC(4,2),
  cod1 INT, cod2 INT, cod3 INT, cod4 INT, cod5 INT, cod6 INT, cod7 INT, cod8 INT, cod9 INT, cod10 INT, cod11 INT, cod12 INT, cod13 INT, cod14 INT, cod15 INT, cod16 INT, cod17 INT, cod18 INT,
  subcod1 VARCHAR(100), subcod3 VARCHAR(100), subcod5 VARCHAR(100), personal VARCHAR(80)
);

INSERT INTO stg_excel (n_fila, fecha, maquina, operario, referencia, turno, pacas, horas, cod1, cod2, cod3, cod4, cod5, cod6, cod7, cod8, cod9, cod10, cod11, cod12, cod13, cod14, cod15, cod16, cod17, cod18, subcod1, subcod3, subcod5, personal) VALUES
  (2, '2025-03-25', 'Vinilos_3', 'Operaria OP-013', 'Parchesitos 22cc (6 col)', '6am-4:30pm', 25, 9.5, NULL, NULL, NULL, NULL, 40, 117, 60, 60, NULL, NULL, NULL, NULL, NULL, NULL, 30, 70, 6, NULL, NULL, NULL, '5.8 Banda de sujeción y roscadores', NULL),
  (3, '2025-03-28', 'Vinilos_3', 'Operaria OP-013', 'Pintorcitos 22cc (6 col)', '6am-4:30pm', 64, 10.5, NULL, NULL, NULL, NULL, 30, 19, NULL, NULL, NULL, NULL, 10, NULL, NULL, NULL, NULL, 70, 6, NULL, NULL, NULL, '5.8 Banda de sujeción y roscadores', NULL),
  (4, '2025-03-28', 'Vinilos_3', 'Operaria OP-013', 'Pintorcitos 22cc (6 col)', '6am-4:30pm', NULL, NULL, NULL, NULL, NULL, NULL, 15, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '5.2 Sistema de dosificación de pintura, frontal posterior', NULL),
  (5, '2025-03-27', 'Vinilos_3', 'Operaria OP-014', 'Pintorcitos 22cc (6 col)', '6am-4:30pm', 56, 10.5, NULL, NULL, NULL, NULL, 5, 34, 10, 60, 15, 10, NULL, NULL, NULL, NULL, NULL, 70, 6, NULL, NULL, NULL, '5.11 Lavado de boquilla', NULL),
  (6, '2025-03-26', 'Vinilos_3', 'Operaria OP-013', 'Pintorcitos 22cc (6 col)', '6am-4:30pm', 57, 10.5, NULL, NULL, NULL, NULL, 80, 37, 10, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 70, 6, NULL, NULL, NULL, '5.2 Sistema de dosificación de pintura, frontal posterior', 'Mantenimiento MT-003'),
  (7, '2025-03-28', 'Vinilos_2', 'Operaria OP-042', 'Parchesitos 125 cc', '6am-4:30pm', 245, 10.5, NULL, NULL, NULL, NULL, NULL, NULL, 10, 60, 201, NULL, NULL, NULL, NULL, NULL, NULL, 70, 6, NULL, NULL, NULL, NULL, NULL),
  (8, '2025-03-27', 'Vinilos_2', 'Operaria OP-022', 'Parchesitos 125 cc', '6am-4:30pm', 276, 10.5, NULL, NULL, NULL, NULL, 25, 141, 10, 60, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 70, 6, NULL, NULL, NULL, '5.2 Sistema de dosificación de pintura, frontal posterior', 'Mantenimiento MT-002'),
  (9, '2025-03-26', 'Vinilos_2', 'Operaria OP-022', 'Parchesitos 125 cc', '6am-4:30pm', 200, 10.5, NULL, NULL, NULL, NULL, 10, 263, 15, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 5, 70, 6, NULL, NULL, NULL, '5.8 Banda de sujeción y roscadores', 'Mantenimiento MT-001'),
  (10, '2025-03-26', 'Vinilos_2', 'Operaria OP-022', 'Parchesitos 125 cc', '6am-4:30pm', NULL, NULL, NULL, NULL, NULL, NULL, 10, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '5.5 Transfer y pisador de tapa', NULL);

-- Meta por hora: NO existe en el libro. Se define aquí (supuesto del equipo). Cambie los valores si conoce la meta real.
-- 52 = la meta manuscrita en el formato físico del P-MTO-22 (Vinilos_2, Rojo 125cc).
DROP TABLE IF EXISTS stg_meta;
CREATE TABLE stg_meta (maquina VARCHAR(20) PRIMARY KEY, meta_por_hora INT NOT NULL);
INSERT INTO stg_meta VALUES ('Vinilos_1',52),('Vinilos_2',52),('Vinilos_3',52),('Vinilos_4',52);

-- 2) registro_produccion: las filas 4 y 10 del Excel repiten fecha/máquina/turno/referencia/operaria de las filas 3 y 9
--    (son paros adicionales del mismo registro, botón 'Ingreso Sub Código'); se consolidan con GROUP BY.
INSERT INTO registro_produccion (fecha, id_maquina, id_turno, id_referencia, id_operaria, pacas_producidas, horas_trabajadas, meta_por_hora)
SELECT s.fecha, m.id_maquina, t.id_turno, r.id_referencia, p.id_persona,
       MAX(s.pacas), MAX(s.horas), MAX(sm.meta_por_hora)
FROM stg_excel s
JOIN maquina m    ON m.nombre = s.maquina
JOIN turno t      ON t.nombre = s.turno
JOIN referencia r ON r.nombre = s.referencia
JOIN persona p    ON p.nombre = s.operario AND p.rol = 'OPERARIA'
JOIN stg_meta sm  ON sm.maquina = s.maquina
GROUP BY s.fecha, m.id_maquina, t.id_turno, r.id_referencia, p.id_persona;

-- 3) paro: una fila por cada código con minutos > 0 (se elimina el grupo repetitivo de 18 columnas).
INSERT INTO paro (id_registro, id_codigo_paro, id_subcodigo, minutos, id_persona)
SELECT rp.id_registro, u.codigo, sc.id_subcodigo, u.minutos, pe.id_persona
FROM stg_excel s
JOIN maquina m    ON m.nombre = s.maquina
JOIN turno t      ON t.nombre = s.turno
JOIN referencia r ON r.nombre = s.referencia
JOIN persona o    ON o.nombre = s.operario AND o.rol = 'OPERARIA'
JOIN registro_produccion rp ON rp.fecha = s.fecha AND rp.id_maquina = m.id_maquina AND rp.id_turno = t.id_turno
                           AND rp.id_referencia = r.id_referencia AND rp.id_operaria = o.id_persona
CROSS JOIN LATERAL (VALUES
  (1, s.cod1, split_part(s.subcod1,' ',1)),
  (2, s.cod2, NULL::text),
  (3, s.cod3, split_part(s.subcod3,' ',1)),
  (4, s.cod4, NULL::text),
  (5, s.cod5, split_part(s.subcod5,' ',1)),
  (6, s.cod6, NULL::text),
  (7, s.cod7, NULL::text),
  (8, s.cod8, NULL::text),
  (9, s.cod9, NULL::text),
  (10, s.cod10, NULL::text),
  (11, s.cod11, NULL::text),
  (12, s.cod12, NULL::text),
  (13, s.cod13, NULL::text),
  (14, s.cod14, NULL::text),
  (15, s.cod15, NULL::text),
  (16, s.cod16, NULL::text),
  (17, s.cod17, NULL::text),
  (18, s.cod18, NULL::text)
) AS u(codigo, minutos, sub)
LEFT JOIN subcodigo_paro sc ON sc.codigo = u.sub AND sc.id_codigo_paro = u.codigo
LEFT JOIN persona pe ON pe.nombre = s.personal AND u.codigo = 5
WHERE COALESCE(u.minutos,0) > 0;

-- 4) Verificación de integridad (esperado: filas_excel=9, registros=7, paros=44, minutos=1984).
SELECT (SELECT COUNT(*) FROM stg_excel) AS filas_excel,
       (SELECT COUNT(*) FROM registro_produccion) AS registros,
       (SELECT COUNT(*) FROM paro) AS paros,
       (SELECT SUM(COALESCE(cod1,0)+COALESCE(cod2,0)+COALESCE(cod3,0)+COALESCE(cod4,0)+COALESCE(cod5,0)+COALESCE(cod6,0)+COALESCE(cod7,0)+COALESCE(cod8,0)+COALESCE(cod9,0)+COALESCE(cod10,0)+COALESCE(cod11,0)+COALESCE(cod12,0)+COALESCE(cod13,0)+COALESCE(cod14,0)+COALESCE(cod15,0)+COALESCE(cod16,0)+COALESCE(cod17,0)+COALESCE(cod18,0)) FROM stg_excel) AS minutos_excel,
       (SELECT SUM(minutos) FROM paro) AS minutos_bd,
       (SELECT SUM(pacas) FROM stg_excel) AS pacas_excel,
       (SELECT SUM(pacas_producidas) FROM registro_produccion) AS pacas_bd;

-- Paros cuyo subcódigo no se pudo enlazar (debe devolver 0 filas).
SELECT s.n_fila, s.subcod5 FROM stg_excel s
WHERE s.subcod5 IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM subcodigo_paro sc WHERE sc.codigo = split_part(s.subcod5,' ',1));

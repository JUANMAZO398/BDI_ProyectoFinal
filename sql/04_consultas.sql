-- 04_consultas.sql  |  Consultas de negocio. Ajuste el rango de fechas en cada WHERE según los datos cargados.

-- Q1. % de productividad por máquina y mes (INNER JOIN + SUM + GROUP BY + rango de fechas)
SELECT m.nombre AS maquina, EXTRACT(YEAR FROM r.fecha)::INT AS anio, EXTRACT(MONTH FROM r.fecha)::INT AS mes,
       SUM(r.pacas_producidas) AS pacas,
       ROUND(100.0 * SUM(r.pacas_producidas) * m.factor_produccion / NULLIF(SUM(r.meta_por_hora * r.horas_trabajadas),0), 1) AS pct_productividad
FROM registro_produccion r
JOIN maquina m ON m.id_maquina = r.id_maquina
WHERE r.fecha BETWEEN DATE '2024-01-01' AND DATE '2025-12-31'
GROUP BY m.nombre, m.factor_produccion, anio, mes
ORDER BY m.nombre, anio, mes;

-- Q1b. Comparativo entre años (CTE + FILTER): cada fila = máquina y mes; columnas = años
WITH prod AS (
  SELECT m.nombre AS maquina, EXTRACT(YEAR FROM r.fecha)::INT AS anio, EXTRACT(MONTH FROM r.fecha)::INT AS mes,
         100.0 * SUM(r.pacas_producidas) * m.factor_produccion / NULLIF(SUM(r.meta_por_hora * r.horas_trabajadas),0) AS pct
  FROM registro_produccion r JOIN maquina m ON m.id_maquina = r.id_maquina
  GROUP BY m.nombre, m.factor_produccion, anio, mes
)
SELECT maquina, mes,
       ROUND(MAX(pct) FILTER (WHERE anio = 2024), 1) AS pct_2024,
       ROUND(MAX(pct) FILTER (WHERE anio = 2025), 1) AS pct_2025,
       ROUND(MAX(pct) FILTER (WHERE anio = 2025) - MAX(pct) FILTER (WHERE anio = 2024), 1) AS diferencia
FROM prod GROUP BY maquina, mes ORDER BY maquina, mes;

-- Q2. Participación porcentual de cada código de paro (LEFT JOIN para listar los 18 códigos, subconsultas)
SELECT c.id_codigo_paro, c.descripcion,
       COALESCE(t.minutos, 0) AS minutos,
       ROUND(100.0 * COALESCE(t.minutos, 0) / (SELECT SUM(horas_trabajadas * 60) FROM registro_produccion WHERE fecha BETWEEN DATE '2025-01-01' AND DATE '2025-12-31'), 2) AS pct_del_tiempo_trabajado,
       ROUND(100.0 * COALESCE(t.minutos, 0) / NULLIF((SELECT SUM(minutos) FROM paro p JOIN registro_produccion r USING (id_registro) WHERE r.fecha BETWEEN DATE '2025-01-01' AND DATE '2025-12-31'),0), 2) AS pct_del_total_de_paros
FROM codigo_paro c
LEFT JOIN (SELECT p.id_codigo_paro, SUM(p.minutos) AS minutos
           FROM paro p JOIN registro_produccion r ON r.id_registro = p.id_registro
           WHERE r.fecha BETWEEN DATE '2025-01-01' AND DATE '2025-12-31'
           GROUP BY p.id_codigo_paro) t ON t.id_codigo_paro = c.id_codigo_paro
ORDER BY c.id_codigo_paro;

-- Q3. Detalle por subcódigo de los códigos 01, 03 y 05 (% dentro de cada código con función de ventana)
SELECT c.id_codigo_paro, COALESCE(s.codigo || ' ' || s.descripcion, '(en blanco)') AS subcodigo,
       SUM(p.minutos) AS minutos,
       ROUND(100.0 * SUM(p.minutos) / SUM(SUM(p.minutos)) OVER (PARTITION BY c.id_codigo_paro), 1) AS pct_dentro_del_codigo
FROM paro p
JOIN codigo_paro c ON c.id_codigo_paro = p.id_codigo_paro
LEFT JOIN subcodigo_paro s ON s.id_subcodigo = p.id_subcodigo
WHERE p.id_codigo_paro IN (1, 3, 5)
GROUP BY c.id_codigo_paro, s.codigo, s.descripcion
ORDER BY c.id_codigo_paro, s.codigo;

-- Q3b. Código 05 por subcódigo y tipo de personal (Operarios / Mantenimiento / en blanco), como el gráfico del P-MTO-22
SELECT s.codigo || ' ' || s.descripcion AS subcodigo,
       COALESCE(pe.rol, '(en blanco)') AS area,
       SUM(p.minutos) AS minutos
FROM paro p
JOIN subcodigo_paro s ON s.id_subcodigo = p.id_subcodigo
LEFT JOIN persona pe ON pe.id_persona = p.id_persona
WHERE p.id_codigo_paro = 5
GROUP BY s.codigo, s.descripcion, pe.rol
ORDER BY s.codigo;

-- Q4. Comparación del desempeño entre turnos (JOIN + agregaciones + subconsulta correlacionada)
SELECT t.nombre AS turno, COUNT(*) AS registros,
       SUM(r.pacas_producidas) AS pacas,
       ROUND(SUM(r.horas_trabajadas), 1) AS horas,
       ROUND(100.0 * SUM(r.pacas_producidas) / NULLIF(SUM(r.meta_por_hora * r.horas_trabajadas),0), 1) AS pct_productividad_sin_factor,
       (SELECT COALESCE(SUM(p.minutos),0) FROM paro p JOIN registro_produccion r2 ON r2.id_registro = p.id_registro WHERE r2.id_turno = t.id_turno) AS minutos_de_paro
FROM registro_produccion r
JOIN turno t ON t.id_turno = r.id_turno
GROUP BY t.id_turno, t.nombre
ORDER BY pct_productividad_sin_factor DESC;

-- Q5. Tiempo faltante por registro: tiempo improductivo esperado menos paros reportados (CTE + HAVING)
WITH base AS (
  SELECT v.id_registro, v.fecha, v.maquina, v.horas_trabajadas * 60 AS min_trabajados,
         v.horas_trabajadas * 60 * (1 - v.pct_productividad / 100.0) AS min_improductivos,
         COALESCE(SUM(p.minutos), 0) AS min_reportados
  FROM vw_productividad v LEFT JOIN paro p ON p.id_registro = v.id_registro
  GROUP BY v.id_registro, v.fecha, v.maquina, v.horas_trabajadas, v.pct_productividad
)
SELECT fecha, maquina, ROUND(min_improductivos) AS min_improductivos, min_reportados,
       ROUND(min_improductivos - min_reportados) AS tiempo_faltante
FROM base
GROUP BY fecha, maquina, min_improductivos, min_reportados
HAVING ABS(min_improductivos - min_reportados) > 30       -- registros con diferencia relevante
ORDER BY ABS(min_improductivos - min_reportados) DESC;

-- Q6. Códigos de paro que nunca se han usado (LEFT JOIN ... IS NULL)
SELECT c.id_codigo_paro, c.descripcion
FROM codigo_paro c LEFT JOIN paro p ON p.id_codigo_paro = c.id_codigo_paro
WHERE p.id_paro IS NULL ORDER BY c.id_codigo_paro;

-- Q7. Personal de mantenimiento con más minutos de intervención (HAVING)
SELECT pe.codigo, SUM(p.minutos) AS minutos, COUNT(*) AS intervenciones
FROM paro p JOIN persona pe ON pe.id_persona = p.id_persona
WHERE pe.rol = 'MANTENIMIENTO'
GROUP BY pe.codigo
HAVING SUM(p.minutos) > 10
ORDER BY minutos DESC;

-- Q8. Registros con más minutos de paro que el promedio (subconsulta en HAVING)
SELECT r.fecha, m.nombre AS maquina, SUM(p.minutos) AS minutos_paro
FROM registro_produccion r
JOIN maquina m ON m.id_maquina = r.id_maquina
JOIN paro p ON p.id_registro = r.id_registro
GROUP BY r.id_registro, r.fecha, m.nombre
HAVING SUM(p.minutos) > (SELECT AVG(t.s) FROM (SELECT SUM(minutos) AS s FROM paro GROUP BY id_registro) t)
ORDER BY minutos_paro DESC;

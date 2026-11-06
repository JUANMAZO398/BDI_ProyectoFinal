-- 01_esquema.sql  |  PostgreSQL 14+  |  Esquema normalizado (3FN) de paros de producción
-- Ejecutar primero. Es re-ejecutable: borra y recrea todo.

DROP VIEW  IF EXISTS vw_productividad, vw_persona_anonima CASCADE;
DROP TABLE IF EXISTS paro, registro_produccion, subcodigo_paro, codigo_paro, maquina_referencia,
                     persona, turno, referencia, maquina, stg_excel, stg_meta CASCADE;

-- ---------- Catálogos ----------
CREATE TABLE maquina (
  id_maquina        SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre            VARCHAR(20)  NOT NULL UNIQUE,
  factor_produccion NUMERIC(4,2) NOT NULL DEFAULT 1.00 CHECK (factor_produccion > 0)  -- antes: SI anidado en hoja Tiempos
);

CREATE TABLE referencia (
  id_referencia INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre        VARCHAR(60) NOT NULL UNIQUE,
  unidades_por_display SMALLINT CHECK (unidades_por_display > 0),   -- 'Unidad por display' del Excel (vacío en la muestra)
  displays_por_paca    SMALLINT CHECK (displays_por_paca > 0)       -- 'Display por paca' del Excel (vacío en la muestra)
);

-- Qué referencias puede producir cada máquina (N:M)
CREATE TABLE maquina_referencia (
  id_maquina    SMALLINT NOT NULL REFERENCES maquina(id_maquina)       ON DELETE CASCADE ON UPDATE CASCADE,
  id_referencia INT      NOT NULL REFERENCES referencia(id_referencia) ON DELETE CASCADE ON UPDATE CASCADE,
  unidades_por_minuto NUMERIC(6,2) CHECK (unidades_por_minuto > 0),  -- 'Unidades producidas cada minuto' (depende de máquina+referencia)
  PRIMARY KEY (id_maquina, id_referencia)
);

CREATE TABLE turno (
  id_turno    SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre      VARCHAR(30) NOT NULL UNIQUE,
  hora_inicio TIME NOT NULL,
  hora_fin    TIME NOT NULL
);

-- Operarias y personal de mantenimiento. 'codigo' permite anonimizar (ver vw_persona_anonima).
CREATE TABLE persona (
  id_persona INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo     VARCHAR(10) NOT NULL UNIQUE,
  nombre     VARCHAR(80) NOT NULL,
  rol        VARCHAR(13) NOT NULL CHECK (rol IN ('OPERARIA','MANTENIMIENTO')),
  activo     BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE codigo_paro (
  id_codigo_paro SMALLINT PRIMARY KEY CHECK (id_codigo_paro BETWEEN 1 AND 18),
  descripcion    VARCHAR(100) NOT NULL UNIQUE
);

-- Subcódigos de los códigos 1, 3 y 5; jerarquía opcional (1.2 -> 1.2.A)
CREATE TABLE subcodigo_paro (
  id_subcodigo       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_codigo_paro     SMALLINT NOT NULL REFERENCES codigo_paro(id_codigo_paro) ON DELETE RESTRICT ON UPDATE CASCADE,
  codigo             VARCHAR(10)  NOT NULL UNIQUE,
  descripcion        VARCHAR(100) NOT NULL,
  id_subcodigo_padre INT REFERENCES subcodigo_paro(id_subcodigo) ON DELETE SET NULL ON UPDATE CASCADE,
  UNIQUE (id_codigo_paro, id_subcodigo)   -- permite la FK compuesta desde paro
);

-- ---------- Transaccional ----------
CREATE TABLE registro_produccion (
  id_registro      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  fecha            DATE     NOT NULL,
  id_maquina       SMALLINT NOT NULL REFERENCES maquina(id_maquina) ON DELETE RESTRICT ON UPDATE CASCADE,
  id_turno         SMALLINT NOT NULL REFERENCES turno(id_turno)     ON DELETE RESTRICT ON UPDATE CASCADE,
  id_referencia    INT      NOT NULL,
  id_operaria      INT      NOT NULL REFERENCES persona(id_persona) ON DELETE RESTRICT ON UPDATE CASCADE,
  pacas_producidas INT          NOT NULL CHECK (pacas_producidas >= 0),
  horas_trabajadas NUMERIC(4,2) NOT NULL CHECK (horas_trabajadas > 0 AND horas_trabajadas <= 24),
  meta_por_hora    INT          NOT NULL CHECK (meta_por_hora > 0),
  observacion      TEXT,
  creado_en        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  -- la referencia debe ser una de las que la máquina puede producir
  FOREIGN KEY (id_maquina, id_referencia) REFERENCES maquina_referencia(id_maquina, id_referencia) ON DELETE RESTRICT ON UPDATE CASCADE,
  UNIQUE (fecha, id_maquina, id_turno, id_referencia, id_operaria)
);

CREATE TABLE paro (
  id_paro        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_registro    BIGINT   NOT NULL REFERENCES registro_produccion(id_registro) ON DELETE CASCADE ON UPDATE CASCADE,
  id_codigo_paro SMALLINT NOT NULL REFERENCES codigo_paro(id_codigo_paro) ON DELETE RESTRICT ON UPDATE CASCADE,
  id_subcodigo   INT,
  minutos        INT NOT NULL CHECK (minutos > 0),
  id_persona     INT REFERENCES persona(id_persona) ON DELETE SET NULL ON UPDATE CASCADE,  -- personal involucrado (opcional)
  observacion    TEXT,
  -- el subcódigo debe pertenecer al código indicado (si es NULL no se valida)
  FOREIGN KEY (id_codigo_paro, id_subcodigo) REFERENCES subcodigo_paro(id_codigo_paro, id_subcodigo) ON DELETE RESTRICT ON UPDATE CASCADE
);
-- un mismo código/subcódigo no se repite dentro de un registro
CREATE UNIQUE INDEX ux_paro_registro_codigo ON paro (id_registro, id_codigo_paro, COALESCE(id_subcodigo, 0));

-- ---------- Índices (según las consultas de 04_consultas.sql) ----------
CREATE INDEX ix_registro_fecha          ON registro_produccion (fecha);                -- filtros por rango de fechas
CREATE INDEX ix_registro_maquina_fecha  ON registro_produccion (id_maquina, fecha);    -- productividad por máquina y mes
CREATE INDEX ix_registro_turno          ON registro_produccion (id_turno);             -- comparación entre turnos
CREATE INDEX ix_paro_codigo             ON paro (id_codigo_paro);                      -- participación por código
CREATE INDEX ix_paro_subcodigo          ON paro (id_subcodigo);                        -- detalle por subcódigo

-- ---------- Vistas ----------
-- Productividad = pacas / (meta * horas) * factor de la máquina (misma fórmula de la hoja Tiempos)
CREATE VIEW vw_productividad AS
SELECT r.id_registro, r.fecha, EXTRACT(YEAR FROM r.fecha)::INT AS anio, EXTRACT(MONTH FROM r.fecha)::INT AS mes,
       m.nombre AS maquina, t.nombre AS turno,
       r.pacas_producidas, r.horas_trabajadas, r.meta_por_hora,
       r.meta_por_hora * r.horas_trabajadas AS produccion_ideal,
       ROUND(100.0 * r.pacas_producidas * m.factor_produccion / (r.meta_por_hora * r.horas_trabajadas), 2) AS pct_productividad
FROM registro_produccion r
JOIN maquina m ON m.id_maquina = r.id_maquina
JOIN turno   t ON t.id_turno   = r.id_turno;

-- Protección de datos personales: se expone solo el código, no el nombre.
CREATE VIEW vw_persona_anonima AS
SELECT id_persona, codigo, rol, activo FROM persona;

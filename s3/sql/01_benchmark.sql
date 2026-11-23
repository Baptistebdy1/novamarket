-- Garder les mêmes réglages pour tous les essais.
SET max_parallel_workers_per_gather = 0;

SELECT version() AS version_postgresql,
       current_setting('shared_buffers') AS shared_buffers,
       current_setting('block_size') AS taille_bloc_octets,
       current_setting('max_parallel_workers_per_gather') AS workers_paralleles;

CREATE TEMP TABLE volumes_benchmark AS
SELECT COUNT(*) AS lignes,
       COUNT(*) FILTER (WHERE store_id = 42) AS magasin_42,
       COUNT(*) FILTER (WHERE store_id = 1) AS magasin_1
FROM benchmark.benchmark_sales;

SELECT *, pg_size_pretty(pg_total_relation_size('benchmark.benchmark_sales')) AS taille_table
FROM volumes_benchmark;

DO $$
BEGIN
    IF (SELECT lignes FROM volumes_benchmark) <> 10000000 THEN
        RAISE EXCEPTION 'Le benchmark doit contenir 10 millions de lignes';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_index
        WHERE indrelid = 'benchmark.benchmark_sales'::regclass
    ) THEN
        RAISE EXCEPTION 'La comparaison doit commencer sans index sur benchmark_sales';
    END IF;
END;
$$;

-- Les deux phases exécutent exactement les mêmes requêtes, dans le même ordre.
-- Essai 0 : premier passage. Essais 1 à 3 : répétitions pour la médiane.
CREATE TEMP VIEW requetes_benchmark AS
SELECT f.magasin, e.essai,
       format(
           'EXPLAIN (ANALYZE, BUFFERS) SELECT SUM(amount_cents) FROM benchmark.benchmark_sales WHERE store_id = %s',
           f.magasin
       ) AS plan
FROM (VALUES (42), (1)) AS f(magasin)
CROSS JOIN generate_series(0, 3) AS e(essai);

SELECT format('SELECT %L AS mesure', format('avant magasin=%s essai=%s', magasin, essai)),
       plan
FROM requetes_benchmark
ORDER BY essai, magasin DESC
\gexec

BEGIN;
SELECT clock_timestamp()::text AS debut_creation
\gset
CREATE INDEX benchmark_sales_store_idx ON benchmark.benchmark_sales (store_id);
SELECT round(1000 * extract(epoch FROM clock_timestamp() - :'debut_creation'::timestamptz), 3)
           AS creation_index_ms,
       pg_relation_size('benchmark.benchmark_sales_store_idx') AS taille_index_octets,
       pg_size_pretty(pg_relation_size('benchmark.benchmark_sales_store_idx')) AS taille_index;

SELECT format('SELECT %L AS mesure', format('apres magasin=%s essai=%s', magasin, essai)),
       plan
FROM requetes_benchmark
ORDER BY essai, magasin DESC
\gexec
-- La génération est conservée et un prochain essai peut repartir sans index.
ROLLBACK;

BEGIN;

CREATE TABLE reception.categories (
    category_id integer,
    category_name text,
    parent_category_id integer
);

CREATE TABLE reception.products (
    product_id integer,
    sku text,
    product_name text,
    category_id integer,
    first_listed_on date
);

\copy reception.categories FROM '/tmp/novamarket-s2/categories.csv' WITH (FORMAT csv, HEADER true)
\copy reception.products FROM '/tmp/novamarket-s2/products.csv' WITH (FORMAT csv, HEADER true)

CREATE TABLE public.categories (
    category_id integer PRIMARY KEY,
    category_name text NOT NULL,
    parent_category_id integer REFERENCES public.categories (category_id)
);

CREATE TABLE public.products (
    product_id integer PRIMARY KEY,
    sku text NOT NULL UNIQUE,
    product_name text NOT NULL,
    category_id integer NOT NULL REFERENCES public.categories (category_id),
    first_listed_on date NOT NULL
);

-- Les références entre catégories sont contrôlées à la fin de cet INSERT.
INSERT INTO public.categories
SELECT category_id, category_name, parent_category_id
FROM reception.categories;

-- Garder une fiche par doublon exact et journaliser chaque copie en plus.
WITH occurrences AS (
    SELECT p.*,
           ROW_NUMBER() OVER (
               PARTITION BY product_id, sku, product_name, category_id, first_listed_on
           ) AS numero
    FROM reception.products AS p
)
INSERT INTO qualite.rejets (source, identifiant, donnees, motif)
SELECT 'products.csv', product_id::text, to_jsonb(occurrences) - 'numero', 'doublon exact'
FROM occurrences
WHERE numero > 1;

INSERT INTO public.products
SELECT DISTINCT product_id, sku, product_name, category_id, first_listed_on
FROM reception.products;

-- PostgreSQL vérifie aussi les lignes S1 déjà présentes.
ALTER TABLE public.order_items
    ADD CONSTRAINT order_items_product_id_fkey
    FOREIGN KEY (product_id) REFERENCES public.products (product_id);

COMMIT;

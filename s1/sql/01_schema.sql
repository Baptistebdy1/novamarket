BEGIN;

CREATE TABLE public.customers (
    customer_id integer PRIMARY KEY,
    customer_name text NOT NULL,
    city text NOT NULL
);

CREATE TABLE public.orders (
    order_id integer PRIMARY KEY,
    customer_id integer NOT NULL REFERENCES public.customers (customer_id),
    ordered_on date NOT NULL,
    status text NOT NULL CHECK (status IN ('completed', 'pending', 'cancelled'))
);

CREATE TABLE public.order_items (
    order_item_id integer PRIMARY KEY,
    order_id integer NOT NULL REFERENCES public.orders (order_id),
    product_id integer NOT NULL,
    quantity integer NOT NULL CHECK (quantity > 0),
    unit_price_cents integer NOT NULL CHECK (unit_price_cents >= 0)
);

CREATE TABLE public.payments (
    payment_id integer PRIMARY KEY,
    order_id integer NOT NULL REFERENCES public.orders (order_id),
    paid_on date NOT NULL,
    amount_cents integer NOT NULL,
    status text NOT NULL CHECK (status IN ('captured', 'pending'))
);

COMMIT;

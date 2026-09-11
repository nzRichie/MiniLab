-- The portal's database. Loaded by default_config/db.sh on every spawn and
-- every reset, so a learner who dropped a table gets the original back.
--
-- Three tables, and which tier reads which one is the whole reason the lab has
-- two tiers. The portal reads `document` and nothing else. The nightly report
-- job reads `customer` and `shipment`. The starter state gives both tiers one
-- account holding SELECT on the whole database, so the account the traversal
-- discloses on the web tier reads the customer table as well.

DROP DATABASE IF EXISTS portal;
CREATE DATABASE portal;
USE portal;

-- The document titles the viewer prints above a document's contents. `name` is
-- the value that arrives in the `file` query parameter.
CREATE TABLE document (
    name  VARCHAR(64) PRIMARY KEY,
    title VARCHAR(128) NOT NULL
);

INSERT INTO document (name, title) VALUES
    ('returns-policy.txt', 'Returns and claims policy'),
    ('tariff-2026.txt',    'Standard tariff, 2026'),
    ('depot-hours.txt',    'Depot collection hours');

-- The account records the nightly report counts over. Nothing the portal does
-- reads this table; the direct login at the end of Part 1 is what reaches it.
CREATE TABLE customer (
    id      INT PRIMARY KEY,
    name    VARCHAR(64)  NOT NULL,
    email   VARCHAR(96)  NOT NULL,
    phone   VARCHAR(24)  NOT NULL,
    account VARCHAR(16)  NOT NULL
);

INSERT INTO customer (id, name, email, phone, account) VALUES
    (1, 'Aldermoor Plant Hire',  'accounts@aldermoor-plant.example',  '01305 774 218', 'ALD-0041'),
    (2, 'Carrick Marine Supply', 'orders@carrick-marine.example',     '01772 330 915', 'CAR-0117'),
    (3, 'Weatherby Print',       'jvenn@weatherby-print.example',     '01423 812 664', 'WEA-0093'),
    (4, 'Torrance Fabrication',  'purchasing@torrance-fab.example',   '01914 226 780', 'TOR-0208'),
    (5, 'Nyland Cold Storage',   'logistics@nyland-cold.example',     '01482 559 034', 'NYL-0155'),
    (6, 'Petrie Instruments',    'r.petrie@petrie-inst.example',      '01865 441 902', 'PET-0072');

CREATE TABLE shipment (
    id          INT PRIMARY KEY,
    customer_id INT NOT NULL,
    depot       VARCHAR(32) NOT NULL,
    band        CHAR(1)     NOT NULL,
    delivered   DATE        NOT NULL
);

INSERT INTO shipment (id, customer_id, depot, band, delivered) VALUES
    (2201, 1, 'Aldermoor', 'C', '2026-01-14'),
    (2202, 3, 'Weatherby', 'A', '2026-01-14'),
    (2203, 1, 'Aldermoor', 'B', '2026-01-15'),
    (2204, 5, 'Carrick',   'D', '2026-01-15'),
    (2205, 2, 'Carrick',   'B', '2026-01-16'),
    (2206, 6, 'Weatherby', 'A', '2026-01-16'),
    (2207, 4, 'Aldermoor', 'C', '2026-01-17'),
    (2208, 3, 'Weatherby', 'A', '2026-01-17'),
    (2209, 5, 'Carrick',   'D', '2026-01-18');

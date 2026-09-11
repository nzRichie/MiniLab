-- The storefront's database, loaded by default_config/db.sh on every spawn and
-- every reset. Two tables, and the whole of the lab's argument is that the
-- application legitimately reads one of them and has no business reading the
-- other.
--
-- product   what search.php and stock.php are for. Three of its rows carry
--           published = 0: unreleased lines the storefront is not meant to show
--           yet. They are the rows a tautology exposes, and they stay exposed
--           after every stage of Part 2, because the application holds SELECT on
--           this table for a reason and the hidden rows live in it.
--
-- credential  the storefront's own accounts. Nothing in the web application ever
--           reads this table; an administrative tool that does not run on the
--           web server does. The starter grants let the application read it
--           anyway, which is what Part 2A takes away.

DROP DATABASE IF EXISTS shop;
CREATE DATABASE shop;
USE shop;

CREATE TABLE product (
  id        INT          NOT NULL PRIMARY KEY,
  name      VARCHAR(60)  NOT NULL,
  category  VARCHAR(30)  NOT NULL,
  price     DECIMAL(7,2) NOT NULL,
  stock     INT          NOT NULL,
  published TINYINT(1)   NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO product (id, name, category, price, stock, published) VALUES
  (1,  'Harkness 12mm socket',          'hand tools',  4.50,  180, 1),
  (2,  'Harkness ratchet handle',       'hand tools', 18.99,   42, 1),
  (3,  'Harkness torque wrench 40Nm',   'hand tools', 74.00,   11, 1),
  (4,  'Harkness cable stripper',       'electrical', 12.25,   96, 1),
  (5,  'Harkness crimp set 120pc',      'electrical', 31.40,    7, 1),
  (6,  'Harkness digital multimeter',   'electrical', 58.75,    0, 1),
  (7,  'Harkness LED inspection lamp',  'lighting',   22.10,   63, 1),
  (8,  'Harkness bench vice 100mm',     'workshop',   89.90,    4, 1),
  (9,  'Harkness impact driver X2',     'power tools',149.00,   25, 0),
  (10, 'Harkness battery pack 5Ah',     'power tools', 64.50,   30, 0),
  (11, 'Harkness laser level LX',       'measuring',  118.00,   14, 0);

CREATE TABLE credential (
  id        INT         NOT NULL PRIMARY KEY,
  username  VARCHAR(30) NOT NULL,
  email     VARCHAR(60) NOT NULL,
  pass_hash CHAR(64)    NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO credential (id, username, email, pass_hash) VALUES
  (1, 'admin',    'admin@harkness.example',    'd4e7e93b257878579164665fa1fa5c76573b647547b2956572f4a24bd0bee7cb'),
  (2, 'j.mercer', 'j.mercer@harkness.example', '9416a9df5328046b781bfebe9a288ea913ea09491ac86afac68dcd037c64ad0e'),
  (3, 'bruno.k',  'bruno.k@harkness.example',  '84961cdccc780a608ad71f487627346c534d9f19d0fc57369553515d351bc5f3'),
  (4, 's.patel',  's.patel@harkness.example',  '2ef1aed21ba42851603c05b8b48ad1385c645937f26eb6a9fd83c49bcded377e');

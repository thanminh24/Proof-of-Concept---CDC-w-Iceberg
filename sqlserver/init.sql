USE master;
GO
CREATE DATABASE commerce;
GO
USE commerce;
GO
CREATE SCHEMA commerce;
GO
CREATE TABLE commerce.account (
    user_id INT IDENTITY(1,1) PRIMARY KEY,
    email VARCHAR(255) NOT NULL
);
GO
CREATE TABLE commerce.product (
    product_id INT IDENTITY(1,1) PRIMARY KEY,
    product_name VARCHAR(255) NOT NULL
);
GO
INSERT INTO commerce.account (email) VALUES ('initial_user@example.com');
GO
INSERT INTO commerce.product (product_name) VALUES ('Initial Product');
GO
EXEC sys.sp_cdc_enable_db;
GO
EXEC sys.sp_cdc_enable_table @source_schema = 'commerce', @source_name = 'account', @role_name = NULL;
GO
EXEC sys.sp_cdc_enable_table @source_schema = 'commerce', @source_name = 'product', @role_name = NULL;
GO
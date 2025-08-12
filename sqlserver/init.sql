CREATE DATABASE postgres;
GO
USE postgres;
GO
CREATE SCHEMA commerce;
GO
CREATE TABLE commerce.account (user_id INT IDENTITY(1,1) PRIMARY KEY, email VARCHAR(255));
CREATE TABLE commerce.product (product_id INT IDENTITY(1,1) PRIMARY KEY, product_name VARCHAR(255));
GO
EXEC sys.sp_cdc_enable_db;
GO
EXEC sys.sp_cdc_enable_table @source_schema = 'commerce', @source_name = 'account', @role_name = NULL, @supports_net_changes = 1;
EXEC sys.sp_cdc_enable_table @source_schema = 'commerce', @source_name = 'product', @role_name = NULL, @supports_net_changes = 1;
GO

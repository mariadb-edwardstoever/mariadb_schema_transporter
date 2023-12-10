-- Schema Exists 
-- transport_schema_mariabackup, by Edward Stoever for MariaDB Support

select 'YES' from information_schema.SCHEMATA where SCHEMA_NAME='$SCHEMA_NAME'


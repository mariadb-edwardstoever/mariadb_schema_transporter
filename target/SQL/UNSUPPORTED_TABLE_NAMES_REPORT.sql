-- Mariadb Schema Transporter, by Edward Stoever for MariaDB Support

select concat(count(*),' TABLE(S) WITH UNSUPPORTED TABLE NAMES IN SCHEMA ', TABLE_SCHEMA) as txt
from information_schema.TABLES
where TABLE_SCHEMA='$SCHEMA_NAME'
and ENGINE ='InnoDB' 
and TABLE_NAME REGEXP '[^a-zA-Z0-9_]+' = 1
having count(*) !=0;
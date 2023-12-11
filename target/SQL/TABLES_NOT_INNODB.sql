-- Mariadb Schema Transporter, by Edward Stoever for MariaDB Support

select concat(count(*),' TABLE(S) NOT INNODB ENGINE IN SCHEMA ', TABLE_SCHEMA) as txt
from information_schema.TABLES
where TABLE_SCHEMA='$SCHEMA_NAME'
and ENGINE !='InnoDB' 
having count(*) !=0;


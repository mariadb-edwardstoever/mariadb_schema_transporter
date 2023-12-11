-- Mariadb Schema Transporter, by Edward Stoever for MariaDB Support

select TABLE_NAME 
from information_schema.TABLES 
where TABLE_SCHEMA='$SCHEMA_NAME'
and TABLE_TYPE='BASE TABLE'
and ENGINE='InnoDB'
and TABLE_NAME REGEXP '[^a-zA-Z0-9_]+'=0
and TABLE_NAME IN (
  select distinct table_name
  FROM information_schema.partitions 
  WHERE PARTITION_NAME is not null
  AND TABLE_SCHEMA = '$SCHEMA_NAME'
  AND SUBPARTITION_NAME IS NULL);

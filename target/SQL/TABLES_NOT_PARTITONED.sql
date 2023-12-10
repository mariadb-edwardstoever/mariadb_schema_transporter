-- transport_schema_mariabackup, by Edward Stoever for MariaDB Support

select TABLE_NAME 
from information_schema.TABLES 
where TABLE_SCHEMA='$SCHEMA_NAME'
and TABLE_TYPE='BASE TABLE'
and ENGINE='InnoDB'
and TABLE_NAME NOT IN (
  select distinct table_name
  FROM information_schema.partitions 
  WHERE PARTITION_NAME is not null
  AND TABLE_SCHEMA = '$SCHEMA_NAME');


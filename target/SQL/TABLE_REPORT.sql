-- Mariadb Schema Transporter, by Edward Stoever for MariaDB Support

select concat(count(*),' INNODB TABLE(S) NOT PARTITIONED IN SCHEMA ', TABLE_SCHEMA) as txt
from information_schema.TABLES
where TABLE_SCHEMA='$SCHEMA_NAME'
and TABLE_TYPE='BASE TABLE'
and ENGINE='InnoDB'
and TABLE_NAME NOT IN (
  select distinct table_name
  FROM information_schema.partitions
  WHERE PARTITION_NAME is not null
  AND TABLE_SCHEMA = '$SCHEMA_NAME')
GROUP BY TABLE_SCHEMA
having count(*) !=0
union all
select concat(count(*),' INNODB TABLE(S) WITH PARTITIONS IN SCHEMA ', TABLE_SCHEMA) as txt
from information_schema.TABLES
where TABLE_SCHEMA='$SCHEMA_NAME'
and TABLE_TYPE='BASE TABLE'
and ENGINE='InnoDB'
and TABLE_NAME IN (
  select distinct table_name
  FROM information_schema.partitions
  WHERE PARTITION_NAME is not null
  AND TABLE_SCHEMA = '$SCHEMA_NAME'
  AND SUBPARTITION_NAME IS NULL)
GROUP BY TABLE_SCHEMA
having count(*) !=0
union all
select concat(count(*),' INNODB TABLE(S) WITH SUBPARTITIONS IN SCHEMA ', TABLE_SCHEMA) as txt
from information_schema.TABLES
where TABLE_SCHEMA='$SCHEMA_NAME'
and TABLE_TYPE='BASE TABLE'
and ENGINE='InnoDB'
and TABLE_NAME IN (
  select distinct table_name
  FROM information_schema.partitions
  WHERE PARTITION_NAME is not null
  AND TABLE_SCHEMA = '$SCHEMA_NAME'
  AND SUBPARTITION_NAME IS NOT NULL)
GROUP BY TABLE_SCHEMA
having count(*) !=0;

-- QUERY BY EDWARD STOEVER FOR MARIADB SUPPORT

select 'YES' into @CHECK_EVENT_PRIV 
from information_schema.SCHEMATA 
where SCHEMA_NAME='information_schema'
and '$V_SKIP_EVENTS' = 'DO';

delimiter //
begin not atomic
set @MISSING_PRIVS='NONE';
select GROUP_CONCAT(`PRIVILEGE` SEPARATOR ', ') into @MISSING_PRIVS from (
select 1 as `ONE`, `PRIVILEGE` FROM(
WITH REQUIRED_PRIVS as (
select 'SELECT' as PRIVILEGE UNION ALL
select 'INSERT' as PRIVILEGE UNION ALL
select 'CREATE' as PRIVILEGE UNION ALL
select 'DROP'  as PRIVILEGE UNION ALL
select 'ALTER' as PRIVILEGE UNION ALL
select 'CREATE ROUTINE' as PRIVILEGE UNION ALL
select 'ALTER ROUTINE' as PRIVILEGE UNION ALL
select 'EVENT' as PRIVILEGE UNION ALL
select 'SUPER' as PRIVILEGE  ) 
SELECT A.PRIVILEGE , B.TABLE_CATALOG
from REQUIRED_PRIVS A
LEFT OUTER JOIN
information_schema.USER_PRIVILEGES B
ON (A.PRIVILEGE=B.PRIVILEGE_TYPE AND replace(B.GRANTEE,'''','')=current_user())
) as X where TABLE_CATALOG is null) as Y group by `ONE`;
 IF @MISSING_PRIVS != 'NONE' THEN

  SELECT concat('Insufficient privileges. Grant ',@MISSING_PRIVS,' on *.* to ',CONCAT('\'',REPLACE(CURRENT_USER(),'@','\'@\''),'\'')) as NOTE;

 END IF;
end;
//
delimiter ;

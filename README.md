# Mariadb Schema Transporter

## Synopsis
The usual method for transporting a schema from one server to another is to export with mariadb-dump. This method works well, but it can be slow, especially for a large schema.

With innodb it possible to transport a tablespace between tables which copies entire datafiles at a time, a much faster process. The downside is that the process involves many steps and becomes particularly complicated for partitioned and subpartitioned tables.

The Mariadb Schema Transporter makes transporting a schema quick and easy.

You can use Mariadb Schema Transporter to copy a schema on the same instance giving the copied schema a different name, or to an instance on a separate host using any name.

***
## Get Mariadb Schema Transporter
To download the Schema Transporter script direct to your linux server, you may use git or wget:
```
git clone https://github.com/mariadb-edwardstoever/mariadb_schema_transporter.git
```
```
wget https://github.com/mariadb-edwardstoever/mariadb_schema_transporter/archive/refs/heads/main.zip
```
***
## Example 
Mariadb Schema Transporter is divided into two subdirectories, source and target. Assuming you allow for root@localhost connections, with ALL PRIVILEGES connecting via unix socket, you can ignore configuring the script. In that case, to backup a single schema for transport, run the following command from the source directory:
```
./backup_schema.sh --source-schema=myschema
```
That will produce two files:
```
/tmp/schema_transporter/source_schema.dump.sql.gz
/tmp/schema_transporter/mariabackupstream.gz
```

Copy those files to the same directory on the host where you want to duplicate the schema. Again, assuming root@localhost connecting via unix socket, run the following command from the target directory:
```
./restore_schema.sh --target-schema=myduplicatedschema
```
That is all it takes to copy the schema `myschema` to `myduplicateschema`.
***
### Minimum Privileges
The backup_schema.sh and restore_schema.sh scripts in the Mariadb Schema Transporter must be run on the same host as the database you are working with, but that does not mean you _must_ use the root@localhost account. 

Imagine you want to use the account mariabackup@localhost identified with a password. In that case, you can edit the files source.cnf in the source directory and target.cnf in the target directory. The edits are self explanatory.

Minimum required privileges to successfully take a backup on source:
```
grant SELECT, RELOAD, PROCESS, LOCK TABLES, BINLOG MONITOR, EVENT ON *.* 
to mariabackup@localhost;
```
Minimum required privileges to successfully restore on target:

```
grant SELECT, INSERT, CREATE, DROP, ALTER, SUPER, CREATE ROUTINE, ALTER ROUTINE, EVENT ON *.* 
to mariabackup@localhost;
```
If you want to make the task of grants easy and reliable, especially on the target, `grant ALL PRIVILEGES on *.*` to the user. You can revoke them when you are done.
***
## Planning the backup and restore
It is important to plan for the required storage space for the backup on the source and the restore on the target. 
#### Source
The easiest option is the default `--compressed=true` which will compress the backup into an archive. This means that the source machine really only needs a mount point with about 50% of the space used for the subdirectory of the datadir where the schema is stored. For example, if your schema is called mydb, you can see how much space it uses (datadir is /var/lib/mysql in this example):
```
$ du -sh /var/lib/mysql/mydb
11G     /var/lib/mysql/mydb
```
#### Target
The target will require additional free space, even more than the source. First, you must have a mount point to place the two compressed files `mariabackupstream.gz` and `source_schema.dump.sql.gz`. When the script is run, additional files will be stored in a subdirectory `stage`. Expect the file mariabackupstream.gz to extract about 10 times in overall size, plus you will need some room for a margin of error. So if mariabackupstream.gz is 100M, you will need an _additional_ 1200M of free space.

Next, you will need to ensure that the datadir of the database has enough space to store all of those new files. It will need the same storage that is used for the subdirectory of the datadir where the schema is stored _on the source_. In this example, 1200M of free space in the datadir would be enough.

Once the operation is completed, the script will ask you if you want to remove the temporary files.

#### Where do the files go?
When you run the backup_schema.sh or the restore_schema.sh scripts, you can indicate an alternative directory for the files. The default is `/tmp`. 

Suppose you prepare a large partition and mount it at `/opt/mydb_bkup`. You can run either backup_schema.sh or restore_schema.sh with the option `--base-dir=/opt/mydb_bkup`. 

With the option `--base-dir=/opt/mydb_bkup`, the backup script will store the files in `/opt/mydb_bkup/schema_transporter`. 

With the option `--base-dir=/opt/mydb_bkup`, the restore script will expect the files `source_schema.dump.sql.gz` and  `mariabackupstream.gz` in the directory `/opt/mydb_bkup/schema_transporter`. 

The base directory for the source does not have to be the same as the base directory for the target. 

***
## Options

#### Source
A number of options are available when running the backup_schema.sh script:
```
  --source-schema=mydb       # Indicate the schema to backup, this is required
  --base-dir=/opt/mydb_bkup  # Indicate a base directory to store backup
                             # Base directory must exist. Default: /tmp
  --compressed=false         # Do not compress backup into a single file
  --skip-fks                 # Do not define foreign keys in tables to be transported
  --skip-events              # Do not include events in the transported schema
  --skip-routines            # Do not include routines in the transported schema
  --bypass-priv-check        # Bypass the check that the user has sufficient privileges
  --test                     # Test connect to database and display script version
  --version                  # Test connect to database and display script version
  --help                     # Display the help menu

```
#### target
A number of options are available when running the restore_schema.sh script:
```
  --target-schema=mydb_new   # Indicate the schema to restore, this is required
  --base-dir=/opt/mydb_bkup  # Indicate a base directory where the subdirectory
                             # mariadb_schema_transporter is located. Default: /tmp
  --bypass-priv-check        # Bypass the check that the user has sufficient privileges.
  --test                     # Test connect to database and display script version
  --version                  # Test connect to database and display script version
  --help                     # Display the help menu

```
***
## Be Aware
Some things to keep in mind:

* You can define tables without foreign keys with the option `--skip-fks` when backing up on the source. This will prevent an error when a table references a primary key that is not part of the transport. 
* You can turn off transport of EVENTS with the option `--skip-events` when backing up on the source.
* You can turn off transport of ROUTINES with the option `--skip-routines` when backing up on the source.
* You can turn off the privilege check with the option `--bypass-priv-check` which will let you run either script even if the database user doesn't have all the required privileges. This may be required for backward compatibility to old releases.
* It is possible to skip saving the backup as a compressed archive with the option `--compressed=false`. This takes up much more storage space and makes transferring the files to another host more cumbersome. When using this option, find the created files in the subdirectory `stage`. 
* When the restore_schema.sh is run to create the target schema, foreign key and check constraints will be _disabled globally_ during the operation.
* When copying files from one host to another, use scp or rsync and transfer the directory `schema_transporter` and its contents. It is important that the directory `schema_transporter` exists in the directory defined by the `--base-dir` option. It is important that _the user running_ the restore_schema.sh script _and the user running mariadb process_ have read and write privileges on the `schema_transporter` directory.
* Mariadb is not responsible for your use of this script. Test Mariadb Schema Transporter thoroughly in the appropriate test environment to ensure it does what you are expecting it to do and that you know how to use it.
***
## Limitations
There are limitations you should be aware of when using Mariadb Schema Transporter:
1. Tables with out-of-the-ordinary characters in their names will be bypassed automatically. Examples of such tables would be ones with names like `M$_variables` (with $) or `innovación` (with a tilde). This is because the file name will be different from the table name. Currently, names with a-z, A-Z, 0-9, and _ (underscore) will work just fine. Any other characters in a table name will cause the table to be transferred to the target but with no rows. In a future release, this limitation may be sorted out. 
2. Tables in the schema you transport with any ENGINE that is not InnoDB will be transferred to the target without rows. It is possible for _you_ to dump the rows and insert them as a separate operation.

## MDEV-36827
In the most recent versions of Mariadb-backup, we have discovered a bug which is documented here: https://jira.mariadb.org/browse/MDEV-36827
The problem occurs during the backup phase, but no error is reported. Mariadb Schema Transporter uses a feature in Mariabackup called "tables-file" which is a list of tables to be backed up. With the bug, the backup appears to complete without error but nothing is actually backed up. When you attempt to restore to a new schema, you will see this error:
```
ERROR 1030 (HY000) at line 1: Got error 194 "Tablespace is missing for a table" from storage engine InnoDB
2025_06_06_11_10_14 Something went wrong when importing tablespace for ooni.PERSONS
```
The bug is present in the following versions of mariabackup, and perhaps exists in more versions:
10.6.22 Community
10.11.11 Community
11.4.5 Community
11.8.1 Community
11.8.2 Community
10.6.21 Enterprise

## Workarounds for bug MDEV-36827
Currently, there are two ways of working around this bug. Version 11.8 has no workaround.

### Workaround #1
The first workaround is to force Mariadb Schema Transporter to use an older version of Mariabackup that does not include the bug. I have added mariadb-backup files for versions that work in the bin directory. They were compiled for Debian, but they will likely work on any linux version. Edit the file source/pre_backup.sh and at the bottom of the file, uncomment out the line that applies to the version you are working with.

### Workaround #2
Do not downgrade the mariadb-server, however downgrade the version of mariadb-backup. For example, let's say you have installed Mariadb-server 10.11.11 and Mariadb-backup 10.11.11. You want to downgrade only Mariadb-backup. You would run these commands:
```
apt remove mariadb-backup
./mariadb_repo_setup --mariadb-server-version=10.11.10
apt install maria-backup
```

## Cross Version Compatibility
Transporting a schema to the same version of Mariadb server will always work. It is possible to transport from one version to a different version in some cases. The following table indicates where transporting across versions will work. All versions of 11.8 are not working yet because of bug MDEV-36827.
```
+-------------+---------+---------+----------+---------+------------+
|             | TO 10.5 | TO 10.6 | TO 10.11 | TO 11.4 | TO 11.8    |
+-------------+---------+---------+----------+---------+------------+
| FROM 10.5   | OK      | OK      | FAILS    | FAILS   |            |
| FROM 10.6   | OK      | OK      | FAILS    | FAILS   |            |
| FROM 10.11  | FAILS   | FAILS   | OK       | OK      |            |
| FROM 11.4   | FAILS   | FAILS   | FAILS    | OK      |            |
| FROM 11.8   |         |         |          |         | MDEV-36827 |
+-------------+---------+---------+----------+---------+------------+
```

### _Happy Transporting!_
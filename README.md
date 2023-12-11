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
The script is divided into two subdirectories, source and target. Assuming you allow for root@localhost connections, with ALL PRIVILEGES connecting via unix socket, you can ignore configuring the script. In that case, to backup a single schema, run the following command from the source directory:
```
./backup_schema.sh --source-schema=myschema
```
That will produce two files:
```
/tmp/schema_transporter/source_schema.dump.sql.gz
/tmp/schema_transporter/mariabackupstream.gz
```

Copy those files to the host where you want to duplicate the schema. Again, assuming root@localhost connecting via unix socket, run the following command from the target directory:
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
The target will require additional free space, even more than the source. First, you must have a mount point to place the two compressed files `mariabackupstream.gz` and `source_schema.dump.sql.gz`. When the script extracts from these files, additional files will be stored in a subdirectory `stage`. Expect the file mariabackupstream.gz to expand about 10 times. So if mariabackupstream.gz is 100M, you will need an additional 1000M of free space.

Next, you will need to ensure that the datadir of the database has enough space to store all of those new files. It will need the same storage that is used for the subdirectory of the datadir where the schema is stored _on the source_.

Once the operation is completed, the script will ask you if you want to remove the temporary files.

#### Where do the files go?
When you run the backup_schema.sh or the restore_schema.sh scripts, you can indicate an alternative directory for the files. The default is `/tmp`. 

Suppose you prepare a large partition and mount it at `/opt/mydb_bkup`. You can run either script with the option `&#8209;&#8209;base-dir=/opt/mydb_bkup`. 

With the option `--base-dir=/opt/mydb_bkup`, the backup script will store the files in `/opt/mydb_bkup/schema_transporter`. 

With the option `--base-dir=/opt/mydb_bkup`, the restore script will expect the files `source_schema.dump.sql.gz` and  `mariabackupstream.gz` in the directory `/opt/mydb_bkup/schema_transporter`. 

The base directory for the source does not have to be the same as the base directory for the target.

***
## Options
#### Source
A number of options are available when running the backup_schema.sh script:
```
  --source-schema=mydb       # Indicate the schema to backup, this is required
  --base-dir=/opt/mydb_bkup  # Indicate a base directory to store backup.
                             # Base directory must exist. Default: /tmp
  --compressed=false         # Do not compress backup into a single file
  --skip-events              # Do not include events in the transported schema
  --skip-routines            # Do not include routines in the transported schema
  --bypass-priv-check        # Bypass the check that the user has sufficient privileges.
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

* You can turn off transport of EVENTS with the option `--skip-events` when backing up on the source.
* You can turn off transport of ROUTINES with the option `--skip-routines` when backing up on the source.
* You can turn off the privilege check with the option `--bypass-priv-check` which will let you run either script even if the database user doesn't have all the required privileges. This may be required for backward compatibility to old releases.
* It is possible to skip saving the backup as a compressed archive with the option `--compressed=false`. This takes up much more storage space and makes transferring the files to another host more cumbersome. When using this option, find the created files in the subdirectory `stage`. 
* When the restore_schema.sh is run to create the target schema, foreign key and check constraints will be disabled during the operation.
* When copying files from one host to another, use scp or rsync and transfer the directory `schema_transporter` and its contents. It is important that the directory `schema_transporter` exists in the directory defined by the `--base-dir` option. It is important that _the user running_ the restore_schema.sh script _and the user running mariadb process_ have read and write privileges on the `schema_transporter` directory.
* Mariadb is not responsible for your use of this script. Please test it thoroughly in the appropriate test environment to ensure it does what you are expecting it to do.
***
## Limitations
There are limitations you should be aware of when using Mariadb Schema Transporter:
1. Tables with out-of-the-ordinary characters in their names will be bypassed automatically. Examples of such tables would be ones with names like `M$_variables` (with $) or `innovación` (with a tilde). This is because the file name will be different from the table name. Currently, names with a-z, A-Z, 0-9, and _ (underscore) will work just fine. Any other characters in a table name will cause the table to be transferred to the target but with no rows. It is in my plans to fix this in future releases of Mariadb Schema Transporter. 
2. Tables in the schema you transport with any ENGINE that is not InnoDB will be transferred to the target without rows. It is possible for _you_ to dump the rows and insert them as a separate operation.


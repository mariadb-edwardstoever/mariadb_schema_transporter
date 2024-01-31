#!/usr/bin/env bash
# pre_restore.sh
# file distributed with mariadb_schema_transporter 
# By Edward Stoever for MariaDB Support

TEMPDIR="/tmp"
CONFIG_FILE="$SCRIPT_DIR/target.cnf"
SQL_DIR="$SCRIPT_DIR/SQL"
TABLE_LIST_FILE="${TEMPDIR}/tables_list.out"
PARTITIONED_TABLE_LIST_FILE="${TEMPDIR}/tables_partitioned_list.out"
SUBPARTITIONED_TABLE_LIST_FILE="${TEMPDIR}/tables_subpartitioned_list.out"
MARIADB_PROCESS_OWNER=$(ps -o user= -p $(pidof mariadbd 2>/dev/null | awk '{print $1}') 2>/dev/null)
if [ -z "$MARIADB_PROCESS_OWNER" ]; then MARIADB_PROCESS_OWNER=mysql; fi
BASEDIR=$TEMPDIR # DEFAULT

function ts() {
   TS=$(date +%F-%T | tr ':-' '_')
   echo "$TS $*"
}

function die() {
   ts "$*" >&2
   exit 1
}


if [ ! $SCRIPT_VERSION ]; then  die "Do not run ${BASH_SOURCE[0]} script directly. Read the file README.md for help."; fi

function display_help_message() {
printf "This script cannot be run without the target-schema option.
  --target-schema=mydb_new   # Indicate the schema to restore, this is required
  --base-dir=/opt/mydb_bkup  # Indicate a base directory where the subdirectory
                             # mariadb_schema_transporter is located. Default: /tmp 
  --bypass-priv-check        # Bypass the check that the user has sufficient privileges.
  --test                     # Test connect to database and display script version
  --version                  # Test connect to database and display script version
  --help                     # Display the help menu

Read the file README.md for more information.\n"
}

function display_title(){
  local BLANK='  │                                                         │'
  printf "  ┌─────────────────────────────────────────────────────────┐\n"
  printf "$BLANK\n"
  printf "  │         TRANSPORT A SCHEMA WITH MARIABACKUP             │\n"
  printf "  │             RESTORE THE SCHEMA ON TARGET                │\n"
  printf '%-62s' "  │                      Version $SCRIPT_VERSION"; printf "│\n"
  printf "$BLANK\n"
  printf "  │      Script by Edward Stoever for MariaDB Support       │\n"
  printf "$BLANK\n"
  printf "  └─────────────────────────────────────────────────────────┘\n"

}

function stop_here_if_necessary(){
if [ $INVALID_INPUT ]; then display_help_message; die "Invalid option: $INVALID_INPUT"; fi
if [ $DISPLAY_VERSION ]; then exit 0; fi
if [ $HELP ]; then display_help_message; exit 0; fi
if [ ! $TRG ]; then display_help_message; die "You must indicate a target schema."; fi
if [ ! $CAN_CONNECT ]; then 
  TEMP_COLOR=lred; print_color "Failing command: ";unset TEMP_COLOR; 
  TEMP_COLOR=lyellow; print_color "$CMD_MARIADB $CLOPTS\n";unset TEMP_COLOR; 
  local SQL="select now();"
  ERRTEXT=$($CMD_MARIADB $CLOPTS -e "$SQL" 2>&1); TEMP_COLOR=lcyan; print_color "$ERRTEXT\n";unset TEMP_COLOR;
  die "Database connection failed. Read the file README.md. Edit the file target.cnf."; 
fi
}

function whoami_db(){
  local SQL="select CONCAT('\'',REPLACE(REPLACE(CURRENT_USER(),'@','\'@\''),'%','%%'),'\'') as WHOAMI"

    WHOAMI_DB=$($CMD_MARIADB $CLOPTS -ABNe "$SQL")
    printf "DB account:    "; TEMP_COLOR=lmagenta; print_color "$WHOAMI_DB\n"; unset TEMP_COLOR;

}

function start_message() {
  if [ "$(id -u)" -eq 0 ]; then
    if [ -n "$SUDO_USER" ]; then
      RUNAS="$(whoami) (sudo)"
    else 
      RUNAS="$(whoami)"
    fi
  else 
    RUNAS="$(whoami)"
  fi
  local SQL="select now();"
  $CMD_MARIADB $CLOPTS -s -e "$SQL" 1>/dev/null 2>/dev/null && CAN_CONNECT=true || unset CAN_CONNECT
  if [ $CAN_CONNECT ]; then
    TEMP_COLOR=lgreen; print_color "Can connect to database.\n"; unset TEMP_COLOR;
  else
    TEMP_COLOR=lred;   print_color "Cannot connect to database.\n"; unset TEMP_COLOR;
  fi
  printf "OS account:    "; TEMP_COLOR=lmagenta; print_color "$RUNAS\n"; unset TEMP_COLOR;

}

function mk_tmpdir() {
  local subdir="${BASEDIR}/${TOOL}"
  mkdir -p ${subdir} 2>/dev/null || local ERR=true
  if [ $ERR ]; then 
    die "Could not make subdirectory of /tmp"
  fi
}

function _which() {
   if [ -x /usr/bin/which ]; then
      /usr/bin/which "$1" 2>/dev/null | awk '{print $1}'
   elif which which 1>/dev/null 2>&1; then
      which "$1" 2>/dev/null | awk '{print $1}'
   else
      echo "$1"
   fi
}

function dependency(){
  if [ ! $(_which $1) ]; then die "The linux program $1 is unavailable. Check PATH or install."; fi
}

function test_dependencies(){
  dependency envsubst
  dependency mariabackup
  dependency mariadb-dump
  dependency my_print_defaults
}

function print_color () {
  if [ -z "$COLOR" ] && [ -z "$TEMP_COLOR" ]; then printf "$1"; return; fi
  case "$COLOR" in
    default) i="0;36" ;;
    red)  i="0;31" ;;
    blue) i="0;34" ;;
    green) i="0;32" ;;
    yellow) i="0;33" ;;
    magenta) i="0;35" ;;
    cyan) i="0;36" ;;
    lred) i="1;31" ;;
    lblue) i="1;34" ;;
    lgreen) i="1;32" ;;
    lyellow) i="1;33" ;;
    lmagenta) i="1;35" ;;
    lcyan) i="1;36" ;;
    *) i="0" ;;
  esac
if [ $TEMP_COLOR ]; then
  case "$TEMP_COLOR" in
    default) i="0;36" ;;
    red)  i="0;31" ;;
    blue) i="0;34" ;;
    green) i="0;32" ;;
    yellow) i="0;33" ;;
    magenta) i="0;35" ;;
    cyan) i="0;36" ;;
    lred) i="1;31" ;;
    lblue) i="1;34" ;;
    lgreen) i="1;32" ;;
    lyellow) i="1;33" ;;
    lmagenta) i="1;35" ;;
    lcyan) i="1;36" ;;
    *) i="0" ;;
  esac
fi
  printf "\033[${i}m${1}\033[0m"

}

function singular_plural () {
  local noun=$1;
  local count=$2;
  if (( $count != 1 )); then
    noun+="s"
  fi
  printf "%s" "$noun"  
}

function is_db_localhost(){
  local SQL="select VARIABLE_VALUE from information_schema.GLOBAL_VARIABLES where VARIABLE_NAME='HOSTNAME' limit 1"
    local DBHOST=$($CMD_MARIADB $CLOPTS -ABNe "$SQL")
    local CLIENTHOST=$(hostname)
    if [ ! "$DBHOST" == "$CLIENTHOST" ]; then CLIENT_SIDE='TRUE'; else DB_IS_LOCAL='TRUE'; fi

      if [ ! $DB_IS_LOCAL ]; then
         printf "Notice:        ";TEMP_COLOR=lred;  print_color "Database is remote. Please run this script locally.\n";unset TEMP_COLOR;
         die "This script should be run on the host of the database."
      fi
}

function verify_dirs() {
  touch ${BASEDIR}/t.txt 2>/dev/null || local ERR=TRUE;
  rm -f ${BASEDIR}/t.txt 2>/dev/null || local ERR=TRUE;
  if [ $ERR ]; then die "$BASEDIR is not a writeable directory."; fi
  touch ${TEMPDIR}/t.txt 2>/dev/null || local ERR=TRUE;
  rm -f ${TEMPDIR}/t.txt 2>/dev/null || local ERR=TRUE;
  if [ $ERR ]; then die "$TEMPDIR is not a writeable directory."; fi
}

function prepare_basedir(){
  if [ -z $MARIADB_PROCESS_OWNER ]; then die "mariadbd process Owner not defined"; fi
  mkdir -p ${BASEDIR}/${TOOL}/stage
  chown -R $MARIADB_PROCESS_OWNER:$MARIADB_PROCESS_OWNER ${BASEDIR}/${TOOL} 
  if [ -f ${BASEDIR}/${TOOL}/mariabackupstream.gz ]; then COMPRESSED_READY=true; fi
  if [ -f ${BASEDIR}/${TOOL}/stage/xtrabackup_checkpoints ]; then UNCOMPRESSED_READY=true; fi

}

function unpack(){
  if [ $UNCOMPRESSED_READY ]; then TEMP_COLOR=lcyan; print_color "Files were previously uncompressed.\n";unset TEMP_COLOR; return; fi
  if [ ! $COMPRESSED_READY ]; then die "The file mariabackupstream.gz is missing."; fi
  mkdir -p ${BASEDIR}/${TOOL}/stage 
  dependency mbstream
  dependency gzip
  cd ${BASEDIR}/${TOOL}/stage
  cat ../mariabackupstream.gz | gzip -d | mbstream -x || local ERR=TRUE
  if [ $ERR ]; then 
    TEMP_COLOR=lred;  print_color "The command to uncompress backup failed.\n";unset TEMP_COLOR;
    die "gzip and mbstream failed."
  else 
    TEMP_COLOR=lcyan;  print_color "Uncompress of backup file succeeded.\n";unset TEMP_COLOR;
  fi
  cat ../source_schema.dump.sql.gz | gzip -d > source_schema.dump.sql || local ERR=TRUE
  if [ $ERR ]; then 
    TEMP_COLOR=lred;  print_color "The command to uncompress dump failed.\n";unset TEMP_COLOR;
    die "gzip failed."
  else 
    TEMP_COLOR=lcyan;  print_color "Uncompress of dump file succeeded.\n";unset TEMP_COLOR;
  fi

  chown -R $MARIADB_PROCESS_OWNER ${BASEDIR}/${TOOL}/stage
  cd $OLDPWD
}

function prepare_backup(){
  $CMD_MARIABACKUP $CLOPTS  --prepare --export --target-dir=${BASEDIR}/${TOOL}/stage || local ERR=TRUE
  if [ $ERR ]; then 
    TEMP_COLOR=lred;  print_color "The prepare command failed.\n";unset TEMP_COLOR;
    die "gzip failed."
  else 
    TEMP_COLOR=lcyan;  print_color "Prepare of backup succeeded.\n";unset TEMP_COLOR;
  fi
}


function interactive_schema_exists(){
  local SQL_FILE="$SQL_DIR/SCHEMA_EXISTS.sql"
  SCHEMA_NAME=$TRG
  export SCHEMA_NAME
  local SQL=$(envsubst < $SQL_FILE)
  local SCHEMA_EXISTS=$($CMD_MARIADB $CLOPTS  -ABNe "$SQL")
  if [ "$SCHEMA_EXISTS" == "YES" ]; then 
  TEMP_COLOR=lred; print_color "Important: "; unset TEMP_COLOR;
  printf "The schema "; TEMP_COLOR=lcyan; print_color "$SCHEMA_NAME"; printf " already exists.\n"; unset TEMP_COLOR;
  printf "Type y to drop and create the schema or type any other key to cancel.\n"; 
  read -s -n 1 RESPONSE
    if [ ! "$RESPONSE" = "y" ]; then
      die "operation cancelled";  
    fi 
  fi
}

function import_dump(){
  DUMPFILE=${BASEDIR}/${TOOL}/stage/source_schema.dump.sql
  if [ ! -f $DUMPFILE ]; then die "The file $DUMPFILE is mising!"; fi
  local SQL="drop schema if exists $TRG; create schema $TRG; use $TRG; source $DUMPFILE;"
  $CMD_MARIADB $CLOPTS -ABNe "$SQL" || local ERR=TRUE
  if [ $ERR ]; then 
    TEMP_COLOR=lred;  print_color "The import of file $DUMPFILE failed.\n";unset TEMP_COLOR;
    die "import failed."
  else 
    TEMP_COLOR=lcyan;  print_color "The import of file $DUMPFILE succeeded.\n";unset TEMP_COLOR;
  fi
}

function print_table_list_to_file(){
  local SQL_FILE="$SQL_DIR/TABLES_NOT_PARTITONED.sql"
  SCHEMA_NAME=$TRG
  export SCHEMA_NAME
  local SQL=$(envsubst < $SQL_FILE)
  $CMD_MARIADB $CLOPTS -ABNe "$SQL" > $TABLE_LIST_FILE || local ERR=TRUE
  if [ $ERR ]; then 
    TEMP_COLOR=lred;  print_color "Generating the file $TABLE_LIST_FILE failed.\n";unset TEMP_COLOR;
    die "file creation failed."
  else 
    TEMP_COLOR=lcyan;  print_color "Generating the file $TABLE_LIST_FILE succeeded.\n";unset TEMP_COLOR;
  fi
}

function print_partitioned_table_list_to_file(){
  local SQL_FILE="$SQL_DIR/TABLES_PARTITONED.sql"
  SCHEMA_NAME=$TRG
  export SCHEMA_NAME
  local SQL=$(envsubst < $SQL_FILE)
  $CMD_MARIADB $CLOPTS -ABNe "$SQL" > $PARTITIONED_TABLE_LIST_FILE || local ERR=TRUE
  if [ $ERR ]; then 
    TEMP_COLOR=lred;  print_color "Generating the file $PARTITIONED_TABLE_LIST_FILE failed.\n";unset TEMP_COLOR;
    die "file creation failed."
  else 
    TEMP_COLOR=lcyan;  print_color "Generating the file $PARTITIONED_TABLE_LIST_FILE succeeded.\n";unset TEMP_COLOR;
  fi
}

function print_subpartitioned_table_list_to_file(){
  local SQL_FILE="$SQL_DIR/TABLES_PARTITONED_WITH_SUBPARTITIONS.sql"
  SCHEMA_NAME=$TRG
  export SCHEMA_NAME
  local SQL=$(envsubst < $SQL_FILE)
  $CMD_MARIADB $CLOPTS -ABNe "$SQL" > $SUBPARTITIONED_TABLE_LIST_FILE || local ERR=TRUE
  if [ $ERR ]; then 
    TEMP_COLOR=lred;  print_color "Generating the file $SUBPARTITIONED_TABLE_LIST_FILE failed.\n";unset TEMP_COLOR;
    die "file creation failed."
  else 
    TEMP_COLOR=lcyan;  print_color "Generating the file $SUBPARTITIONED_TABLE_LIST_FILE succeeded.\n";unset TEMP_COLOR;
  fi
}

function set_datadir(){
  local SQL_FILE="$SQL_DIR/DATADIR.sql"
  local SQL=$(cat $SQL_FILE)
  DATADIR=$($CMD_MARIADB $CLOPTS  -ABNe "$SQL" | sed 's:/*$::') || local ERR=TRUE;
  if [ $ERR ]; then die "Something went wrong when setting DATADIR"; fi
}

function discard_tablespace () {
  SCHEMA_NAME=$TRG
  TABLE_NAME=$1
  if [ ! $TABLE_NAME ]; then die "No table name to discard tablespace?"; fi
  local SQL="ALTER TABLE ${SCHEMA_NAME}.${TABLE_NAME} DISCARD TABLESPACE;"
  $CMD_MARIADB $CLOPTS -ABNe "$SQL" || local ERR=TRUE;
  if [ $ERR ]; then die "Something went wrong when discarding tablespace for ${SCHEMA_NAME}.${TABLE_NAME}"; fi
  TEMP_COLOR=lcyan; print_color "Discarded tablespace for $SCHEMA_NAME.$TABLE_NAME\n";unset TEMP_COLOR;
}

function import_tablespace () {
  SCHEMA_NAME=$TRG
  TABLE_NAME=$1
  if [ ! $TABLE_NAME ]; then die "No table name to import tablespace?"; fi
  SQL="ALTER TABLE $SCHEMA_NAME.$TABLE_NAME IMPORT TABLESPACE;"
  $CMD_MARIADB $CLOPTS -ABNe "$SQL" || local ERR=TRUE;
  if [ $ERR ]; then die "Something went wrong when importing tablespace for $SCHEMA_NAME.$TABLE_NAME"; fi
  TEMP_COLOR=lcyan; print_color "Imported tablespace for $SCHEMA_NAME.$TABLE_NAME\n";unset TEMP_COLOR;
}

function copy_table_files() {
  SCHEMA_NAME=$TRG
  TABLE_NAME=$1
  if [ ! $TABLE_NAME ]; then die "No table name to copy files?"; fi
  if [ ! $DATADIR ]; then die "Where did DATADIR variable go?"; fi
  if [ ! -d ${DATADIR}/${SCHEMA_NAME} ]; then die "I don't find a directory here: $DATADIR/$SCHEMA_NAME"; fi
  find ${BASEDIR}/${TOOL}/stage -name "${TABLE_NAME}.ibd" -exec cp -f {}  ${DATADIR}/${SCHEMA_NAME} \; || ERR=TRUE
  find ${BASEDIR}/${TOOL}/stage -name "${TABLE_NAME}.cfg" -exec cp -f {}  ${DATADIR}/${SCHEMA_NAME} \; || ERR=TRUE
  chown $MARIADB_PROCESS_OWNER:$MARIADB_PROCESS_OWNER ${DATADIR}/${SCHEMA_NAME}/${TABLE_NAME}.ibd
  chown $MARIADB_PROCESS_OWNER:$MARIADB_PROCESS_OWNER ${DATADIR}/${SCHEMA_NAME}/${TABLE_NAME}.cfg
  if [ $ERR ]; then die "Something went wrong when cp a file to ${DATADIR}/${SCHEMA_NAME}"; fi
  TEMP_COLOR=lcyan; print_color "Copied datafiles for $SCHEMA_NAME.$TABLE_NAME\n";unset TEMP_COLOR;
}

function transport_tablespaces_for_not_partitioned_tables() {
  if [ ! -z "$(cat $TABLE_LIST_FILE)" ]; then 
    TEMP_COLOR=lyellow; print_color "TRANSPORTING TABLESPACES FOR NON-PARTITIONED TABLES\n";unset TEMP_COLOR;
  else
    TEMP_COLOR=lyellow; print_color "NO NON-PARTITIONED TABLES TABLES\n";unset TEMP_COLOR; return;
  fi
  while IFS= read -r line; do  
    discard_tablespace $line;
    copy_table_files $line;
    import_tablespace $line;
    echo "completed steps for table $TRG.$line"
  done <<< $(cat "$TABLE_LIST_FILE")
}

foreign_key_checks_off(){
  SQL="set global foreign_key_checks=OFF; set global check_constraint_checks=OFF;"
  $CMD_MARIADB $CLOPTS -ABNe "$SQL" || local ERR=TRUE
  if [ $ERR ]; then die "Something went wrong when setting foreign_key_checks=OFF"; fi
}

foreign_key_checks_on(){
  SQL="set global foreign_key_checks=ON; set global check_constraint_checks=ON;"
  $CMD_MARIADB $CLOPTS -ABNe "$SQL" || local ERR=TRUE
  if [ $ERR ]; then die "Something went wrong when setting foreign_key_checks=ON"; fi
}

function remove_partitioning_from_placeholder () {
  SCHEMA_NAME=$TRG
  TABLE_NAME=$1
  if [ ! $TABLE_NAME ]; then die "No table name to remove partitioning?"; fi
  SQL="ALTER TABLE ${SCHEMA_NAME}.${TABLE_NAME} REMOVE PARTITIONING;"
  $CMD_MARIADB $CLOPTS -ABNe "$SQL" || local ERR=TRUE;
  if [ $ERR ]; then die "Something went wrong when removing partioning from ${SCHEMA_NAME}.${TABLE_NAME}"; fi
  TEMP_COLOR=lcyan; print_color "Removed partitioning from ${SCHEMA_NAME}.${TABLE_NAME}\n";unset TEMP_COLOR;
}

function create_placeholder_table () {
  SCHEMA_NAME=$TRG
  TABLE_NAME=$1
  if [ ! $TABLE_NAME ]; then die "No table name to create placeholder?"; fi
  SQL="CREATE TABLE ${SCHEMA_NAME}.${TABLE_NAME}_placeholder LIKE ${SCHEMA_NAME}.${TABLE_NAME};"
  $CMD_MARIADB $CLOPTS -ABNe "$SQL" || local ERR=TRUE;
  if [ $ERR ]; then die "Something went wrong when creating placeholder table for ${SCHEMA_NAME}.${TABLE_NAME}"; fi
  TEMP_COLOR=lcyan; print_color "Created placeholder table for ${SCHEMA_NAME}.${TABLE_NAME}\n";unset TEMP_COLOR;
}


function drop_placeholder_table () {
  SCHEMA_NAME=$TRG
  TABLE_NAME=$1
  if [ ! $TABLE_NAME ]; then die "No table name to create placeholder?"; fi
  SQL="DROP TABLE ${SCHEMA_NAME}.${TABLE_NAME};"
  $CMD_MARIADB $CLOPTS -ABNe "$SQL" || local ERR=TRUE;
  if [ $ERR ]; then die "Something went wrong when dropping placeholder table ${SCHEMA_NAME}.${TABLE_NAME}"; fi
  TEMP_COLOR=lcyan; print_color "Dropped placeholder table ${SCHEMA_NAME}.${TABLE_NAME}\n";unset TEMP_COLOR;
}

function exchange_partition_for_partitioned_table(){
  SCHEMA_NAME=$TRG
  TABLE_NAME=$1
  PARTITION_NAME=$2
  if [ ! $TABLE_NAME ]; then die "No table name to exchange tablespace?"; fi
  SQL="ALTER TABLE ${SCHEMA_NAME}.${TABLE_NAME} EXCHANGE PARTITION ${PARTITION_NAME} WITH TABLE ${SCHEMA_NAME}.${TABLE_NAME}_placeholder;;"
  $CMD_MARIADB $CLOPTS -ABNe "$SQL" || local ERR=TRUE;
  if [ $ERR ]; then die "Something went wrong when exchanging partition tablespace for $SCHEMA_NAME.$TABLE_NAME"; fi
  TEMP_COLOR=lblue; print_color "Exchanged tablespace partition $PARTITION_NAME for $SCHEMA_NAME.$TABLE_NAME\n";unset TEMP_COLOR;
}

function transport_tablespaces_for_partitioned_tables() {
  if [ ! -z "$(cat $PARTITIONED_TABLE_LIST_FILE)" ]; then 
    TEMP_COLOR=lyellow; print_color "TRANSPORTING TABLESPACES FOR PARTITIONED TABLES\n";unset TEMP_COLOR;
  else
    TEMP_COLOR=lyellow; print_color "NO PARTITIONED TABLES\n";unset TEMP_COLOR; return;
  fi
  SCHEMA_NAME=$TRG
  while IFS= read -r tb; do  
    create_placeholder_table $tb
    remove_partitioning_from_placeholder ${tb}_placeholder
    while IIFS= read -r pt; do
       discard_tablespace ${tb}_placeholder;
       find ${BASEDIR}/${TOOL}/stage -name "${tb}\#*\#${pt}.ibd" -exec cp -f {}  ${DATADIR}/${SCHEMA_NAME}/${tb}_placeholder.ibd \; || local ERR=TRUE
       find ${BASEDIR}/${TOOL}/stage -name "${tb}\#*\#${pt}.cfg" -exec cp -f {}  ${DATADIR}/${SCHEMA_NAME}/${tb}_placeholder.cfg \; || local ERR=TRUE
       chown $MARIADB_PROCESS_OWNER:$MARIADB_PROCESS_OWNER ${DATADIR}/${SCHEMA_NAME}/${tb}_placeholder.ibd || local ERR=TRUE
       chown $MARIADB_PROCESS_OWNER:$MARIADB_PROCESS_OWNER ${DATADIR}/${SCHEMA_NAME}/${tb}_placeholder.cfg || local ERR=TRUE
       if [ $ERR ]; then die "something did not work out in transport_tablespaces_for_partitioned_tables."; fi
       import_tablespace ${tb}_placeholder
       exchange_partition_for_partitioned_table ${tb} ${pt}
    done <<< $(mariadb -ABNe "select PARTITION_NAME from information_schema.PARTITIONS where TABLE_NAME='$tb' and TABLE_SCHEMA='$SCHEMA_NAME' order by PARTITION_ORDINAL_POSITION;")
    drop_placeholder_table ${tb}_placeholder
    TEMP_COLOR=lmagenta; print_color "Completed steps for partitioned table $SCHEMA_NAME.${tb}\n";unset TEMP_COLOR;
  done <<< $(cat "$PARTITIONED_TABLE_LIST_FILE")
}

function transport_tablespaces_for_subpartitioned_tables() {
  if [ ! -z "$(cat $SUBPARTITIONED_TABLE_LIST_FILE)" ]; then 
    TEMP_COLOR=lyellow; print_color "TRANSPORTING TABLESPACES FOR SUBPARTITIONED TABLES\n";unset TEMP_COLOR;
  else
    TEMP_COLOR=lyellow; print_color "NO SUBPARTITIONED TABLES\n";unset TEMP_COLOR; return;
  fi
  SCHEMA_NAME=$TRG
  while IFS= read -r tb; do  
    create_placeholder_table $tb
    remove_partitioning_from_placeholder ${tb}_placeholder
    while IIFS= read -r subpt; do
       discard_tablespace ${tb}_placeholder;
       find ${BASEDIR}/${TOOL}/stage -name "${tb}\#*\#${subpt}.ibd" -exec cp -f {}  ${DATADIR}/${SCHEMA_NAME}/${tb}_placeholder.ibd \; || local ERR=TRUE
       find ${BASEDIR}/${TOOL}/stage -name "${tb}\#*\#${subpt}.cfg" -exec cp -f {}  ${DATADIR}/${SCHEMA_NAME}/${tb}_placeholder.cfg \; || local ERR=TRUE
       chown $MARIADB_PROCESS_OWNER:$MARIADB_PROCESS_OWNER ${DATADIR}/${SCHEMA_NAME}/${tb}_placeholder.ibd || local ERR=TRUE
       chown $MARIADB_PROCESS_OWNER:$MARIADB_PROCESS_OWNER ${DATADIR}/${SCHEMA_NAME}/${tb}_placeholder.cfg || local ERR=TRUE
       if [ $ERR ]; then die "something did not work out in transport_tablespaces_for_partitioned_tables."; fi
       import_tablespace ${tb}_placeholder
       exchange_partition_for_partitioned_table ${tb} ${subpt}
    done <<< $(mariadb -ABNe "select SUBPARTITION_NAME from information_schema.PARTITIONS where TABLE_NAME='$tb' and TABLE_SCHEMA='$SCHEMA_NAME' order by PARTITION_ORDINAL_POSITION;")
    drop_placeholder_table ${tb}_placeholder
    TEMP_COLOR=lmagenta; print_color "Completed steps for partitioned table $SCHEMA_NAME.${tb}\n";unset TEMP_COLOR;
  done <<< $(cat "$SUBPARTITIONED_TABLE_LIST_FILE")
}


function verify_dirs() {
  touch ${BASEDIR}/t.txt 2>/dev/null || local ERR=TRUE;
  rm -f ${BASEDIR}/t.txt 2>/dev/null || local ERR=TRUE;
  if [ $ERR ]; then die "$BASEDIR is not a writeable directory."; fi
  touch ${TEMPDIR}/t.txt 2>/dev/null || local ERR=TRUE;
  rm -f ${TEMPDIR}/t.txt 2>/dev/null || local ERR=TRUE;
  if [ $ERR ]; then die "$TEMPDIR is not a writeable directory."; fi
}

 function table_report() {
  local SQL_FILE="$SQL_DIR/TABLE_REPORT.sql"
  local SCHEMA_NAME="$TRG"
  export SCHEMA_NAME
  local SQL=$(envsubst < $SQL_FILE)
  local TABLE_REPORT_OUTPUT=$($CMD_MARIADB $CLOPTS -ABNe "$SQL")
  TEMP_COLOR=lgreen; print_color "$TABLE_REPORT_OUTPUT\n"; unset TEMP_COLOR;
 }

 function tables_not_innodb_report() {
  local SQL_FILE="$SQL_DIR/TABLES_NOT_INNODB.sql"
  local SCHEMA_NAME="$TRG"
  export SCHEMA_NAME
  local SQL=$(envsubst < $SQL_FILE)
  local TABLE_REPORT_OUTPUT=$($CMD_MARIADB $CLOPTS -ABNe "$SQL")
  if [ ! -z "$TABLE_REPORT_OUTPUT" ]; then 
    TEMP_COLOR=lred; print_color "$TABLE_REPORT_OUTPUT\n"; unset TEMP_COLOR; 
    TEMP_COLOR=lyellow; print_color "[ WARNING ] ";unset TEMP_COLOR; 
    printf "Tables with engine not InnodDB do not have transportable tablespaces and their rows will not be restored.\n"
    printf "Continue anyway? Type y to continue.\n";
    read -s -n 1 RESPONSE
    if [ ! "$RESPONSE" = "y" ]; then die "operation cancelled";  fi
  fi
  
 }
 
  function tables_with_unsupported_characters() {
  local SQL_FILE="$SQL_DIR/UNSUPPORTED_TABLE_NAMES_REPORT.sql"
  local SCHEMA_NAME="$TRG"
  export SCHEMA_NAME
  local SQL=$(envsubst < $SQL_FILE)
  local UNSUPPORTED_NAME_REPORT_OUTPUT=$($CMD_MARIADB $CLOPTS -ABNe "$SQL")
  if [ ! -z "$UNSUPPORTED_NAME_REPORT_OUTPUT" ]; then 
    TEMP_COLOR=lred; print_color "$UNSUPPORTED_NAME_REPORT_OUTPUT\n"; unset TEMP_COLOR; 
    TEMP_COLOR=lyellow; print_color "[ WARNING ] ";unset TEMP_COLOR; 
    printf "Tables with unsupported characters in their names will not be restored.\n"
    printf "Continue anyway? Type y to continue.\n";
    read -s -n 1 RESPONSE
    if [ ! "$RESPONSE" = "y" ]; then die "operation cancelled";  fi
  fi
 }
 
 function check_required_privs() {
  if [ "$BYPASS_PRIV_CHECK" == "TRUE" ]; then return; fi
  local SQL_FILE="$SQL_DIR/REQUIRED_PRIVS.sql"
  if [ $SKIP_EVENTS ]; then V_SKIP_EVENTS='SKIP'; else V_SKIP_EVENTS='DO'; fi
  export V_SKIP_EVENTS
  local SQL=$(envsubst < $SQL_FILE)

  if [ ! "$BYPASS_PRIV_CHECK" == "TRUE" ]; then
      ERR=$($CMD_MARIADB $CLOPTS -e "$SQL")
      if [ "$ERR" ]; then die "$ERR"; fi
  fi
  unset V_SKIP_EVENTS
}

function interactive_rm_tool_directory(){
  local SIZE=$(du -sh ${BASEDIR}/${TOOL} | awk '{print $1}')
  TEMP_COLOR=lred; print_color "Note: "; unset TEMP_COLOR;
  printf "The directory ${BASEDIR}/${TOOL} is ${SIZE} in size and contains\nthe files used to restore the schema ${TRG}. Would you like to remove it?\n"; 
  printf "Type y to delete ${BASEDIR}/${TOOL}.\n"; 
  read -s -n 1 RESPONSE
    if [ "$RESPONSE" = "y" ]; then
      if [ -d ${BASEDIR}/${TOOL} ]; then 
        rm -fr ${BASEDIR}/${TOOL}
        echo "Directory removed!"
      fi
    fi 
}
################





for params in "$@"; do
unset VALID; #REQUIRED
# echo "PARAMS: $params"
if [ $(echo "$params"|sed 's,=.*,,') == '--target-schema' ]; then 
  TRG=$(echo "$params" | sed 's/.*=//g'); 
  if [ "$TRG" == '--target-schema' ]; then unset TRG; fi
  if [ ! $TRG ]; then 
   INVALID_INPUT="$params"; 
  else 
   VALID=TRUE; 
  fi
fi

if [ $(echo "$params"|sed 's,=.*,,') == '--base-dir' ]; then 
  BASEDIR=$(echo "$params" | sed 's/.*=//g'); 
  if [ "$BASEDIR" == '--base-dir' ]; then unset BASEDIR; fi
  if [ ! $BASEDIR ]; then 
   INVALID_INPUT="$params"; 
  else 
   VALID=TRUE; 
  fi
fi
  if [ "$params" == '--bypass-priv-check' ]; then BYPASS_PRIV_CHECK='TRUE'; VALID=TRUE; fi
  if [ "$params" == '--compressed=true' ]; then VALID=TRUE; fi # DEFAULT: COMPRESSED=TRUE
  if [ "$params" == '--compressed=false' ]; then unset COMPRESSED; VALID=TRUE; fi 
  if [ "$params" == '--skip-events' ]; then SKIP_EVENTS=TRUE; VALID=TRUE; fi
  if [ "$params" == '--skip-routines' ]; then SKIP_ROUTINES=TRUE; VALID=TRUE; fi
  if [ "$params" == '--version' ]; then DISPLAY_VERSION=TRUE; VALID=TRUE; fi
  if [ "$params" == '--test' ]; then DISPLAY_VERSION=TRUE; VALID=TRUE; fi
  if [ "$params" == '--help' ]; then HELP=TRUE; VALID=TRUE; fi
  if [ ! $VALID ] && [ ! $INVALID_INPUT ];  then  INVALID_INPUT="$params"; fi
done

if [ $(_which mariadb 2>/dev/null) ]; then
  CMD_MARIADB="${CMD_MARIADB:-"$(_which mariadb)"}"
else
  CMD_MARIADB="${CMD_MYSQL:-"$(_which mysql)"}"
fi

CMD_MY_PRINT_DEFAULTS="${CMD_MY_PRINT_DEFAULTS:-"$(_which my_print_defaults)"}"
CMD_MARIABACKUP="${CMD_MARIABACKUP:-"$(_which mariabackup)"}"
CMD_MARIADB_DUMP="${CMD_MARIADB_DUMP:-"$(_which mariadb-dump)"}"


if [ -z $CMD_MARIADB ]; then
  die "mariadb client command not available."
fi


test_dependencies

CLOPTS=$($CMD_MY_PRINT_DEFAULTS --defaults-file=$CONFIG_FILE target | sed -z -e "s/\n/ /g")
if [ -z "$CLOPTS" ]; then CLOPTS="--user=$(whoami)"; fi

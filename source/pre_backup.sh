#!/usr/bin/env bash
# pre_backup.sh
# file distributed with mariadb_schema_transporter
# By Edward Stoever for MariaDB Support

TEMPDIR="/tmp"
CONFIG_FILE="$SCRIPT_DIR/source.cnf"
TOOL="mariadb_schema_transporter"
COMPRESSED="TRUE" # DEFAULT
SQL_DIR="$SCRIPT_DIR/SQL"
TABLE_LIST_FILE="${TEMPDIR}/mariabackup_tables_list.out"
BASEDIR=$TEMPDIR # DEFAULT

function ts() {
   TS=$(date +%F-%T | tr ':-' '_')
   echo "$TS $*"
}

function die() {
   ts "$*" >&2
   exit 1
}


if [ ! $SCRIPT_VERSION ]; then  die "Do not run this script directly. Read the file README.md for help."; fi

function display_help_message() {
printf "This script cannot be run without the source-schema option.
  --source-schema=mydb       # Indicate the schema to backup, this is required
  --base-dir=/opt/mydb_bkup  # Indicate a base directory to store backup. 
                             # Base directory must exist. Default: /tmp 
  --compressed=false         # Do not compress backup into a single file
  --skip-events              # Do not include events in the transported schema
  --skip-routines            # Do not include routines in the transported schema
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
  printf "  │              BACKUP THE SCHEMA ON SOURCE                │\n"
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

if [ ! $SRC ]; then display_help_message; die "You must indicate a source schema."; fi
if [ ! $CAN_CONNECT ]; then 
  TEMP_COLOR=lred; print_color "Failing command: ";unset TEMP_COLOR; 
  TEMP_COLOR=lyellow; print_color "$CMD_MARIADB $CLOPTS\n";unset TEMP_COLOR; 
  local SQL="select now();"
  ERRTEXT=$($CMD_MARIADB $CLOPTS -e "$SQL" 2>&1); TEMP_COLOR=lcyan; print_color "$ERRTEXT\n";unset TEMP_COLOR;
  die "Database connection failed. Read the file README.md. Edit the file quick_review.cnf."; 
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
  if [ "$COMPRESSED" == "TRUE" ]; then
    local subdir="${BASEDIR}/${TOOL}"
  else
    local subdir="${BASEDIR}/${TOOL}/stage"
  fi
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
     # printf "Database Host: "; TEMP_COLOR=lmagenta; print_color "$DBHOST\n"; unset TEMP_COLOR;
     # printf "Client Host:   "; TEMP_COLOR=lmagenta; print_color "$CLIENTHOST\n"; unset TEMP_COLOR;
	  if [ ! $DB_IS_LOCAL ]; then
         printf "Notice:        ";TEMP_COLOR=lred;  print_color "Database is remote. Please run this script locally.\n";unset TEMP_COLOR;
		 die "This script should be run on the host of the database."
	  fi
}


function source_schema_exists(){
  local SQL="select 'YES' as answer from information_schema.SCHEMATA where SCHEMA_NAME='$SRC' limit 1"
  local SRC_SCHEMA_EXISTS=$($CMD_MARIADB $CLOPTS -ABNe "$SQL")

    if [ ! "$SRC_SCHEMA_EXISTS" == "YES" ]; then 
      die "There is no schema named $SRC on this Mariadb Server."
	fi
}

function mariabackup_schema(){
  TEMP_COLOR=lcyan; print_color "Backing up schema $SRC.\n";unset TEMP_COLOR;
  if [ $COMPRESSED ]; then
    if [ -d "${BASEDIR}/${TOOL}/stage" ]; then
      rm -fr "${BASEDIR}/${TOOL}/stage" 2>/dev/null || local ERR=true; 
      if [ $ERR ]; then
        die "could not remove directory ${BASEDIR}/${TOOL}/stage"
      else
        TEMP_COLOR=lgreen; print_color "Removed directory ${BASEDIR}/${TOOL}/stage\n"; unset TEMP_COLOR;
      fi
    fi
    $CMD_MARIABACKUP $CLOPTS --backup --tables-file=$TABLE_LIST_FILE --stream=xbstream | gzip > ${BASEDIR}/${TOOL}/mariabackupstream.gz || local ERR=TRUE;
  else
  $CMD_MARIABACKUP $CLOPTS --backup --tables-file=$TABLE_LIST_FILE --target-dir=${BASEDIR}/${TOOL}/stage  || local ERR=TRUE;
  fi
  if [ $ERR ]; then TEMP_COLOR=lred; print_color "An error has occurred\n"; unset TEMP_COLOR; die "Stopping intentionally.";
  else
    TEMP_COLOR=lmagenta; print_color "Backup completed OK.\n";unset TEMP_COLOR;
  fi 
}


function events_exist(){
  if [ $SKIP_EVENTS ]; then return; fi
  unset EVENTS
  local SQL="select 'YES' as answer from information_schema.EVENTS where EVENT_SCHEMA='$SRC' limit 1"
  local EVENTS_EXIST=$($CMD_MARIADB $CLOPTS -ABNe "$SQL")

    if [ "$EVENTS_EXIST" == "YES" ]; then 
      EVENTS="--events";
	fi
}

function routines_exist(){
  if [ $SKIP_ROUTINES ]; then return; fi
  unset ROUTINES
  local SQL="select 'YES' from information_schema.ROUTINES where ROUTINE_SCHEMA='$SRC' limit 1"
  local ROUTINES_EXIST=$($CMD_MARIADB $CLOPTS -ABNe "$SQL")

    if [ "$ROUTINES_EXIST" == "YES" ]; then 
      ROUTINES="--routines";
	fi
}

function dump_schema() {
  events_exist
  routines_exist
    TEMP_COLOR=lcyan; print_color "Dumping schema $SRC.\n";unset TEMP_COLOR; 
  if [ $COMPRESSED ]; then
    $CMD_MARIADB_DUMP $SRC $CLOPTS $ROUTINES $EVENTS --skip-lock-tables --no-data | gzip > ${BASEDIR}/${TOOL}/source_schema.dump.sql.gz || local ERR=TRUE;
  else
    $CMD_MARIADB_DUMP $SRC $CLOPTS $ROUTINES $EVENTS --skip-lock-tables --no-data > ${BASEDIR}/${TOOL}/stage/source_schema.dump.sql || local ERR=TRUE;
  fi
  if [ $ERR ]; then 
    TEMP_COLOR=lred; print_color "An error has occurred.\n"; unset TEMP_COLOR; die "Stopping intentionally."; 
  else
    TEMP_COLOR=lmagenta; print_color "Dump completed OK.\n";unset TEMP_COLOR;
  fi   
}

function check_required_privs() {
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

function check_tmp_subdir(){
 WC=$(find ${BASEDIR}/${TOOL} -type f 2>/dev/null | wc -l)
 if [ -f ${BASEDIR}/${TOOL}/xtrabackup_info ]; then local NO_OVERWRITE=TRUE; fi
 if [ "$WC" != "0" ] && [ -z $NO_OVERWRITE ]; then
    TEMP_COLOR=lcyan; print_color "There are files in the directory ${BASEDIR}/${TOOL}\n"; unset TEMP_COLOR;
    printf "Type y to continue and overwrite existing files.\n";
    read -s -n 1 RESPONSE
    if [ ! "$RESPONSE" = "y" ]; then die "operation cancelled";  fi
  fi
   if [ "$WC" != "0" ] && [ $NO_OVERWRITE ]; then  
     TEMP_COLOR=lcyan; print_color "There are files in the directory ${BASEDIR}/${TOOL}\n"; unset TEMP_COLOR;
     die "Remove the files in ${BASEDIR}/${TOOL} then re-run this script."
   fi
   
}

function print_table_list_to_file(){
  local SQL="select concat(TABLE_SCHEMA,'.',TABLE_NAME) from information_schema.TABLES where TABLE_SCHEMA='$SRC' AND TABLE_TYPE='BASE TABLE';"
  $CMD_MARIADB $CLOPTS -ABNe "$SQL" > $TABLE_LIST_FILE
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
  local SCHEMA_NAME="$SRC"
  export SCHEMA_NAME
  local SQL=$(envsubst < $SQL_FILE)
  local TABLE_REPORT_OUTPUT=$($CMD_MARIADB $CLOPTS -ABNe "$SQL")
  TEMP_COLOR=lgreen; print_color "$TABLE_REPORT_OUTPUT\n"; unset TEMP_COLOR;
 }

 function tables_not_innodb_report() {
  local SQL_FILE="$SQL_DIR/TABLES_NOT_INNODB.sql"
  local SCHEMA_NAME="$SRC"
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
 
################




for params in "$@"; do
unset VALID; #REQUIRED
# echo "PARAMS: $params"
if [ $(echo "$params"|sed 's,=.*,,') == '--source-schema' ]; then 
  SRC=$(echo "$params" | sed 's/.*=//g'); 
  if [ "$SRC" == '--source-schema' ]; then unset SRC; fi
  if [ ! $SRC ]; then 
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

CLOPTS=$($CMD_MY_PRINT_DEFAULTS --defaults-file=$CONFIG_FILE source | sed -z -e "s/\n/ /g")
if [ -z "$CLOPTS" ]; then CLOPTS="--user=$(whoami)"; fi

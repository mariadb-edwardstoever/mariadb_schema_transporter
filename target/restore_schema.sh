#!/usr/bin/env bash
# backup_schema.sh
# By Edward Stoever for MariaDB Support

### DO NOT EDIT SCRIPT. 
### FOR FULL INSTRUCTIONS: README.md
### FOR BRIEF INSTRUCTIONS: ./restore_schema.sh --help

# Establish working directory and source pre_quick_review.sh
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source ${SCRIPT_DIR}/vsn.sh
source ${SCRIPT_DIR}/pre_restore.sh

display_title;
start_message;
test_dependencies;
stop_here_if_necessary;
whoami_db;
interactive_schema_exists
is_db_localhost;
verify_dirs
prepare_basedir
unpack
prepare_backup
import_dump
table_report
tables_not_innodb_report
print_table_list_to_file
print_partitioned_table_list_to_file
print_subpartitioned_table_list_to_file
set_datadir
foreign_key_checks_off
transport_tablespaces_for_not_partitioned_tables
transport_tablespaces_for_partitioned_tables
transport_tablespaces_for_subpartitioned_tables
foreign_key_checks_on

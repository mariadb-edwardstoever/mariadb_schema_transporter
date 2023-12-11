#!/usr/bin/env bash
# backup_schema.sh
# By Edward Stoever for MariaDB Support

### DO NOT EDIT SCRIPT. 
### FOR FULL INSTRUCTIONS: README.md
### FOR BRIEF INSTRUCTIONS: ./backup_schema.sh --help

# Establish working directory and source pre_quick_review.sh
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source ${SCRIPT_DIR}/../vsn.sh
source ${SCRIPT_DIR}/pre_backup.sh





display_title;
start_message;
test_dependencies;
stop_here_if_necessary;
whoami_db;
is_db_localhost;
source_schema_exists
verify_dirs
table_report
tables_not_innodb_report
print_table_list_to_file
mk_tmpdir
check_tmp_subdir
check_required_privs
mariabackup_schema
dump_schema




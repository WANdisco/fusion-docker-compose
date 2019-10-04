#!/bin/bash

# Purpose: Wrapper to call Docker Compose more easily
#
# Usage: ./dc.sh [<compose-command> | "up -d"]
# Note: if a command arg is not given, the default is "up -d" 

cd $(dirname $0)

# Scan in which Docker Compose file templates and .env files to use
tpl_file="${TPL_MAPPING_FILE:-compose-files-cdh-adls2.txt}"
readarray -t compose_files < ${tpl_file}
compose_files+=(docker-compose.induction.yml)
compose_files+=(docker-compose.oneui.yml)

# Create the '-f' flag for passing to `docker-compose`
f=""
for file in ${compose_files[@]/:.*/}; do
    f+=" -f ${file%.tpl}"
done

# Template the Docker Compose files
./vars.sh -t $tpl_file

# Call `docker-compose` on the files using $action
action=${@:-"up -d"}
docker-compose $f $action

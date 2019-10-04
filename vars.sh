#!/bin/bash

# Purpose: Given a file that maps Docker Compose templates to values,
# generate valid Docker Compose files on a per-Fusion-zone basis.
#
# Usage: ./vars.sh [-t | --tpl] ./compose-files.txt
#

set -e

cd $(dirname $0)

effective_user="$(whoami)"
effective_group="$(whoami)"

tpl_filepath=""

# Take input args
while [[ "$1" =~ ^- && ! "$1" == "--" ]]; do case $1 in
  -t | --tpl )
    shift; tpl_filepath=$1
    ;;
esac; shift; done
if [[ "$1" == '--' ]]; then shift; fi

if [[ $tpl_filepath = "" ]]; then 
  echo "Must specify path to tpl file: -t or --tpl flag"
  exit 1
fi

# Read in what files to do tpl replacement within
readarray -t filepaths < $tpl_filepath

# Read in what vars to replace
scan() {
  local fp=$1
  readarray -t vars < ${fp/.*:/}
  r=$(eval echo ${fp/:.*/})
  dest="${r%.tpl}"
  cp "${r}" "${dest}"
  chown -R ${effective_user}:${effective_group} $dest
}

# Injects the specific vars into their templated placeholders
inject() {
    local tpl_vars=$2[@]
    local ivars=("${!tpl_vars}")
    eval $(echo "export $(printf '%s ' ${ivars[@]})")
    envsubst "$(printf '${%s} ' ${ivars[@]/=*/})" < $1 > $1.tmp && mv $1.tmp $1
    eval "$(printf 'unset %s ' ${ivars[@]/=*/})"
}

# $1 value to extract
# $2 file to extract from
extract() {
  echo "$(sed -n "/$1=/p" $2  | cut -d '=' -f 2)"
}

# $1 fp to trim prefix from
trim_prefix() {
  fp=$1
  echo "${fp/.*:/}"
}

# Define zone-specific metadata for injection
INDUCTOR_ZONE_NAME=$(extract ZONE_NAME $(trim_prefix ${filepaths[0]}))
INDUCTEE_ZONE_NAME=$(extract ZONE_NAME $(trim_prefix ${filepaths[1]}))
INDUCTOR_ZONE_TYPE=$(extract ZONE_TYPE $(trim_prefix ${filepaths[0]}))
INDUCTOR_PORT=$(extract FUSION_SERVER_PORT $(trim_prefix ${filepaths[0]}))
INDUCTEE_PORT=$(extract FUSION_SERVER_PORT $(trim_prefix ${filepaths[1]}))
INDUCTOR_NODE_ID="c7d344e5-b9a4-4726-964d-6a374ce61811"
INDUCTEE_NODE_ID="b2238b71-ba65-4aa8-80b5-012bd0935353"
INDUCTEE_REPLICATION_PORT=$(extract FUSION_REPLICATION_PORT $(trim_prefix ${filepaths[1]}))

i=0   # Counter tracks which zone we are templating

# Expand vars from strings in templated files into config files
for fp in ${filepaths[@]}
do
    scan $fp

    # Iterate vars
    inject $dest vars

    # Inject induction-specific variables
    inductor_env_vars=("FUSION_NODE_ID=${INDUCTOR_NODE_ID}")
    inductee_env_vars=("FUSION_NODE_ID=${INDUCTEE_NODE_ID}")
    if [[ $i -eq 0 ]]; then
      inject $dest inductor_env_vars
    elif [[ $i -eq 1 ]]; then
      inject $dest inductee_env_vars
    fi

    i+=1
done

# Template the induction process
src="./docker-compose.induction.yml.tpl"
dest="${src%.tpl}"
cp ${src} ${dest}
chown -R ${effective_user}:${effective_group} $dest
induction_vars=("INDUCTOR_ZONE_NAME=${INDUCTOR_ZONE_NAME}")
induction_vars+=("INDUCTOR_ZONE_TYPE=${INDUCTOR_ZONE_TYPE}")
induction_vars+=("INDUCTEE_ZONE_NAME=${INDUCTEE_ZONE_NAME}")
induction_vars+=("INDUCTOR_PORT=${INDUCTOR_PORT}")
induction_vars+=("INDUCTEE_PORT=${INDUCTEE_PORT}")
induction_vars+=("INDUCTOR_NODE_ID=${INDUCTOR_NODE_ID}")
induction_vars+=("INDUCTEE_NODE_ID=${INDUCTEE_NODE_ID}")
induction_vars+=("INDUCTEE_REPLICATION_PORT=${INDUCTEE_REPLICATION_PORT}")

inject $dest induction_vars

# Template the OneUI Server
src="./docker-compose.oneui.yml.tpl"
dest="${src%.tpl}"
cp ${src} ${dest}
chown -R ${effective_user}:${effective_group} $dest
readarray -t oneui_vars < ./vars-oneui-2.14.1.0.env

inject $dest oneui_vars

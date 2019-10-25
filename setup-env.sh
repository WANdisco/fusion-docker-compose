#!/bin/sh

CALLED=$_

# check if script has been sourced
IS_SOURCED=1
if [ "$0" = "$BASH_SOURCE" -o "$0" = "$CALLED" -o -z "$CALLED" ]; then
  IS_SOURCED=0
fi

# this script uses relative paths, this cd is more complex with a sourced script
if [ $IS_SOURCED = 1 ]; then
  if [ -n "$BASH_SOURCE" ]; then
    cd "$(dirname $BASH_SOURCE)"
  else
    cd "$(dirname $CALLED)"
  fi
else
  cd "$(dirname $0)"
fi

# check if not running inside a container and missing prereq
inside_container() {
  if grep -q '1:name=systemd:/docker/' </proc/self/cgroup; then
    return 0
  else
    return 1
  fi
}
if ! inside_container && ( \
       [ "$(uname -s)" != "Linux" ] \
    || ! ./utils/uuid-gen.py >/dev/null 2>&1 \
    || [ ! -x "$(command -v envsubst)" ] \
    || [ ! -x "$(command -v getent)" ] \
    ); then
  # TODO: this image needs to be moved to WANdisco's repos
  # for now building on the fly
  # echo "Running setup-env inside a container" >&2
  echo "Warning: dependencies missing, running this command inside of a docker container" >&2
  docker image inspect wandisco/setup-env:0.1 >/dev/null 2>&1 \
    || docker build -t wandisco/setup-env:0.1 .
  docker run -it --rm --net host \
    -u "$(id -u):$(id -g)" \
    -v "$(pwd):$(pwd)" -w "$(pwd)" \
    wandisco/setup-env:0.1 ./setup-env.sh "$@"
  exit $?
fi

opt_f="compose.env"
opt_h=0
opt_a=0

# functions
usage() {
  echo "Usage: $0 [opts]"
  echo " -a: all settings will be prompted"
  echo " -f file: main env file to use (default: ${opt_f})"
  echo " -h: this help message"
  [ "$opt_h" = "1" ] && exit 0 || exit 1
}

load_file() {
  filename="$1"

  while read line; do
    key="$(echo "$line" | sed 's/=.*//')"
    value="$(echo "$line" | sed 's/[^=]*=//')"
    eval "$key=\"$value\""
  done <"$filename"
}

save_var() {
  var="$1"
  new_val="$2"
  filename="$3"

  # check for current version
  cur_val=$([ -f "${filename}" ] && grep "^${var}=" "${filename}" | cut -f2- -d= )

  # if aleady on the right version, return
  if [ "${new_val}" = "${cur_val}" ]; then
    return
  fi

  if [ -n "${cur_val}" ]; then
    # if already set, modify
    sed_safe_val="$(echo "${new_val}" | sed -e 's/[\/&]/\\&/g')"
    sed -i "s/^${var}=.*\$/${var}=${sed_safe_val}/" "${filename}"
  else
    # else append a value to the file
    echo "${var}=${new_val}" >> "${filename}"
  fi
}

update_var() {
  var_name=$1
  var_msg=$2
  default=$3
  validate=$4
  # get the value for $var_name
  var_val=$(eval echo -n \"\$$var_name\")
  # make the existing value the default
  [ -n "${var_val}" ] && default="${var_val}"
  # include the current/default in the prompt
  [ -n "${default}" ] && default_msg=" [${default}]" || default_msg=""
  # prompt the user if a value isn't already defined or override is set
  if [ -z "${var_val}" -o "$opt_a" = "1" ]; then
    read -p "${var_msg}${default_msg}: " ${var_name}
  fi
  var_val=$(eval echo -n \"\$$var_name\")
  # set the value to the default if an empty string entered
  if [ -z "${var_val}" -a -n "${default}" ]; then
    var_val="${default}"
    eval "${var_name}=\"${default}\""
  fi
  # validate the input, rerun the prompt on validation failure
  while [ -n "${validate}" ] && ! eval "${validate}" "${var_val}"; do
    read -p "${var_msg}: " ${var_name}
    var_val=$(eval echo -n \"\$$var_name\")
  done
  if [ -n "${SAVE_ENV}" ]; then
    save_var "${var_name}" "${var_val}" "${SAVE_ENV}"
  fi
  export "$var_name"
  return 0
}

validate_file_path() {
  value="$1"
  if [ -z "$value" ] || [ "$value" != "TRIAL" -a ! -f "$value" ]; then
    echo "Error: File path must exist"
    return 1
  fi
  return 0
}

validate_hostname() {
  hostname=$1

  if [ -z "$hostname" ] || ! getent hosts "$hostname" >/dev/null 2>&1; then
    echo "Error: hostname did not resolve in DNS"
    return 1
  fi
  return 0
}

validate_not_empty() {
  value="$1"
  if [ -z "$value" ]; then
    echo "Error: value cannot be empty"
    return 1
  fi
  return 0
}

validate_not_example() {
  value="$1"
  case "$value" in
    ''|*example*)
      echo "Error: example or empty value is not valid"
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

validate_number() {
  value="$1"
  case "$value" in
    ''|*[!0-9]*)
      echo "Error: value must be a number"
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

validate_zone_name() {
  zone_name=$1
  if [ -z "$zone_name" ] || echo "$zone_name" | egrep -q '[^a-z0-9\-]'; then
    echo "Zone name must only contain lower case letters, numbers, or -, no spaces or other characters"
    return 1
  fi
  return 0
}

validate_zone_name_uniq() {
  validate_zone_name "$@" || return 1
  zone_name=$1
  # for now, with only two zones, this check is simple
  if [ -n "$ZONE_A_NAME" -a -n "$zone_name" -a "$ZONE_A_NAME" = "$zone_name" ] ; then
    echo "Zone name must be unique"
    return 1
  fi
  return 0
}

validate_zone_type() {
  zone_type=$1

  if [ "$zone_type" = "NONE" -o -f "zone-${zone_type}.conf" ]; then
    return 0
  else
    echo "Please choose from one of the following zone types:"
    echo
    for zone in zone-*.conf; do
      zone_type=${zone#zone-}
      echo "  ${zone_type%.conf}"
    done
    echo
    return 1
  fi
}

# parse CLI
while getopts 'af:h' option; do
  case $option in
    a) opt_a=1;;
    f) opt_f="$OPTARG";;
    h) opt_h=1;;
  esac
done
set +e
shift `expr $OPTIND - 1`

if [ $# -gt 0 -o "$opt_h" = "1" ]; then
  usage
fi

# load the cached env
[ -f "./$opt_f" ] && load_file "./$opt_f"

# set default values for variables that could be overridden in compose env
: "${COMMON_ENV:=common.env}"
: "${ZONE_A_ENV:=zone_a.env}"
: "${ZONE_B_ENV:=zone_b.env}"
: "${COMPOSE_FILE_A_OUT:=docker-compose.zone-a.yml}"
: "${COMPOSE_FILE_B_OUT:=docker-compose.zone-b.yml}"
: "${COMPOSE_FILE_COMMON_OUT:=docker-compose.common.yml}"

# run everything below in a subshell to avoid leaking env vars
(
  # common environment setup

  SAVE_ENV=${COMMON_ENV}

  ## load existing common variables
  [ -f "./${COMMON_ENV}" ] && load_file "./${COMMON_ENV}"

  ## default values for variables to avoid prompts
  #: "${ZONE_A_NAME:=zone-a}"
  #: "${ZONE_B_NAME:=zone-b}"

  ## set variables for compose zone a

  validate_zone_type "$ZONE_A_TYPE"
  update_var ZONE_A_TYPE "Enter the first zone type" "" validate_zone_type
  update_var ZONE_A_NAME "Enter the first zone name" "${ZONE_A_TYPE}" validate_zone_name

  ## set variables for compose zone b

  update_var ZONE_B_TYPE "Enter the second zone type (or NONE to skip)" "" validate_zone_type
  if [ "$ZONE_B_TYPE" != NONE ]; then
    update_var ZONE_B_NAME "Enter a name for the second zone" "${ZONE_B_TYPE}" validate_zone_name_uniq
  fi

  ## setup common file
  export ZONE_A_ENV ZONE_B_ENV ZONE_A_NAME ZONE_B_NAME
  # run the common conf
  . "./common.conf"

  if [ -n "${LICENSE_FILE}" -a "${LICENSE_FILE}" != "TRIAL" ]; then
    # force the "./" on the filename for relative paths
    LICENSE_FILE="$(dirname ${LICENSE_FILE})/$(basename ${LICENSE_FILE})"
    export LICENSE_FILE_PATH="- ${LICENSE_FILE}:/etc/wandisco/fusion/server/license.key"
  fi

  ## run zone a setup (use a subshell to avoid leaking env vars)
  (
    default_port_offset=0
    zone_letter=A
    set -a
    SAVE_ENV=${ZONE_A_ENV}
    ZONE_ENV=${ZONE_A_ENV}
    ZONE_NAME=${ZONE_A_NAME}
    ZONE_TYPE=${ZONE_A_TYPE}
    # set common fusion variables
    FUSION_NODE_ID=${ZONE_A_NODE_ID}
    # save common vars to zone file
    save_var ZONE_NAME "$ZONE_NAME" "$SAVE_ENV"
    save_var FUSION_NODE_ID "$FUSION_NODE_ID" "$SAVE_ENV"
    # load any existing zone environment
    [ -f "${ZONE_ENV}" ] && load_file "./${ZONE_ENV}"
    # run the common fusion zone config
    . "./common-fusion.conf"
    # run the zone type config
    . "./zone-${ZONE_TYPE}.conf"
    # re-load variables
    [ -f "./${COMMON_ENV}" ] && load_file "./${COMMON_ENV}"
    [ -f "${ZONE_ENV}" ] && load_file "./${ZONE_ENV}"
    envsubst <"docker-compose.zone-tmpl-${ZONE_TYPE}.yml" >"${COMPOSE_FILE_A_OUT}"
    set +a
  )

  ## run zone b setup (use a subshell to avoid leaking env vars)
  ( if [ "$ZONE_B_TYPE" != "NONE" ]; then
    default_port_offset=500
    zone_letter=B
    set -a
    SAVE_ENV=${ZONE_B_ENV}
    ZONE_ENV=${ZONE_B_ENV}
    ZONE_NAME=${ZONE_B_NAME}
    ZONE_TYPE=${ZONE_B_TYPE}
    # set common fusion variables
    FUSION_NODE_ID=${ZONE_B_NODE_ID}
    # save common vars to zone file
    save_var ZONE_NAME "$ZONE_NAME" "$SAVE_ENV"
    save_var FUSION_NODE_ID "$FUSION_NODE_ID" "$SAVE_ENV"
    # load any existing zone environment
    [ -f "${ZONE_ENV}" ] && load_file "./${ZONE_ENV}"
    # run the common fusion zone config
    . "./common-fusion.conf"
    # run the zone type config
    . "./zone-${ZONE_TYPE}.conf"
    # re-load variables
    [ -f "./${COMMON_ENV}" ] && load_file "./${COMMON_ENV}"
    [ -f "${ZONE_ENV}" ] && load_file "./${ZONE_ENV}"
    envsubst <"docker-compose.zone-tmpl-${ZONE_TYPE}.yml" >"${COMPOSE_FILE_B_OUT}"
    set +a
  fi; )

  ## generate the common yml
  (
    set -a
    # load env files in order of increasing priority
    [ -f "${ZONE_B_ENV}" ] && load_file "./${ZONE_B_ENV}"
    [ -f "${ZONE_A_ENV}" ] && load_file "./${ZONE_A_ENV}"
    [ -f "./${COMMON_ENV}" ] && load_file "./${COMMON_ENV}"
    export COMMON_ENV
    envsubst <"docker-compose.common-tmpl.yml" >"${COMPOSE_FILE_COMMON_OUT}"
    set +a
  )

  # set compose variables
  COMPOSE_FILE="${COMPOSE_FILE_COMMON_OUT}:${COMPOSE_FILE_A_OUT}"
  if [ "$ZONE_B_TYPE" != "NONE" ]; then
    COMPOSE_FILE="${COMPOSE_FILE}:${COMPOSE_FILE_B_OUT}"
  fi

  # write the .env file
  save_var COMPOSE_FILE "$COMPOSE_FILE" .env

  # instructions for the end user
  echo "The docker-compose environment is configured and ready to start. If you need to change these settings run:"
  echo "  ./setup-env.sh -a"
  echo "To start Fusion run the command:"
  echo "  docker-compose up -d"
  echo "Once Fusion starts the UI will be available on:"
  echo "  http://${DOCKER_HOSTNAME}:${ONEUI_SERVER_PORT}"
)


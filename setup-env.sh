#!/bin/bash

MINIMUM_DOCKER_VERSION="18.09.7"
MINIMUM_DOCKER_COMPOSE_VERSION="1.24.1"

cd "$(dirname $0)"

print_warning() {
  echo "Warning: $@"
}

docker_warning() {
  print_warning "$@"
  echo "  For installation details, please see: https://docs.docker.com/install/"
  echo ""
}

docker_compose_warning() {
  print_warning "$@"
  echo "  For installation details, please see: https://docs.docker.com/compose/install/"
  echo ""
}

has_docker() {
  local docker_version=$(docker version  --format '{{.Server.Version}}')
  local ret="$?"
  local lowest_sorted_docker_version=$(printf "$MINIMUM_DOCKER_VERSION\n$docker_version" | sort -V | head -1)
  if [ "$ret" != "0" ] || [ -z "$docker_version" ]; then
    docker_warning "docker is either not installed or not running, docker version $MINIMUM_DOCKER_VERSION or above should be installed and running"
    # If the minimum version is sorted to the top then our version is >= the min
  elif [ "$lowest_sorted_docker_version" != "$MINIMUM_DOCKER_VERSION" ]; then
    docker_warning "docker version should be $MINIMUM_DOCKER_VERSION or above (found: $docker_version)"
  fi
}

has_docker_compose() {
  local docker_compose_version=$(docker-compose version --short)
  local ret="$?"
  local lowest_sorted_docker_compose_version=$(printf "$MINIMUM_DOCKER_COMPOSE_VERSION\n$docker_compose_version" | sort -V | head -1)
  if [ "$ret" != "0" ]; then
    docker_compose_warning "docker-compose must be installed to run the fusion environment"
  elif [ "$lowest_sorted_docker_compose_version" != "$MINIMUM_DOCKER_COMPOSE_VERSION" ]; then
    docker_compose_warning "docker-compose version should be $MINIMUM_DOCKER_COMPOSE_VERSION or above (found: $docker_compose_version)"
  fi
}

usage() {
  echo "Usage: $0 [opts]"
  echo " -a: all settings will be prompted"
  echo " -f file: main env file to use (default: ${opt_f})"
  echo " -h: this help message"
  echo " -s: skip validation of inputs"
  echo " -m: deploy monitoring example (only for HDP/CDH main use cases)"
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

  eval "$var=\"$new_val\""

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
  var_name="$1"
  var_msg="$2"
  default="$3"
  validate="$4"
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
  while [ -n "${validate}" ] && [ "$opt_s" != "1" ] && ! eval \"${validate}\" \"${var_val}\"; do
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
  hostname="$1"

  validate_not_empty "$hostname"
  return $?
}

validate_not_empty() {
  value="$1"
  if [ -z "$value" ]; then
    echo "Error: value cannot be empty"
    return 1
  fi
  return 0
}

validate_yn() {
  local value="$1"
  case "$value" in
    y|Y) return 0 ;;
    n|N) return 0 ;;
    *)
      echo "Please enter 'y' or 'n'"
      return 1
    ;;
  esac
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

validate_plugin() {
  value="$1"
  case "$value" in
    databricks)
      # TODO: validate zone type/version compatibility
      return 0
      ;;
    livehive)
      # TODO: validate zone type/version compatibility
      return 0
      ;;
    NONE)
      return 0
      ;;
    *)
      echo "Error: unknown plugin. Valid options are: databricks, livehive, NONE"
      return 1
      ;;
  esac
}

validate_zone_name() {
  zone_name="$1"
  if [ -z "$zone_name" ] || echo "$zone_name" | egrep -q '[^a-z0-9\-]'; then
    echo "Zone name must only contain lower case letters, numbers, or -, no spaces or other characters"
    return 1
  fi
  return 0
}

validate_zone_name_uniq() {
  validate_zone_name "$@" || return 1
  zone_name="$1"
  # for now, with only two zones, this check is simple
  if [ -n "$ZONE_A_NAME" -a -n "$zone_name" -a "$ZONE_A_NAME" = "$zone_name" ] ; then
    echo "Zone name must be unique"
    return 1
  fi
  return 0
}

validate_hdp_custom_type() {
  type="$1"
  case "$type" in
    1|2|3)     return 0;;
  esac
  # for anything not matched by the above case, validation failed
  cat <<EOZONE

Please choose from one of the following zone types:

  1. HDP Sandbox with custom distribution
  2. HDP Sandbox Vanilla
  3. HDP Sandbox Vanilla with LiveData Migrator

EOZONE
  return 1
}

validate_cdh_custom_type() {
  type="$1"
  case "$type" in
    1|2)     return 0;;
  esac
  # for anything not matched by the above case, validation failed
  cat <<EOZONE

Please choose from one of the following zone types:

  1. CDH Sandbox with custom distribution
  2. CDH Sandbox Vanilla

EOZONE
  return 1
}

validate_deployment_type() {
  deployment_type="$1"
  case "$deployment_type" in
    1|2|3|4|5|6|7|8|9)     return 0;;
  esac
  # for anything not matched by the above case, validation failed
  cat <<EOZONE

Please choose from one of the following WANdisco Fusion deployment options:

  1. HDP Sandbox to ADLS Gen2, Live Hive and Databricks integration ${MONITORING_MESSAGE}
  2. HDP Sandbox to S3 ${MONITORING_MESSAGE}
  3. HDP Sandbox to custom distribution
  4. ADLS Gen1 to Gen2
  5. S3 and ADLS Gen2
  6. CDH Sandbox to ADLS Gen2, Live Hive and Databricks integration ${MONITORING_MESSAGE}
  7. CDH Sandbox to S3 ${MONITORING_MESSAGE}
  8. CDH Sandbox to custom distribution
  9. Custom deployment

EOZONE
  return 1
}

validate_zone_type() {
  zone_type="$1"

  case "$zone_type" in
    NONE)                        return 0;; # TODO: verify at least zone A is defined
    adls1|adls2)                 return 0;;
    s3|hcfs-emr)                 return 0;;
    cdh|cdh-vanilla|hdp|hdp-vanilla)         return 0;;
    alibaba-emr)                 return 0;;
  esac
  # for anything not matched by the above case, validation failed
  cat <<EOZONE

Please choose from one of the following zone types:

  adls1:       Azure Data Lake Storage Gen1
  adls2:       Azure Data Lake Storage Gen2
  s3:          AWS S3 Unmanaged
  hcfs-emr:    AWS HCFS EMR
  cdh:         Cloudera Hadoop
  hdp:         Hortonworks Hadoop
  alibaba-emr: Alibaba EMR

EOZONE
  return 1
}


if [ -z "$RUN_IN_CONTAINER" ]; then
  has_docker
  has_docker_compose
  terminal="-it"

  #Check if FD 0 (standard input) is not a TTY
  if [ ! -t 0 ]; then
    terminal=""
  fi

  echo "Getting the latest Fusion Setup image"
  docker run $terminal --rm --net host \
    -u "$(id -u):$(id -g)" \
    -v "$(pwd):$(pwd)" -w "$(pwd)" \
    -e RLWRAP_HOME=$(pwd) \
    -e RUN_IN_CONTAINER=true \
    -e MIGRATOR_ALLOW_STOP_PATH="${MIGRATOR_ALLOW_STOP_PATH:-false}" \
    -e FUS_REGISTRY="${FUS_REGISTRY:-wandisco}" \
    wandisco/setup-env:0.3 rlwrap ./setup-env.sh "$@"
  exit $?
fi

opt_f="compose.env"
opt_h=0
opt_a=0
opt_s=0
opt_m=0

while getopts 'af:hsm' option; do
  case $option in
    a) opt_a=1;;
    f) opt_f="$OPTARG";;
    h) opt_h=1;;
    s) opt_s=1;;
    m)
      opt_m=1
      MONITORING_MESSAGE="(with monitoring example)"
      JVM_ARG="-Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.port=9010 \
-Dcom.sun.management.jmxremote.rmi.port=9010 -Dcom.sun.management.jmxremote.local.only=false \
-Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false"
    ;;
    ?) exit 1;;
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
: "${COMPOSE_FILE_A_PLUGIN_OUT:=docker-compose.zone-a-plugin.yml}"
: "${COMPOSE_FILE_B_OUT:=docker-compose.zone-b.yml}"
: "${COMPOSE_FILE_INDUCT_OUT:=docker-compose.induction.yml}"
: "${COMPOSE_FILE_B_PLUGIN_OUT:=docker-compose.zone-b-plugin.yml}"
: "${COMPOSE_FILE_COMMON_OUT:=docker-compose.common.yml}"
: "${COMPOSE_FILE_SANDBOX_HDP_OUT:=docker-compose.sandbox-hdp.yml}"
: "${COMPOSE_FILE_SANDBOX_CDH_OUT:=docker-compose.sandbox-cdh.yml}"
: "${COMPOSE_FILE_MONITORING_OUT:=docker-compose.monitoring.yml}"
: "${COMPOSE_FILE_LDM_OUT:=docker-compose.livedata-migrator.yml}"
: "${COMPOSE_FILE_SANDBOX_HDP_VANILLA_OUT:=docker-compose.sandbox-hdp-vanilla.yml}"
: "${COMPOSE_FILE_SANDBOX_HDP_VANILLA_EXTENDED_OUT:=docker-compose.sandbox-hdp-vanilla-extended.yml}"
: "${COMPOSE_FILE_SANDBOX_CDH_VANILLA_OUT:=docker-compose.sandbox-cdh-vanilla.yml}"

# run everything below in a subshell to avoid leaking env vars
(
  # common environment setup
  SAVE_ENV=${COMMON_ENV}

  ## load existing common variables
  [ -f "./${COMMON_ENV}" ] && load_file "./${COMMON_ENV}"

  if [[ -z "$DEPLOYMENT_TYPE" && -n "$USE_SANDBOX" ]]; then
    case $USE_SANDBOX in
      y|Y)
        DEPLOYMENT_TYPE="1"
      ;;
      n|N)
        DEPLOYMENT_TYPE="4"
      ;;
    esac
  fi

  validate_deployment_type "$DEPLOYMENT_TYPE"
  update_var DEPLOYMENT_TYPE "Select the deployment you would like to use" "1" validate_deployment_type

  case $DEPLOYMENT_TYPE in
    *)
      save_var DEPLOYMENT_TYPE "${DEPLOYMENT_TYPE}" "$SAVE_ENV"
    ;;&
    1|2|6|7)
      if [ "$opt_m" = "1" ]; then
        save_var USE_MONITORING "y" "$SAVE_ENV"
        save_var JVM_ARG "${JVM_ARG}" "$ZONE_A_ENV"
        save_var JVM_ARG "${JVM_ARG}" "$ZONE_B_ENV"
      fi
    ;;&
    1|2)
      save_var USE_SANDBOX "y" "$SAVE_ENV"
      save_var ZONE_A_TYPE "hdp" "$SAVE_ENV"
      save_var ZONE_A_NAME "sandbox-hdp" "$SAVE_ENV"
      save_var HDP_VERSION "2.6.5" "$ZONE_A_ENV"
      save_var HADOOP_NAME_NODE_HOSTNAME "sandbox-hdp" "$ZONE_A_ENV"
      save_var HADOOP_NAME_NODE_PORT "8020" "$ZONE_A_ENV"
      save_var NAME_NODE_PROXY_HOSTNAME "sandbox-hdp" "$ZONE_A_ENV"
      save_var FUSION_NAME_NODE_SERVICE_NAME "$NAME_NODE_PROXY_HOSTNAME:8020" "$ZONE_A_ENV"
      save_var HIVE_METASTORE_HOSTNAME "sandbox-hdp" "$ZONE_A_ENV"
      save_var HIVE_METASTORE_PORT "9083" "$ZONE_A_ENV"
    ;;&
    3)
      validate_hdp_custom_type "$HDP_SANDBOX_TYPE"
      update_var HDP_SANDBOX_TYPE "Select the HDP Sandbox type you would like to use" "1" validate_hdp_custom_type
      case $HDP_SANDBOX_TYPE in
        *)
          save_var HDP_SANDBOX_TYPE "${HDP_SANDBOX_TYPE}" "$SAVE_ENV"
        ;;&
        1)
          save_var USE_SANDBOX "y" "$SAVE_ENV"
          save_var ZONE_A_TYPE "hdp" "$SAVE_ENV"
          save_var ZONE_A_NAME "sandbox-hdp" "$SAVE_ENV"
          save_var HDP_VERSION "2.6.5" "$ZONE_A_ENV"
          save_var HADOOP_NAME_NODE_HOSTNAME "sandbox-hdp" "$ZONE_A_ENV"
          save_var HADOOP_NAME_NODE_PORT "8020" "$ZONE_A_ENV"
          save_var NAME_NODE_PROXY_HOSTNAME "sandbox-hdp" "$ZONE_A_ENV"
          save_var FUSION_NAME_NODE_SERVICE_NAME "$NAME_NODE_PROXY_HOSTNAME:8020" "$ZONE_A_ENV"
          save_var HIVE_METASTORE_HOSTNAME "sandbox-hdp" "$ZONE_A_ENV"
          save_var HIVE_METASTORE_PORT "9083" "$ZONE_A_ENV"
        ;;
        2|3)
          save_var USE_SANDBOX "y" "$SAVE_ENV"
          save_var DOCKER_HOSTNAME "hdp_vanilla-custom" "$SAVE_ENV"
          save_var ZONE_A_TYPE "hdp-vanilla" "$SAVE_ENV"
          save_var ZONE_A_NAME "sandbox-hdp-vanilla" "$SAVE_ENV"
          save_var ZONE_B_TYPE "NONE" "$SAVE_ENV"
        ;;&
        3)
          save_var USE_LDM "y" "$SAVE_ENV"
        ;;
      esac
    ;;&
    6|7)
      save_var USE_SANDBOX "y" "$SAVE_ENV"
      save_var ZONE_A_TYPE "cdh" "$SAVE_ENV"
      save_var ZONE_A_NAME "sandbox-cdh" "$SAVE_ENV"
      save_var CDH_VERSION "5.16.0" "$ZONE_A_ENV"
      save_var HADOOP_NAME_NODE_HOSTNAME "sandbox-cdh" "$ZONE_A_ENV"
      save_var HADOOP_NAME_NODE_PORT "8020" "$ZONE_A_ENV"
      save_var NAME_NODE_PROXY_HOSTNAME "sandbox-cdh" "$ZONE_A_ENV"
      save_var FUSION_NAME_NODE_SERVICE_NAME "$NAME_NODE_PROXY_HOSTNAME:8020" "$ZONE_A_ENV"
      save_var HIVE_METASTORE_HOSTNAME "sandbox-cdh" "$ZONE_A_ENV"
      save_var HIVE_METASTORE_PORT "9083" "$ZONE_A_ENV"
    ;;&
    8)
      validate_cdh_custom_type "$CDH_SANDBOX_TYPE"
      update_var CDH_SANDBOX_TYPE "Select the CDH Sandbox type you would like to use" "1" validate_cdh_custom_type
      case $CDH_SANDBOX_TYPE in
        *)
          save_var CDH_SANDBOX_TYPE "${CDH_SANDBOX_TYPE}" "$SAVE_ENV"
        ;;&
        1)
          save_var USE_SANDBOX "y" "$SAVE_ENV"
          save_var ZONE_A_TYPE "cdh" "$SAVE_ENV"
          save_var ZONE_A_NAME "sandbox-cdh" "$SAVE_ENV"
          save_var CDH_VERSION "5.16.0" "$ZONE_A_ENV"
          save_var HADOOP_NAME_NODE_HOSTNAME "sandbox-cdh" "$ZONE_A_ENV"
          save_var HADOOP_NAME_NODE_PORT "8020" "$ZONE_A_ENV"
          save_var NAME_NODE_PROXY_HOSTNAME "sandbox-cdh" "$ZONE_A_ENV"
          save_var FUSION_NAME_NODE_SERVICE_NAME "$NAME_NODE_PROXY_HOSTNAME:8020" "$ZONE_A_ENV"
          save_var HIVE_METASTORE_HOSTNAME "sandbox-cdh" "$ZONE_A_ENV"
          save_var HIVE_METASTORE_PORT "9083" "$ZONE_A_ENV"
        ;;
        2)
          save_var USE_SANDBOX "y" "$SAVE_ENV"
          save_var DOCKER_HOSTNAME "cdh_vanilla-custom" "$SAVE_ENV"
          save_var ZONE_A_TYPE "cdh-vanilla" "$SAVE_ENV"
          save_var ZONE_A_NAME "sandbox-cdh-vanilla" "$SAVE_ENV"
          save_var ZONE_B_TYPE "NONE" "$SAVE_ENV"
        ;;
      esac
    ;;&
    1|4|5|6)
      save_var ZONE_B_TYPE "adls2" "$SAVE_ENV"
      save_var ZONE_B_NAME "adls2" "$SAVE_ENV"
      save_var HDI_VERSION "3.6" "$ZONE_B_ENV"
    ;;&
    1|6)
      save_var ZONE_A_PLUGIN "livehive" "$ZONE_A_ENV"
      save_var ZONE_B_PLUGIN "databricks" "$ZONE_B_ENV"
    ;;&
    2|7)
      save_var ZONE_B_TYPE "s3" "$SAVE_ENV"
      save_var ZONE_B_NAME "s3" "$SAVE_ENV"
    ;;&
    4)
      save_var ZONE_A_TYPE "adls1" "$SAVE_ENV"
      save_var ZONE_A_NAME "adls1" "$SAVE_ENV"
      save_var HDI_VERSION "3.6" "$ZONE_B_ENV"
    ;;&
    5)
      save_var ZONE_A_TYPE "s3" "$SAVE_ENV"
      save_var ZONE_A_NAME "s3" "$SAVE_ENV"
    ;;&
    2|4|5|7)
      save_var ZONE_A_PLUGIN "NONE" "$ZONE_A_ENV"
      save_var ZONE_B_PLUGIN "NONE" "$ZONE_B_ENV"
    ;;&
    1|2|4|5|6|7)
      save_var DOCKER_HOSTNAME "$ZONE_A_TYPE-$ZONE_B_TYPE" "$SAVE_ENV"
    ;;
    3)
      save_var DOCKER_HOSTNAME "hdp-custom" "$SAVE_ENV"
    ;;
    8)
      save_var DOCKER_HOSTNAME "cdh-custom" "$SAVE_ENV"
    ;;
    9)
      save_var USE_SANDBOX "n" "$SAVE_ENV"
    ;;
  esac

  validate_zone_type "$ZONE_A_TYPE"
  update_var ZONE_A_TYPE "Enter the first zone type" "" validate_zone_type
  validate_zone_type "$ZONE_B_TYPE"
  update_var ZONE_B_TYPE "Enter the second zone type (or NONE to skip)" "" validate_zone_type

  if [ "$ZONE_B_TYPE" != NONE ]; then
    update_var ZONE_A_NAME "Enter a name for the first zone" "${ZONE_A_TYPE}" validate_zone_name
    update_var ZONE_B_NAME "Enter a name for the second zone" "${ZONE_B_TYPE}" validate_zone_name_uniq
  else
    if [[ "$ZONE_A_TYPE" != "hdp-vanilla" && "$ZONE_A_TYPE" != "cdh-vanilla" ]]; then
      unset ZONE_A_NAME
      update_var ZONE_A_NAME "Enter a name for the first zone" "${ZONE_A_TYPE}-$(shuf -i 1-9999 -n 1)" validate_zone_name
    fi
  fi

  ## setup common file
  export ZONE_A_ENV ZONE_B_ENV ZONE_A_NAME ZONE_B_NAME
  # run the common conf
  . "./common.conf"

  ## run zone a setup (use a subshell to avoid leaking env vars)
  ( if [[ "$ZONE_A_TYPE" != "hdp-vanilla" && "$ZONE_A_TYPE" != "cdh-vanilla" ]]; then
    default_port_offset=0
    zone_letter=A
    set -a
    SAVE_ENV=${ZONE_A_ENV}
    ZONE_ENV=${ZONE_A_ENV}
    ZONE_NAME=${ZONE_A_NAME}
    ZONE_TYPE=${ZONE_A_TYPE}
    save_var ZONE_TYPE "$ZONE_TYPE" "$SAVE_ENV"
    # set common fusion variables
    FUSION_NODE_ID=${ZONE_A_NODE_ID}
    # save common vars to zone file
    save_var ZONE_NAME "$ZONE_NAME" "$SAVE_ENV"
    save_var FUSION_NODE_ID "$FUSION_NODE_ID" "$SAVE_ENV"

    if [ "$ZONE_B_TYPE" != NONE ]; then
      save_var FUSION_SERVER_HOST "fusion-server-$ZONE_NAME" "$ZONE_ENV"
      save_var IHC_SERVER_HOST "fusion-ihc-server-$ZONE_NAME" "$ZONE_ENV"
    else
      update_var HOST_ADDRESS "Enter the ip address or DNS name of the current host" "" validate_hostname
      save_var FUSION_SERVER_HOST "${HOST_ADDRESS}" "$ZONE_ENV"
      save_var IHC_SERVER_HOST "${HOST_ADDRESS}" "$ZONE_ENV"
    fi

    save_var INTERNAL_FUSION_SERVER_HOST "fusion-server-$ZONE_NAME" "$ZONE_ENV"
    # load any existing zone environment
    [ -f "${ZONE_ENV}" ] && load_file "./${ZONE_ENV}"
    # run the common fusion zone config
    . "./common-fusion.conf"

    save_var ZONE_A_FUSION_IHC_SERVER_PORT "${FUSION_IHC_SERVER_PORT}" "$COMMON_ENV"

    # run the zone type config
    . "./zone-${ZONE_TYPE}.conf"
    # re-load variables
    [ -f "./${COMMON_ENV}" ] && load_file "./${COMMON_ENV}"
    [ -f "${ZONE_ENV}" ] && load_file "./${ZONE_ENV}"
    COMPOSE_ZONE_A="${COMPOSE_FILE_A_OUT}"
    # configure plugins
    update_var ZONE_A_PLUGIN "Select plugin for ${ZONE_NAME} (livehive, databricks or NONE to skip)" "NONE" validate_plugin
    ZONE_PLUGIN=${ZONE_A_PLUGIN}
    save_var ZONE_PLUGIN "$ZONE_PLUGIN" "$ZONE_ENV"
    if [ "$ZONE_A_PLUGIN" != "NONE" ]; then
      [ -f "./plugin-${ZONE_PLUGIN}.conf" ] && . "./plugin-${ZONE_PLUGIN}.conf"
      if [ -f "docker-compose.plugin-tmpl-${ZONE_PLUGIN}.yml" ]; then
        [ -f "${ZONE_ENV}" ] && load_file "./${ZONE_ENV}"
        envsubst <"docker-compose.plugin-tmpl-${ZONE_PLUGIN}.yml" >"${COMPOSE_FILE_A_PLUGIN_OUT}"
        COMPOSE_ZONE_A="${COMPOSE_ZONE_A}:${COMPOSE_FILE_A_PLUGIN_OUT}"
      fi
    fi
    envsubst <"docker-compose.zone-tmpl-${ZONE_TYPE}.yml" >"${COMPOSE_FILE_A_OUT}"
    save_var COMPOSE_ZONE_A "${COMPOSE_ZONE_A}" "${COMMON_ENV}"
    set +a
  fi; )

  ## run zone b setup (use a subshell to avoid leaking env vars)
  ( if [[ "$ZONE_B_TYPE" != "NONE" ]]; then
    default_port_offset=500
    zone_letter=B
    set -a
    SAVE_ENV=${ZONE_B_ENV}
    ZONE_ENV=${ZONE_B_ENV}
    ZONE_NAME=${ZONE_B_NAME}
    ZONE_TYPE=${ZONE_B_TYPE}
    save_var ZONE_TYPE "$ZONE_TYPE" "$SAVE_ENV"
    # set common fusion variables
    FUSION_NODE_ID=${ZONE_B_NODE_ID}
    # save common vars to zone file
    save_var ZONE_NAME "$ZONE_NAME" "$SAVE_ENV"
    save_var FUSION_NODE_ID "$FUSION_NODE_ID" "$SAVE_ENV"
    save_var FUSION_SERVER_HOST "fusion-server-$ZONE_NAME" "$ZONE_ENV"
    save_var INTERNAL_FUSION_SERVER_HOST "fusion-server-$ZONE_NAME" "$ZONE_ENV"
    save_var IHC_SERVER_HOST "fusion-ihc-server-$ZONE_NAME" "$ZONE_ENV"

    # load any existing zone environment
    [ -f "${ZONE_ENV}" ] && load_file "./${ZONE_ENV}"
    # run the common fusion zone config
    . "./common-fusion.conf"

    save_var ZONE_B_FUSION_IHC_SERVER_PORT "${FUSION_IHC_SERVER_PORT}" "$COMMON_ENV"

    # run the zone type config
    . "./zone-${ZONE_TYPE}.conf"
    # re-load variables
    [ -f "./${COMMON_ENV}" ] && load_file "./${COMMON_ENV}"
    [ -f "${ZONE_ENV}" ] && load_file "./${ZONE_ENV}"
    COMPOSE_ZONE_B="${COMPOSE_FILE_B_OUT}"
    # configure plugins
    update_var ZONE_B_PLUGIN "Select plugin for ${ZONE_NAME} (livehive, databricks or NONE to skip)" "NONE" validate_plugin
    ZONE_PLUGIN=${ZONE_B_PLUGIN}
    save_var ZONE_PLUGIN "$ZONE_PLUGIN" "$ZONE_ENV"
    if [ "$ZONE_B_PLUGIN" != "NONE" ]; then
      [ -f "./plugin-${ZONE_PLUGIN}.conf" ] && . "./plugin-${ZONE_PLUGIN}.conf"
      if [ -f "docker-compose.plugin-tmpl-${ZONE_PLUGIN}.yml" ]; then
        [ -f "${ZONE_ENV}" ] && load_file "./${ZONE_ENV}"
        envsubst <"docker-compose.plugin-tmpl-${ZONE_PLUGIN}.yml" >"${COMPOSE_FILE_B_PLUGIN_OUT}"
        COMPOSE_ZONE_B="${COMPOSE_ZONE_B}:${COMPOSE_FILE_B_PLUGIN_OUT}"
      fi
    fi
    envsubst <"docker-compose.zone-tmpl-${ZONE_TYPE}.yml" >"${COMPOSE_FILE_B_OUT}"
    envsubst <"docker-compose.induction-tmpl.yml" >"${COMPOSE_FILE_INDUCT_OUT}"
    save_var COMPOSE_ZONE_B ":${COMPOSE_ZONE_B}:${COMPOSE_FILE_INDUCT_OUT}" "${COMMON_ENV}"
    set +a
  fi; )

  if [ "$ZONE_B_TYPE" != "NONE" ]; then
    FUSION_SERVER_HOSTNAMES=",http://fusion-server-${ZONE_B_NAME}:${ZONE_B_SERVER_PORT}"
  fi

  if [[ "$ZONE_A_TYPE" != "hdp-vanilla" && "$ZONE_A_TYPE" != "cdh-vanilla" ]]; then
    FUSION_SERVER_HOSTNAMES="http://fusion-server-${ZONE_A_NAME}:${ZONE_A_SERVER_PORT}${FUSION_SERVER_HOSTNAMES}"
    save_var FUSION_SERVER_HOSTNAMES "$FUSION_SERVER_HOSTNAMES" "${COMMON_ENV}"
  fi

  ## generate the common yml
  set -a
  # load env files in order of increasing priority
  [ -f "${ZONE_B_ENV}" ] && load_file "./${ZONE_B_ENV}"
  [ -f "${ZONE_A_ENV}" ] && load_file "./${ZONE_A_ENV}"
  [ -f "./${COMMON_ENV}" ] && load_file "./${COMMON_ENV}"
  export COMMON_ENV

  if [[ "$ZONE_A_TYPE" != "hdp-vanilla" && "$ZONE_A_TYPE" != "cdh-vanilla" || "$USE_LDM" = "y" ]]; then
    envsubst <"docker-compose.common-tmpl.yml" >"${COMPOSE_FILE_COMMON_OUT}"
  fi

  set +a

  # set compose variables
  COMPOSE_FILE=${COMPOSE_FILE_COMMON_OUT}
  if [[ "$ZONE_A_TYPE" != "hdp-vanilla" && "$ZONE_A_TYPE" != "cdh-vanilla" ]]; then
    COMPOSE_FILE="${COMPOSE_FILE}:${COMPOSE_ZONE_A}${COMPOSE_ZONE_B}"
  fi

  if [ "$USE_SANDBOX" = "y" ]; then
    case "$ZONE_A_TYPE" in
      hdp-vanilla)
        COMPOSE_FILE="${COMPOSE_FILE_SANDBOX_HDP_VANILLA_OUT}"
        if [ "$USE_LDM" = "y" ]; then
          COMPOSE_FILE="${COMPOSE_FILE}:${COMPOSE_FILE_COMMON_OUT}:${COMPOSE_FILE_LDM_OUT}"
          save_var LDM_SERVERS "livedata-migrator:18080" "${COMMON_ENV}"
        else
          COMPOSE_FILE="${COMPOSE_FILE}:${COMPOSE_FILE_SANDBOX_HDP_VANILLA_EXTENDED_OUT}"
        fi
      ;;
      cdh-vanilla)
        COMPOSE_FILE="${COMPOSE_FILE_SANDBOX_CDH_VANILLA_OUT}"
      ;;
      hdp|cdh)
        save_var ZONE_PLUGIN "${ZONE_A_PLUGIN}" sandbox.env
        COMPOSE_FILE="${COMPOSE_FILE}:docker-compose.sandbox-${ZONE_A_TYPE}.yml"
        if [ "$USE_MONITORING" = "y" ]; then
          envsubst <"docker-compose.monitoring-tmpl.yml" >"${COMPOSE_FILE_MONITORING_OUT}"
          COMPOSE_FILE="${COMPOSE_FILE}:${COMPOSE_FILE_MONITORING_OUT}"
        fi
      ;;&
      hdp)
        envsubst <"docker-compose.sandbox-${ZONE_A_TYPE}-tmpl.yml" >"${COMPOSE_FILE_SANDBOX_HDP_OUT}"
      ;;
      cdh)
        envsubst <"docker-compose.sandbox-${ZONE_A_TYPE}-tmpl.yml" >"${COMPOSE_FILE_SANDBOX_CDH_OUT}"
      ;;
    esac
  fi

  # write the .env file
  save_var COMPOSE_FILE "$COMPOSE_FILE" .env
  save_var COMPOSE_PROJECT_NAME "$COMPOSE_PROJECT_NAME" .env
  save_var COMPOSE_HTTP_TIMEOUT 600 .env

  # instructions for the end user
  echo "The docker-compose environment is configured and ready to start. If you need to change these settings run:"
  echo "  ./setup-env.sh -a"

  if [ "$USE_SANDBOX" = "y" ]; then
    echo "Once services starts the following interfaces will be available on this host:"
    echo
    case $ZONE_A_TYPE in
      cdh|cdh-vanilla)
        echo "  Cloudera: 7180"
      ;;
      hdp|hdp-vanilla)
        echo "  Ambari: 8080"
      ;;
    esac
    echo "  LiveData UI: ${LIVEDATA_UI_PORT}"
    echo
    echo "Please be aware that it may take some time for these ports to be fully available."
  else
    echo "Once Fusion starts the UI will be available on:"
    echo "  http://${DOCKER_HOSTNAME}:${LIVEDATA_UI_PORT} or http://ip-address:${LIVEDATA_UI_PORT} using the IP of your docker host."
  fi

  echo
  echo "To start Fusion run the command:"
  echo "  docker-compose up -d"
)

#!/usr/bin/env bash

function parent_domain() {
  set -- ${1//\./ }
  shift
  set -- "$@"
  parent="$*"
  parent=${parent//\ /\.}
  echo $parent
}

function log() {
  /usr/bin/logger ${LOGGER_FLAGS} "$@"
}

alias log="/usr/bin/logger ${LOGGER_FLAGS}"

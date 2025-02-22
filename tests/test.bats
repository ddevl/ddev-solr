#!/bin/bash

setup() {
  set -eu -o pipefail
  export DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )/.."
  export TESTDIR=~/tmp/test-solr
  mkdir -p $TESTDIR
  export PROJNAME=test-solr
  export DDEV_NON_INTERACTIVE=true
  ddev delete -Oy ${PROJNAME} >/dev/null 2>&1 || true
  cd "${TESTDIR}"
  ddev config --project-name=${PROJNAME}
  ddev start -y >/dev/null
}

health_checks() {
  # Check that the techproducts configset can be uploaded and a corresponding collection will be created
  docker cp ddev-${PROJNAME}-solr:/opt/solr/server/solr/configsets/sample_techproducts_configs .ddev/solr/configsets/techproducts
  ddev restart
  # Wait for Solr to be ready
  while true; do
    # Try to reach the Solr admin ping URL
    if curl --output /dev/null --silent --head --fail http://${PROJNAME}.ddev.site:8983/solr/techproducts/select?q=*:*; then
        break
    else
        sleep 3 # Wait for 3 seconds before retrying
    fi
  done
  ddev exec "curl -sSf -u solr:SolrRocks -s http://solr:8983/solr/techproducts/select?q=*:* | grep numFound >/dev/null"
  # Check unauthenticated read access
  ddev exec "curl -sSf -s http://solr:8983/solr/techproducts/select?q=*:* | grep numFound >/dev/null"
  # Make sure the solr admin UI is working
  ddev exec "curl -sSf -u solr:SolrRocks -s http://solr:8983/solr/# | grep Admin >/dev/null"
  # Make sure the solr admin UI via HTTP from outside is redirected to HTTP /solr/
  curl --silent --head --fail http://${PROJNAME}.ddev.site:8983 | grep -i "location: http://${PROJNAME}.ddev.site:8983/solr/" >/dev/null
  # Make sure the solr admin UI via HTTPS from outside is redirected to HTTPS /solr/
  curl --silent --head --fail https://${PROJNAME}.ddev.site:8943 | grep -i "location: https://${PROJNAME}.ddev.site:8943/solr/" >/dev/null
  # Make sure the custom `ddev solr` command works
  ddev solr | grep COMMAND >/dev/null
  # Make sure the custom `ddev solr-zk` command works
  ddev solr-zk ls / | grep security.json >/dev/null
}

teardown() {
  set -eu -o pipefail
  cd ${TESTDIR} || ( printf "unable to cd to ${TESTDIR}\n" && exit 1 )
  ddev delete -Oy ${PROJNAME} >/dev/null 2>&1
  [ "${TESTDIR}" != "" ] && rm -rf ${TESTDIR}
}

@test "install from directory" {
  set -eu -o pipefail
  cd ${TESTDIR}
  echo "# ddev get ${DIR} with project ${PROJNAME} in ${TESTDIR} ($(pwd))" >&3
  ddev addon get ${DIR}
  ddev restart
  health_checks
}

@test "install from release" {
  set -eu -o pipefail
  cd ${TESTDIR} || ( printf "unable to cd to ${TESTDIR}\n" && exit 1 )
  echo "# ddev get ddev/ddev-solr with project ${PROJNAME} in ${TESTDIR} ($(pwd))" >&3
  ddev addon get ddev/ddev-solr
  ddev restart >/dev/null
  health_checks
}

@test "Solr version change" {
  set -eu -o pipefail
  cd "${TESTDIR}" || { printf "Unable to cd to %s\n" "${TESTDIR}" >&2; exit 1; }
  ddev addon get ${DIR}

  echo "⚡ Setting Solr base image to Solr 8.x.x" >&3
  ddev dotenv set .ddev/.env.solr --solr-base-image "solr:8"
  ddev restart

  echo "🔍 Retrieving Solr version..." >&3
  echo $(ddev solr version) >&3
  SOLR_VERSION=$(ddev solr version | grep -oE '8\.[0-9]+\.[0-9]+' || { printf "❌ Failed to get Solr version\n" >&2; exit 1; })

  echo "🔍 Retrieved Solr version: '$SOLR_VERSION'" >&3

  # Validate that the version starts with 8.x.x
  if ! [[ $SOLR_VERSION =~ ^8\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ Expected version matching '8.x.x' but got '$SOLR_VERSION'" >&2
    exit 1
  fi

  echo "✅ Solr 8.x.x version check passed!" >&3
}

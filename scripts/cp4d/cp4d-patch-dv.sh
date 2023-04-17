#!/bin/bash
SCRIPT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )

#
# Functions
#
get_logtime() {
  echo $(date "+%Y-%m-%d %H:%M:%S")
}

log() {
  LOG_TIME=$(get_logtime)
  printf "[${LOG_TIME}] ${1}\n" | tee -a ${temp_dir}/$cpd_project-patch-dv.log
}

#
# Initialization
#
CP4D_PROJECT=$1
if [ -z "${CP4D_PROJECT}" ];then
    echo "Usage: $0 <cp4d-project>"
    exit 1
fi

temp_dir=$(mktemp -d)

#
# Checks
#
# Checking for DV instance to exist in the spectified namespace
if ! command -v jq &> /dev/null;then
  echo "The jq command is required for this script. Please install first."
fi

#
# Body
#
echo "Temporary directory with logs and output files: ${temp_dir}"

# Retrieve morph job
oc get job c-db2u-dv-restore-morph -n ${CP4D_PROJECT} -o yaml > ${temp_dir}/c-db2u-dv-restore-morph.yaml

# Only allow DV patching for CP4D 4.6.4
oc get job c-db2u-dv-restore-morph -o yaml | grep -q icr.io/db2u/db2u.tools@sha256:24238a8b1c9cac0081edc7a11cc5a0ccef46dc09e8b28e98f98a8b03276b632f
if [ $? -ne 0 ];then
  echo "DV patching only allowed for CP4D 4.6.4"
fi

# Check status of morph job
MORPH_JOB_SUCCEEDED=$(oc get job c-db2u-dv-restore-morph -n ${CP4D_PROJECT} -o json | jq '.status.succeeded')

# If morph job was successful, exit
if [ ${MORPH_JOB_SUCCEEDED} != "1" ];then
  echo "Data Virtualization restore-morph job was successful, nothing to do."
  exit 0
fi

echo "Deleting restore-morph job if it exists"
oc delete job c-db2u-dv-restore-morph -n ${CP4D_PROJECT} --ignore-not-found

echo "Patching Db2 cluster"
oc rsh -n ${CP4D_PROJECT} -c db2u c-db2u-dv-db2u-0 su - db2inst1 -c 'source /mnt/blumeta0/home/db2inst1/sqllib/db2profile;db2 -v "update dbm cfg using INSTANCE_MEMORY 20"'

echo "Restarting restore-morph job"
oc apply -n ${CP4D_PROJECT} -f ${SCRIPT_DIR}/assets/c-db2u-dv-restore-morph-job.yaml

exit 0
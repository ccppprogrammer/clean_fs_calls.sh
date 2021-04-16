#!/bin/bash

[ "${FLOCKER}" != "$0" ] && exec env FLOCKER="$0" flock -en "$0" "$0" "$@" || :

PSQL_BIN="/usr/bin/psql"
FS_CLI_BIN="/usr/bin/fs_cli"
FS_CLI_API_TIMEOUT="5000"
FS_CLI_SOCKET_TIMEOUT="5000"
LOG_FILENAME="/var/log/freeswitch/clean_fs_calls.log"
PGSQL_HOSTNAME="127.0.0.1"
PGSQL_PORT="5432"
PGSQL_DBNAME="freeswitch"
PGSQL_USERNAME="fusionpbx"
PGSQL_PASSWORD="fusionpbx"
FS_HOSTS="10.10.10.10 20.20.20.20 30.30.30.30 40.40.40.40"

function log {
	echo "$(date +'%Y-%m-%d %H:%M:%S %Z') $(basename "$0")[$$]: $1" &>> ${LOG_FILENAME}
	echo "$(date +'%Y-%m-%d %H:%M:%S %Z') $(basename "$0")[$$]: $1"
}

function check_fs_call {
	FS_HOST=$1
	UUID=$2
	FS_CLI_OUTPUT=$(${FS_CLI_BIN} -H ${FS_HOST} -t ${FS_CLI_API_TIMEOUT} -T ${FS_CLI_SOCKET_TIMEOUT} -x "uuid_getvar ${UUID} uuid" 2>&1)
	if [[ "$?" -ne 0 ]]; then
		log "[ERROR] Checking UUID '${UUID}' on FS '${FS_HOST}': ERROR."
		return 0
	fi
	if [[ "${FS_CLI_OUTPUT}" != "${UUID}" ]]; then
		log "[INFO] Checking UUID '${UUID}' on FS '${FS_HOST}': NOT FOUND."
		return 1
	fi
	log "[INFO] Checking UUID '${UUID}' on FS '${FS_HOST}': FOUND."
	return 0
}

log "[INFO] BEGIN"

log "[INFO] Checking 'channels' table..."
DELETE_UUIDS=""
for UUID in $(PGPASSWORD=${PGSQL_PASSWORD} ${PSQL_BIN} -h ${PGSQL_HOSTNAME} -p ${PGSQL_PORT} -U ${PGSQL_USERNAME} -d ${PGSQL_DBNAME} -A -t -c "SELECT uuid FROM channels ORDER BY created ASC;" 2>&1); do
	if ! [[ ${UUID} =~ ^[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}$ ]]; then
		log "[ERROR] Incorrect channel UUID '${UUID}'"
		continue
	fi
	RC=1
	for FS_HOST in ${FS_HOSTS}; do
		if check_fs_call "${FS_HOST}" "${UUID}"; then
			RC=0
			break
		fi
	done
	if [[ "${RC}" -eq "1" ]]; then
		DELETE_UUIDS+=",'${UUID}'"
	fi
done

if [[ "${DELETE_UUIDS}" != "" ]]; then
	DELETE_UUIDS=${DELETE_UUIDS:1}
	PSQL_OUTPUT=$(PGPASSWORD=${PGSQL_PASSWORD} ${PSQL_BIN} -h ${PGSQL_HOSTNAME} -p ${PGSQL_PORT} -U ${PGSQL_USERNAME} -d ${PGSQL_DBNAME} -A -b -t -e -c "DELETE FROM channels WHERE uuid IN (${DELETE_UUIDS});" 2>&1)
	log "[DEBUG] ${PSQL_OUTPUT}"
fi

log "[INFO] Checking 'calls' table..."
DELETE_UUIDS=""
for UUID in $(PGPASSWORD=${PGSQL_PASSWORD} ${PSQL_BIN} -h ${PGSQL_HOSTNAME} -p ${PGSQL_PORT} -U ${PGSQL_USERNAME} -d ${PGSQL_DBNAME} -A -t -c "SELECT call_uuid, caller_uuid, callee_uuid FROM calls ORDER BY call_created ASC;" 2>&1); do
	if ! [[ ${UUID} =~ ^([a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}\|?){3}$ ]]; then
		log "[ERROR] Incorrect call UUID '${UUID}'"
		continue
	fi
	UUIDS=(${UUID//|/ })
	RC=1
	for FS_HOST in ${FS_HOSTS}; do
		if check_fs_call "${FS_HOST}" "${UUIDS[1]}"; then
			RC=0
			break
		fi
		if check_fs_call "${FS_HOST}" "${UUIDS[2]}"; then
			RC=0
			break
		fi
	done
	if [[ "${RC}" -eq "1" ]]; then
		DELETE_UUIDS+=",'${UUIDS[0]}'"
	fi
done

if [[ "${DELETE_UUIDS}" != "" ]]; then
	DELETE_UUIDS=${DELETE_UUIDS:1}
	PSQL_OUTPUT=$(PGPASSWORD=${PGSQL_PASSWORD} ${PSQL_BIN} -h ${PGSQL_HOSTNAME} -p ${PGSQL_PORT} -U ${PGSQL_USERNAME} -d ${PGSQL_DBNAME} -A -b -e -t -c "DELETE FROM calls WHERE call_uuid IN (${DELETE_UUIDS});" 2>&1)
	log "[DEBUG] ${PSQL_OUTPUT}"
fi

log "[INFO] END"
exit 0

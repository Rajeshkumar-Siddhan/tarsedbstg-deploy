#!/usr/bin/env bash
# make_subscription.sh - create <db>_subscription.yaml from the working dsq template.
#
# Usage:
#   ./make_subscription.sh                 # asks for database name(s)
set -euo pipefail

NAMESPACE="tars-edb"
CLUSTER="tarsedb"
EXTERNAL_CLUSTER="crunchy"

if [ $# -gt 0 ]; then
  DBS="$*"
else
  read -r -p "Database name(s), separated by spaces: " DBS
fi
[ -n "${DBS// /}" ] || { echo "No database name given." >&2; exit 1; }

for DB in $DBS; do
  K8S_NAME="cr2edb-$(echo "$DB" | tr '[:upper:]_' '[:lower:]-')"   # valid Kubernetes name
  PG_NAME="$DB"                                                   # same as the database name
  FILE="${DB}_subscription.yaml"

  if [ -e "$FILE" ]; then
    read -r -p "$FILE exists. Overwrite? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { echo "Skipped $FILE"; continue; }
  fi

  cat > "$FILE" <<EOF
apiVersion: postgresql.k8s.enterprisedb.io/v1
kind: Subscription
metadata:
  name: ${K8S_NAME}
  namespace: ${NAMESPACE}
spec:
  cluster:
    name: ${CLUSTER}
  dbname: ${DB}
  name: ${PG_NAME}_sub
  externalClusterName: ${EXTERNAL_CLUSTER}
  publicationName: ${PG_NAME}_pub
  publicationDBName: ${DB}
  subscriptionReclaimPolicy: delete
EOF
  echo "Created $FILE  (subscription ${PG_NAME}_sub, publication ${PG_NAME}_pub)"
done

echo
echo "Review, then apply with:  oc apply -f <db>_subscription.yaml"


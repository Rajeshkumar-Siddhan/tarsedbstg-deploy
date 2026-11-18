#!/usr/bin/env bash
# check-logins.sh - from the bastion, test user/password/database logins on
# the Crunchy (source) or EDB (target) cluster. Green = OK, red = FAILED.
#
# It runs psql INSIDE the primary pod with "oc exec", so the bastion needs no
# direct database access - only "oc" logged in with exec rights.
#
# Logins are read from a separate file (default: stg_logins.conf next to this
# script), one per line:
#     user:database:password
# The password is the LAST field, so it may itself contain ':' characters.
# Blank lines and lines starting with # are ignored.
#
# Usage:
#   ./check-logins.sh crunchy                 # source: tars-db / tarsdb
#   ./check-logins.sh edb                     # target: tars-edb / tarsedb
#   ./check-logins.sh both                    # both, one after the other

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGIN_FILE="${2:-$SCRIPT_DIR/stg_logins.conf}"

# ---- Cluster settings ---------------------------------------------------------
set_target() {
  case "$1" in
    crunchy)
      LABEL="CRUNCHY"
      NS=tars-db
      CLUSTER=tarsdb
      CONTAINER=database
      POD=$(oc get pod -n "$NS" \
              -l postgres-operator.crunchydata.com/cluster=$CLUSTER,postgres-operator.crunchydata.com/role=master \
              -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
      ;;
    edb)
      LABEL="EDB"
      NS=tars-edb
      CLUSTER=tarsedb
      CONTAINER=postgres
      POD=$(oc get cluster.postgresql.k8s.enterprisedb.io "$CLUSTER" -n "$NS" \
              -o jsonpath='{.status.currentPrimary}' 2>/dev/null)
      ;;
    *)
      echo "Usage: $0 crunchy|edb|both [logins-file]" >&2
      exit 1
      ;;
  esac
}


# ---- Run the checks against one cluster --------------------------------------
run_checks() {
  set_target "$1"
  echo -e "\e[1m=== $LABEL   namespace: $NS   cluster: $CLUSTER   pod: ${POD:-<not found>} ===\e[0m"
  if [ -z "$POD" ]; then
    echo -e "\e[31mERROR: primary pod not found - check 'oc login', namespace and cluster name\e[0m"
    echo
    return 1
  fi

  local ok=0 fail=0 line user db pass out
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"                          # tolerate Windows line endings
    case "$line" in ""|\#*) continue ;; esac      # skip blanks and comments
    user="${line%%:*}";  line="${line#*:}"
    db="${line%%:*}";    pass="${line#*:}"
    if [ -z "$user" ] || [ -z "$db" ] || [ "$db" = "$pass" ]; then
      echo -e "\e[33m[$LABEL] skipped malformed line (expected user:database:password)\e[0m"
      continue
    fi

    if out=$(oc exec -n "$NS" "$POD" -c "$CONTAINER" -- \
               env PGPASSWORD="$pass" psql -h localhost -p 5432 -U "$user" -d "$db" -w -Atc \
               "SELECT current_user || ' user connected ' || current_database() || ' database successfully';" \
               2>/dev/null </dev/null); then
      echo -e "\e[32m[$LABEL] $out\e[0m"
      ok=$((ok + 1))
    else
      echo -e "\e[31m[$LABEL] $user user FAILED to connect $db database\e[0m"
      fail=$((fail + 1))
    fi
  done < "$LOGIN_FILE"

  echo -e "[$LABEL] Summary: \e[32m$ok OK\e[0m, \e[31m$fail FAILED\e[0m"
  echo
}

# ---- Main ---------------------------------------------------------------------
[ -r "$LOGIN_FILE" ] || { echo "ERROR: logins file not found: $LOGIN_FILE" >&2; exit 1; }
PERM=$(stat -c %a "$LOGIN_FILE" 2>/dev/null)
case "$PERM" in
  600|400) ;;
  *) echo -e "\e[33mWARNING: $LOGIN_FILE has permissions $PERM - run: chmod 600 $LOGIN_FILE\e[0m" ;;
esac

oc whoami >/dev/null 2>&1 || { echo "ERROR: not logged in - run 'oc login' first" >&2; exit 1; }

case "$1" in
  both) run_checks crunchy; run_checks edb ;;
  *)    run_checks "$1" ;;
esac


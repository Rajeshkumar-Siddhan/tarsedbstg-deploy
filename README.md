Deployment manifests for EDB Postgres for Kubernetes (PG4K) in the STG environment on OpenShift v4.16.
oc apply --server-side -f  edbstg-pg4k-operator.yaml

If server-side apply reported field ownership conflicts because some fields on the existing resources were owned by a different field manager
oc apply --server-side -f  edbstg-pg4k-operator.yaml




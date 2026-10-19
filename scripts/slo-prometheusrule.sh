#!/usr/bin/env bash
# Wrap the plain Prometheus rules file (slo/call-router-slo.rules.yml, the
# source of truth that promtool checks/tests) in a PrometheusRule custom
# resource for the Prometheus Operator, and print it to stdout.
#
#   scripts/slo-prometheusrule.sh | kubectl apply -f -
set -euo pipefail
RULES="${1:-$(dirname "$0")/../slo/call-router-slo.rules.yml}"
NAMESPACE="${NAMESPACE:-voice}"

cat <<YAML
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: call-router-slo
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: call-router
    app.kubernetes.io/component: slo
spec:
YAML
# Indent every line by two spaces so `groups:` becomes `spec.groups`.
sed 's/^/  /' "$RULES"

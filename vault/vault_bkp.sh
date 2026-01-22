#/bin/sh
vault auth enable kubernetes
vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc:443" \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    issuer="https://kubernetes.default.svc.cluster.local" 
vault secrets enable -path=$NAMESPACE kv-v2
# Add policy
vault policy write ${NAMESPACE} - <<EOF
path "${NAMESPACE}/data/proxy" {
capabilities = ["read"]
}

path "${NAMESPACE}/data/proxy_env" {
capabilities = ["read"]
}

path "${NAMESPACE}/data/indexer_env" {
capabilities = ["read"]
} 
EOF
#/bin/sh
vault auth enable kubernetes
vault write auth/kubernetes/config \
    kubernetes_host=https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT 1>/dev/null
vault secrets enable -path=$NAMESPACE kv-v2 1>/dev/null
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

path "${NAMESPACE}/data/core_api_env" {
capabilities = ["read"]
}

path "${NAMESPACE}/data/core_rpc_env" {
capabilities = ["read"]
}
EOF
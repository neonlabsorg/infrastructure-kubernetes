#!/bin/bash

OPERATOR_KEYS=()
DB_MIGRATION="false"
envs=("devnet","testnet","mainnet")
vault_types=("dev","standalone","ha")
VAR_FILE="config.ini"

[ "$(which kubectl)" ] || { 
    echo "ERROR: Kubectl not installed"
    exit 1 
}
[ "$(which helm)" ] || { 
    echo "ERROR: Helm not installed"
    exit 1
}

HELP="\nUsage: $0 [OPTION]...\n
  -f, Variabels file \n
  -i, Init setup \n
  -r, Read-only mode\n  
  -S, SOLANA_URL\n
  -s, PP_SOLANA_URL\n
  -e, Set environment (\"devnet\", \"testnet\" or \"mainnet\") \n
  -p, Set postgres admin password (can be used only with -i option) \n
  -v, Set vault root token (experemental) \n  
  -m, Use this option to set migrations\n
  -k, Set keys directory \n
  -y, Assume \"yes\" as answer, run non-interactively \n
  "

## Get options
while getopts ":f:k:n:p:v:S:s:yhmird" opt; do
  case $opt in
    f) VAR_FILE=${OPTARG} ;;
    k) CLI_KEY_DIR=${OPTARG} ;;
    n) CLI_NAMESPACE=${OPTARG}`` ;;  
    p) CLI_POSTGRES_PASSWORD=${OPTARG} ;;
    v) CLI_VAULT_ROOT_TOKEN=${OPTARG} ;;    
    S) CLI_SOLANA_URL=${OPTARG} ;;
    s) CLI_PP_SOLANA_URL=${OPTARG} ;;
    y) FORCE_APPLY=1 ;;
    m) DB_MIGRATION="true" ;;  
    i) FIRST_RUN="true";DB_MIGRATION="true" ;;
    r) CLI_READONLY="true" ;;    
    d) DESTROY="true" ;;    
    h) echo -e $HELP;exit 0 ;;
    *) echo "Invalid option -$OPTARG" >&2
    exit 1
    ;;
  esac
  case $OPTARG in
    -*) echo "Option $opt needs a valid argument"
    echo -e $HELP
    exit 1
    ;;
  esac
done

[ $VAR_FILE ] || {
  echo "ERROR: Please specify parameters file. Use -f key "
  echo -e $HELP
  exit 1
}

[ -f $VAR_FILE ] || {
  echo "ERROR: ${VAR_FILE} does not exist."
  exit 1
}

## Read *.ini file
source $VAR_FILE
PROXY_ENV=$(grep -Po 'PRX_\K.*' $VAR_FILE)
INDEXER_ENV=$(grep -Po 'IDX_\K.*' $VAR_FILE)


# Set values from a command line
[ ! $CLI_NAMESPACE ] || NAMESPACE=$CLI_NAMESPACE
[ ! $CLI_POSTGRES_PASSWORD ] || POSTGRES_ADMIN_PASSWD=$CLI_POSTGRES_PASSWORD
[ ! $CLI_VAULT_ROOT_TOKEN ] || VAULT_ROOT_TOKEN=$CLI_VAULT_ROOT_TOKEN
[ ! $CLI_SOLANA_URL ] || SOLANA_URL=$CLI_SOLANA_URL
[ ! $CLI_PP_SOLANA_URL ] || PP_SOLANA_URL=$CLI_SOLANA_URL
[ ! $CLI_KEY_DIR ] || KEY_DIR=$CLI_KEY_DIR
[ ! $CLI_READONLY ] || PRX_ENABLE_SEND_TX_API="NO"
[ $VAULT_NAMESPACE ] || VAULT_NAMESPACE=$NAMESPACE
[ $MONITORING_NAMESPACE ] || MONITORING_NAMESPACE=$NAMESPACE

[ ! $DESTROY ] || {
  read -p "Uninstall neon-proxy? [yes/no]: " -n 4 -r
  [[ $REPLY != "yes" ]] || { 
    kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    kubectl delete ns $NAMESPACE
    [[ $VAULT_ENABLED != "true" ]] || [[ "$VAULT_NAMESPACE" == "$NAMESPACE" ]] || kubectl delete ns $VAULT_NAMESPACE
    [[ $MONITORING_ENABLED != "true" ]] || [[ "$MONITORING_NAMESPACE" == "$NAMESPACE" ]] || kubectl delete ns $MONITORING_NAMESPACE
    kubectl delete MutatingWebhookConfiguration vault-agent-injector-cfg
  }
  exit 0
}

## Check variables
[ $FIRST_RUN ] || kubectl get ns $NAMESPACE > /dev/null || {
  echo "Please run with -i opton"
  echo -e $HELP
  exit 1
}

[ ! -z "$SOLANA_URL" ] || {
  echo "ERROR: SOLANA_URL cannot be empty! Use -S key to set SOLANA url"
  echo -e $HELP
  exit 1
}

[ ! -z "$SOLANA_URL" ] || {
  echo "ERROR: SOLANA_URL cannot be empty! Use -S key to set SOLANA url"
  echo -e $HELP
  exit 1
}

## Check for operator keys
[[ $PRX_ENABLE_SEND_TX_API == "NO" ]] || [ "$(ls $KEY_DIR/$KEY_MASK 2>/dev/null)" ] || { 
    echo "ERROR: Keypairs not found in $KEY_DIR/"
    exit 1 
}

## Read key files to variable $OPERATOR_KEYS
[[ $PRX_ENABLE_SEND_TX_API == "NO" ]] || {
  for k in $(awk '{print}' $KEY_DIR/$KEY_MASK );do OPERATOR_KEYS+=($k);done
}

[ $POSTGRES_HOST ] && [ $POSTGRES_DB ] && [ $POSTGRES_USER ] || {
    echo -e "ERROR: Postgres credentials not specified. Check $VAR_FILE\n
    POSTGRES_HOST=$POSTGRES_HOST
    POSTGRES_DB=$POSTGRES_DB
    POSTGRES_USER=$POSTGRES_USER\n"
    exit 1 
}

[[ $vault_types[*] =~ $VAULT_TYPE ]] || {
  echo -e "ERROR: Unsupported vault type \"$VAULT_TYPE\".\nCheck $VAR_FILE ( VAULT_TYPE=...) "
  echo -e $HELP
  exit 1
}

[[ $VAULT_TYPE == "dev" ]] || [[ $FIRST_RUN ]] || ! kubectl get pods -n $VAULT_NAMESPACE  | grep vault-0 >> /dev/null || 
[[ -f "$VAULT_KEYS_FILE" && -s "$VAULT_KEYS_FILE" ]] || [[ $VAULT_ROOT_TOKEN ]] || {
  echo -e "ERROR: VAULT_ROOT_TOKEN not defined. Check if $VAULT_KEYS_FILE exist "
  exit 1
}

function installVault() {
   VAULT_CONFIG='ui = true
    listener "tcp" {
      tls_disable = 1
      address = "[::]:8200"
      cluster_address = "[::]:8201"
    }
    storage "postgresql" {
      connection_url = "postgres://'${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}'/vault?sslmode='${POSTGRES_SSL}'"
      ha_enabled = true
    }'
  
  echo "Instlling vault in $VAULT_TYPE mode"

  if [[ $VAULT_TYPE = "dev" ]]
  then
    VAULT_ROOT_TOKEN=$VAULT_DEV_TOKEN
    helm upgrade --install --atomic vault hashicorp/vault -f vault/values.yaml \
      --namespace=$VAULT_NAMESPACE  --create-namespace --history-max 3 \
      --set server.dev.devRootToken=$VAULT_ROOT_TOKEN \
      --set server.dev.enabled=true 
    kubectl wait --for=condition=ready pod vault-0 -n ${VAULT_NAMESPACE} >/dev/null
  elif [[ $VAULT_TYPE = "standalone" ]]
  then
    helm upgrade --install --atomic vault hashicorp/vault -f vault/values.yaml \
      --namespace=$VAULT_NAMESPACE  --create-namespace --history-max 3 \
      --set server.dev.enabled=false \
      --set server.standalone.enabled=true \
      --set server.ha.enabled=false \
      --set server.standalone.config="$VAULT_CONFIG" >/dev/null
    sleep 20
    kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- vault operator init -key-shares=${VAULT_KEY_SHARED} -key-threshold=${VAULT_KEY_THRESHOLD} -format=json > $VAULT_KEYS_FILE
    VAULT_UNSEAL_KEY=$(cat $VAULT_KEYS_FILE | tr { '\n' | tr , '\n' | tr } '\n' | grep unseal_keys_b64 -A 1 | awk  -F'"' 'NR==2 {print $2}')
    VAULT_ROOT_TOKEN=$(cat $VAULT_KEYS_FILE | tr { '\n' | tr , '\n' | tr } '\n' | grep root_token | awk  -F'"' '{print $4}' ) 
    
    kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- /bin/sh -c "vault operator unseal ${VAULT_UNSEAL_KEY}"  >/dev/null
  elif [[ $VAULT_TYPE = "ha" ]]
  then  
    helm upgrade --install --atomic vault hashicorp/vault -f vault/values.yaml \
      --namespace=$VAULT_NAMESPACE  --create-namespace --history-max 3 \
      --set server.dev.enabled=false \
      --set server.standalone.enabled=false \
      --set server.ha.enabled=true \
      --set server.ha.config="$VAULT_CONFIG" >/dev/null
    sleep 20
    for i in $(seq 0 $((VAULT_HA_REPLICAS-1)))
    do
      kubectl -n ${VAULT_NAMESPACE} exec vault-$i -- /bin/sh -c "vault operator unseal ${VAULT_UNSEAL_KEY}" >/dev/null
    done    
    kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- vault operator init -key-shares=${VAULT_KEY_SHARED} -key-threshold=${VAULT_KEY_THRESHOLD} -format=json > $VAULT_KEYS_FILE
    VAULT_UNSEAL_KEY=$(cat $VAULT_KEYS_FILE | tr { '\n' | tr , '\n' | tr } '\n' | grep unseal_keys_b64 -A 1 | awk  -F'"' 'NR==2 {print $2}')
    VAULT_ROOT_TOKEN=$(cat $VAULT_KEYS_FILE | tr { '\n' | tr , '\n' | tr } '\n' | grep root_token | awk  -F'"' '{print $4}' ) 
  fi

}


## Get ready for start and show values
echo -e "You can run this script with -h option\n
 ------------- Values -------------
         Namespase: $NAMESPACE
    Keys directory: ${PWD}/${KEY_DIR} -- (found ${#OPERATOR_KEYS[@]} keys)
    Proxy replicas: $PROXY_COUNT
    Keys per proxy: $KEYS_PER_PROXY
        Solana URL: $SOLANA_URL

 ------------- Modules -------------
  POSTGRES_ENABLED=$POSTGRES_ENABLED
     VAULT_ENABLED=$VAULT_ENABLED
NEON_PROXY_ENABLED=$NEON_PROXY_ENABLED
   INGRESS_ENABLED=$INGRESS_ENABLED
   \n"


## Simple check for keys and proxies values
[[ $PRX_ENABLE_SEND_TX_API == "NO" ]] || {
  k=${#OPERATOR_KEYS[@]}
  p=$PROXY_COUNT
  kp=$(( k / p ))

  [ $kp -gt 0 ] || { 
      echo "ERROR: The number of proxies cannot be more than the adjusted keys"
      exit 1 
  }
}

## Ask user if they are satisfied with the launch options
[ $FORCE_APPLY ] || {
  read -p "Continue? [y/N]" -n 1 -r
  [[ $REPLY =~ ^[Yy]$ ]] || exit 0 
}

# ## RUN
[[ $VAULT_ENABLED != "true" ]] || helm repo add hashicorp https://helm.releases.hashicorp.com   ## Vault repo
[[ $PROMETHEUS_ENABLED != "true" ]] || helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
[[ $GRAFANA_ENABLED != "true" && $LOKI_ENABLED != "true" ]] || helm repo add grafana https://grafana.github.io/helm-charts

helm repo update

# ## 0. Create namespace
kubectl create namespace $NAMESPACE 2>/dev/null

# 1. Ingress-Nginx
[[ $INGRESS_ENABLED != "true" ]] || {
  echo "Installing ingress-nginx..."
  helm upgrade --install ingress-nginx ingress-nginx --repo https://kubernetes.github.io/ingress-nginx --namespace ingress-nginx --create-namespace
}

## 2. Postgres
[[ $POSTGRES_PASSWORD ]] || {
  POSTGRES_PASSWORD=$(kubectl get secret postgres-secret --template={{.data.POSTGRES_PASSWORD}} -n $NAMESPACE 2>/dev/null | base64 --decode )
}
[[ $POSTGRES_PASSWORD ]] || {
  POSTGRES_PASSWORD=$(date +%s | sha256sum | base64 | head -c 32 ; echo)
}

[[ $POSTGRES_ADMIN_PASSWD ]] || {
  POSTGRES_ADMIN_USER=$POSTGRES_USER
  POSTGRES_ADMIN_PASSWD=$POSTGRES_PASSWORD
}
echo "Setup Postgres..."
helm upgrade --install --atomic postgres postgres/ \
  --namespace=$NAMESPACE \
  --wait-for-jobs \
  --history-max 3 \
  --set postgres.enabled=$POSTGRES_ENABLED \
  --set POSTGRES_ADMIN_USER=$POSTGRES_ADMIN_USER \
  --set POSTGRES_ADMIN_PASSWD=$POSTGRES_ADMIN_PASSWD \
  --set postgres.host=$POSTGRES_HOST \
  --set postgres.dbName=$POSTGRES_DB \
  --set postgres.user=$POSTGRES_USER \
  --set postgres.password=$POSTGRES_PASSWORD \
  --set service.port=$POSTGRES_PORT \
  --set postgres.ssl=$POSTGRES_SSL \
  --set persistence.storageClass=$POSTGRES_STORAGE_CLASS \
  --set persistence.size=$POSTGRES_STORAGE_SIZE \
  --set migrate.enabled=$DB_MIGRATION >/dev/null

[[ $POSTGRES_ENABLED == "false" ]] || kubectl -n ${NAMESPACE} wait --for=condition=ready pod postgres-0 || { 
    echo "ERROR: Postgres installation failed"
    exit 1 
}

# ## 2. Vault
if [[ $VAULT_TYPE == "dev" ]]
then
  VAULT_ROOT_TOKEN=$VAULT_DEV_TOKEN
else
  [[ $VAULT_ROOT_TOKEN ]] || VAULT_ROOT_TOKEN=$(cat $VAULT_KEYS_FILE | tr { '\n' | tr , '\n' | tr } '\n' | grep root_token | awk  -F'"' '{print $4}' )
  [[ $VAULT_UNSEAL_KEY ]] || VAULT_UNSEAL_KEY=$(cat $VAULT_KEYS_FILE | tr { '\n' | tr , '\n' | tr } '\n' | grep unseal_keys_b64 -A 1 | awk  -F'"' 'NR==2 {print $2}')
  kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- /bin/sh -c "vault operator unseal ${VAULT_UNSEAL_KEY}" 2>/dev/null  
fi

echo "Run vault installation"
[[ ! $FIRST_RUN ]] || [[ ! $VAULT_ENABLED == "true" ]] || {
  installVault
}

echo "Setup vault"

[[ ! $FIRST_RUN ]] || {
  kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- /bin/sh -c "export NAMESPACE=$NAMESPACE && vault login $VAULT_ROOT_TOKEN >/dev/null && `cat vault/vault.sh`"
  kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- /bin/sh -c "vault login $VAULT_ROOT_TOKEN >/dev/null && vault write auth/kubernetes/role/${NAMESPACE} bound_service_account_names=neon-proxy-sa bound_service_account_namespaces=${NAMESPACE} policies=neon-proxy ttl=24h"  
}

echo "Add keyes"
if [[ $PRX_ENABLE_SEND_TX_API == "YES" ]]
then
  echo "Read operator keys"
  id=0
  for((i=0; i < ${#OPERATOR_KEYS[@]}; i+=$KEYS_PER_PROXY))
  do
    part=( "${OPERATOR_KEYS[@]:i:KEYS_PER_PROXY}" )
    [ $id != 0 ] || kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- /bin/sh -c "vault login $VAULT_ROOT_TOKEN >/dev/null && vault kv put neon-proxy/proxy neon-proxy-${id}=\"${part[*]}\""
    kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- /bin/sh -c "vault login $VAULT_ROOT_TOKEN >/dev/null && vault kv patch neon-proxy/proxy neon-proxy-${id}=\"${part[*]}\""
    id=$((id+1))
  done
fi

kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- /bin/sh -c "vault login $VAULT_ROOT_TOKEN >/dev/null && echo '$PROXY_ENV' | xargs vault kv put neon-proxy/proxy_env"
kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- /bin/sh -c "vault login $VAULT_ROOT_TOKEN >/dev/null && echo '$INDEXER_ENV' | xargs vault kv put neon-proxy/indexer_env"


## 3. Proxy
[[ $NEON_PROXY_ENABLED != "true" ]] || {
  helm upgrade --install --atomic neon-proxy neon-proxy/ \
    --namespace=$NAMESPACE \
    --force \
    --history-max 3 \
    --set ingress.host=$PROXY_HOST \
    --set ingress.className=$INGRESS_CLASS \
    --set solanaUrl=$SOLANA_URL \
    --set ppsolanaUrl=$PP_SOLANA_URL \
    --set proxyCount=$PROXY_COUNT \
    --set keysPerProxy=$KEYS_PER_PROXY \
    --set image.tag=$PROXY_VER \
    --set resources.requests.cpu=$PROXY_MIN_CPU \
    --set resources.requests.memory=$PROXY_MIN_MEM \
    --set resources.limits.cpu=$PROXY_MAX_CPU \
    --set resources.limits.memory=$PROXY_MAX_MEM \
    --set onePod.enabled=$ONE_PROXY_PER_NODE \
    --set ENABLE_SEND_TX_API=$PRX_ENABLE_SEND_TX_API

    kubectl -n ${NAMESPACE} wait --for=condition=ready pod neon-proxy-0 || { 
      echo "ERROR: Proxy installation failed"
      exit 1 
    }
}

## 4. Monitoring
[[ $MONITORING_ENABLED != "true" ]] || { 
  [[ $PROMETHEUS_ENABLED != "true" ]] || {
    helm upgrade --install kube-state-metrics prometheus-community/kube-state-metrics --namespace=$MONITORING_NAMESPACE >/dev/null
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml >/dev/null
    helm upgrade --install prometheus prometheus-community/prometheus \
      -f monitoring/prometheus/values.yaml \
      --namespace=$MONITORING_NAMESPACE \
      --history-max 3 \
      --set server.persistentVolume.storageClass=$PROMETHEUS_STORAGE_CLASS \
      --set server.persistentVolume.size=$PROMETHEUS_STORAGE_SIZE \
      --set alertmanager.persistence.storageClass=$PROMETHEUS_STORAGE_CLASS \
      --set alertmanager.persistence.size=$PROMETHEUS_STORAGE_SIZE \
      --set-file extraScrapeConfigs=monitoring/prometheus/extraScrapeConfigs.yaml >/dev/null
  }

  [[ $LOKI_ENABLED != "true" ]] || {
    helm upgrade --install loki grafana/loki-stack \
      -f monitoring/loki/values.yaml \
      --namespace=$MONITORING_NAMESPACE \
      --history-max 3 >/dev/null
  }

  [[ $GRAFANA_ENABLED != "true" ]] || {
    helm upgrade --install grafana grafana/grafana \
      -f monitoring/grafana/values.yaml \
      --namespace=$MONITORING_NAMESPACE \
      --history-max 3 \
      --set persistence.storageClassName=$GRAFANA_STORAGE_CLASS \
      --set persistence.size=$GRAFANA_STORAGE_SIZE \
      --set adminUser=$GRAFANA_ADMIN_USER \
      --set adminPassword=$GRAFANA_ADMIN_PASSWD >/dev/null
  }
}

  
[ $VAULT_TYPE == "dev" ] || [ ! $FIRST_RUN ] || echo -e "\n###################\nWARNING: Please copy and keep $VAULT_KEYS_FILE in safe place!\n###################\n"
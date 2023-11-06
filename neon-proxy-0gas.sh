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

[ "$(which jq)" ] || { 
    echo "ERROR: jq not installed"
    exit 1 
}

HELP="\nUsage: $0 [OPTION]...\n
  -f, Variabels file \n
  -i, Init setup \n
  -r, Read-only mode\n  
  -S, SOLANA_URL\n
  -s, PP_SOLANA_URL\n
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
PROXY_ENV=$(grep -Po '^PRX_\K.*' $VAR_FILE)
INDEXER_ENV=$(grep -Po '^IDX_\K.*' $VAR_FILE)


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
    echo "$KEY_DIR/KEY_MASK"
    echo "Listing keys:"
    ls $KEY_DIR/$KEY_MASK
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
    VAULT_ROOT_TOKEN="$VAULT_DEV_TOKEN"
    helm upgrade --install --atomic vault hashicorp/vault -f vault/values.yaml \
      --namespace=$VAULT_NAMESPACE  --create-namespace --history-max 3 \
      --set server.dev.devRootToken=$VAULT_ROOT_TOKEN \
      --set server.dev.enabled=true 
    kubectl wait --for=condition=ready pod vault-0 -n ${VAULT_NAMESPACE} 
  elif [[ $VAULT_TYPE = "standalone" ]]
  then
    helm upgrade --install --atomic vault hashicorp/vault -f vault/values.yaml \
      --namespace=$VAULT_NAMESPACE  --create-namespace --history-max 3 \
      --set server.dev.enabled=false \
      --set server.standalone.enabled=true \
      --set server.ha.enabled=false \
      --set server.standalone.config="$VAULT_CONFIG" 1>/dev/null
    sleep 20
    kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- vault operator init -key-shares=${VAULT_KEY_SHARED} -key-threshold=${VAULT_KEY_THRESHOLD} -format=json > $VAULT_KEYS_FILE
    VAULT_UNSEAL_KEY="$(cat $VAULT_KEYS_FILE | jq -r '.unseal_keys_b64[]')"
    VAULT_ROOT_TOKEN="$(cat $VAULT_KEYS_FILE | jq -r '.root_token')"
    
    kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- /bin/sh -c "vault operator unseal ${VAULT_UNSEAL_KEY}" 1>/dev/null
  elif [[ $VAULT_TYPE = "ha" ]]
  then  
    helm upgrade --install --atomic vault hashicorp/vault -f vault/values.yaml \
      --namespace=$VAULT_NAMESPACE  --create-namespace --history-max 3 \
      --set server.dev.enabled=false \
      --set server.standalone.enabled=false \
      --set server.ha.enabled=true \
      --set server.ha.config="$VAULT_CONFIG" 1>/dev/null
    sleep 20
    for i in $(seq 0 $((VAULT_HA_REPLICAS-1)))
    do
      kubectl -n ${VAULT_NAMESPACE} exec vault-$i -- /bin/sh -c "vault operator unseal ${VAULT_UNSEAL_KEY}" 1>/dev/null
    done    
    kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- vault operator init -key-shares=${VAULT_KEY_SHARED} -key-threshold=${VAULT_KEY_THRESHOLD} -format=json > $VAULT_KEYS_FILE
    VAULT_UNSEAL_KEY="$(cat $VAULT_KEYS_FILE | jq -r '.unseal_keys_b64[]')"
    VAULT_ROOT_TOKEN="$(cat $VAULT_KEYS_FILE | jq -r '.root_token')"
  fi

}


## Get ready for start and show values
echo -e "You can run this script with -h option\n
 ------------- Values -------------
         Namespase: $NAMESPACE
    Keys directory: ${KEY_DIR} -- (found ${#OPERATOR_KEYS[@]} keys)
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
[[ $INGRESS_ENABLED != "true" ]] || helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
[[ $VAULT_ENABLED != "true" ]] || helm repo add hashicorp https://helm.releases.hashicorp.com   ## Vault repo
[[ $PROMETHEUS_ENABLED != "true" ]] || helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
[[ $GRAFANA_ENABLED != "true" && $LOKI_ENABLED != "true" ]] || helm repo add grafana https://grafana.github.io/helm-charts

helm repo update

# ## 0. Create namespace
kubectl create namespace $NAMESPACE 2>/dev/null

# 1. Ingress-Nginx
[[ $INGRESS_ENABLED != "true" ]] || {
  echo "Installing ingress-nginx..."
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --history-max 3 \
  --set controller.service.type=$INGRESS_SERVICE_TYPE \
  --set controller.service.nodePorts.http=32080 \
  --set controller.service.nodePorts.https=32443  1>/dev/null
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
echo "Installing Postgres..."
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
  --set migrate.enabled=$DB_MIGRATION 1>/dev/null

[[ $POSTGRES_ENABLED == "false" ]] || kubectl -n ${NAMESPACE} wait --for=condition=ready pod postgres-0 || { 
    echo "ERROR: Postgres installation failed"
    exit 1 
}

# ## 2. Vault
echo "Setup secrets..."
[[ ! $FIRST_RUN ]] || [[  $VAULT_ENABLED != "true" ]] || {
  [[ ! -f "$VAULT_KEYS_FILE" ]] || { 
    echo "Found $VAULT_KEYS_FILE -- Backuping..." 
    cp $VAULT_KEYS_FILE ${VAULT_KEYS_FILE}_bkp
  }
  [[ $(kubectl -n ${VAULT_NAMESPACE} get po vault-0 2>/dev/null)  ]] || {
    echo "Run Vault installation"
    installVault
  }
}

echo "Check vault token"
[[ $VAULT_TYPE != "dev" ]] || VAULT_ROOT_TOKEN=$VAULT_DEV_TOKEN
[[ $VAULT_TYPE == "dev" ]] || {
  [[ $VAULT_ROOT_TOKEN ]] || [[ ! -f "$VAULT_KEYS_FILE" ]] || VAULT_ROOT_TOKEN="$(cat $VAULT_KEYS_FILE | jq -r '.root_token')"
  [[ $VAULT_UNSEAL_KEY ]] || [[ ! -f "$VAULT_KEYS_FILE" ]] || {
    VAULT_UNSEAL_KEY="$(cat $VAULT_KEYS_FILE | jq -r '.unseal_keys_b64[]')"
    [[ $VAULT_UNSEAL_KEY ]] || echo -e "\n###################\nWARNING: VAULT_UNSEAL_KEY no foud! Please make sure Vault is available\n###################\n"
    kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- /bin/sh -c "vault operator unseal ${VAULT_UNSEAL_KEY}" 
  }
  [[ $VAULT_ROOT_TOKEN ]] || {
    echo "ERROR: No VAULT_ROOT_TOKEN found"
    exit 1
  }    
}

kubectl -n ${VAULT_NAMESPACE} wait --for=condition=ready pod vault-0 || {
    echo "ERROR: Vault installation failed"
    exit 1   
}

kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- /bin/sh -c "vault login $VAULT_ROOT_TOKEN" 1>/dev/null

[[ ! $FIRST_RUN ]] || {
  echo "Setup vault"
  kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- /bin/sh -c "export NAMESPACE=$NAMESPACE && `cat vault/vault.sh`" 1>/dev/null
  kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- /bin/sh -c "vault write auth/kubernetes/role/${NAMESPACE} bound_service_account_names=neon-proxy-sa bound_service_account_namespaces=${NAMESPACE} policies=neon-proxy ttl=24h" 1>/dev/null
}

if [[ $PRX_ENABLE_SEND_TX_API == "YES" ]]
then
  echo "Read operator keys"
  id=0
  for((i=0; i < ${#OPERATOR_KEYS[@]}; i+=$KEYS_PER_PROXY))
  do
    echo "Add keys for neon-proxy-${id}"
    part=( "${OPERATOR_KEYS[@]:i:KEYS_PER_PROXY}" )
    [ $id != 0 ] || kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- /bin/sh -c "vault kv put neon-proxy/proxy neon-proxy-${id}=\"${part[*]}\"" 1>/dev/null
    kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- /bin/sh -c "vault kv patch neon-proxy/proxy neon-proxy-${id}=\"${part[*]}\"" 1>/dev/null
    id=$((id+1))
  done
fi

echo "Setup proxy env variables"
kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- /bin/sh -c "echo '$PROXY_ENV' | xargs vault kv put neon-proxy/proxy_env" 1>/dev/null
echo "Setup indexer env variables"
kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- /bin/sh -c "echo '$INDEXER_ENV' | xargs vault kv put neon-proxy/indexer_env" 1>/dev/null

## 3. Proxy
[[ $NEON_PROXY_ENABLED != "true" ]] || {
  echo "Installing neon-proxy..."
  helm upgrade --install --atomic neon-proxy neon-proxy/ \
    --namespace=$NAMESPACE \
    --force \
    --history-max 3 \
    --set solanaUrl=$SOLANA_URL \
    --set evm_loader=$EVM_LOADER \
    --set commit_level=$COMMIT_LEVEL \
    --set perm_account_limit=$PERM_ACCOUNT_LIMIT \
    --set proxyCount=$PROXY_COUNT \
    --set keysPerProxy=$KEYS_PER_PROXY \
    --set image.tag=$PROXY_VER \
    --set resources.requests.cpu=$PROXY_MIN_CPU \
    --set resources.requests.memory=$PROXY_MIN_MEM \
    --set resources.limits.cpu=$PROXY_MAX_CPU \
    --set resources.limits.memory=$PROXY_MAX_MEM \
    --set onePod.enabled=$ONE_PROXY_PER_NODE \
    --set-file indexer.indexerKey=$KEY_DIR/$INDEXER_KEY_FILE \
    --set ENABLE_SEND_TX_API=$PRX_ENABLE_SEND_TX_API \
    --set minimal_gas_price=$MINIMAL_GAS_PRICE \
    --set gas_indexer_erc20_wrapper_whitelist=ANY \
    --set gas_start_slot="CONTINUE"
    #--set ppsolanaUrl=$PP_SOLANA_URL \



    kubectl -n ${NAMESPACE} wait --for=condition=ready pod neon-proxy-0 --timeout=1m || { 
      echo "ERROR: Proxy installation failed"
      exit 1
    }

    [[ $TRACER_ENABLED != "true" ]] || {
    echo "Installing Trace-api..."
    kubectl apply -f tracer/tracer.yaml
  }
}

## 4. Monitoring
[[ $MONITORING_ENABLED != "true" ]] || { 
  [[ $PROMETHEUS_ENABLED != "true" ]] || {
    echo "Installing prometheus"
    helm upgrade --install kube-state-metrics prometheus-community/kube-state-metrics --namespace=$MONITORING_NAMESPACE 1>/dev/null
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml 1>/dev/null
    helm upgrade --install prometheus prometheus-community/prometheus \
      -f monitoring/prometheus/values.yaml \
      --namespace=$MONITORING_NAMESPACE \
      --history-max 3 \
      --set server.persistentVolume.storageClass=$PROMETHEUS_STORAGE_CLASS \
      --set server.persistentVolume.size=$PROMETHEUS_STORAGE_SIZE \
      --set alertmanager.persistence.storageClass=$PROMETHEUS_STORAGE_CLASS \
      --set alertmanager.persistence.size=$PROMETHEUS_STORAGE_SIZE \
      --set server.ingress.host=$PROXY_HOST \
      --set server.ingress.className=$INGRESS_CLASS \
      --set server.ingress.path=$PROMETHEUS_INGRESS_PATH \
      --set-file extraScrapeConfigs=monitoring/prometheus/extraScrapeConfigs.yaml 1>/dev/null
  }

  [[ $LOKI_ENABLED != "true" ]] || {
    echo "Installing Loki..."
    helm upgrade --install loki grafana/loki-stack \
      -f monitoring/loki/values.yaml \
      --namespace=$MONITORING_NAMESPACE \
      --history-max 3 1>/dev/null
  }

  [[ $GRAFANA_ENABLED != "true" ]] || {
    echo "Installing Grafana..."
    helm upgrade --install grafana grafana/grafana \
      -f monitoring/grafana/values.yaml \
      --namespace=$MONITORING_NAMESPACE \
      --history-max 3 \
      --set persistence.storageClassName=$GRAFANA_STORAGE_CLASS \
      --set persistence.size=$GRAFANA_STORAGE_SIZE \
      --set adminUser=$GRAFANA_ADMIN_USER \
      --set ingress.enabled=$GRAFANA_INGRESS_ENABLED \
      --set ingress.host=$PROXY_HOST \
      --set ingress.className=$INGRESS_CLASS \
      --set ingress.path=$GRAFANA_INGRESS_PATH \
      --set adminPassword=$GRAFANA_ADMIN_PASSWD 1>/dev/null
  }
}

  
[ $VAULT_TYPE == "dev" ] || [ ! $FIRST_RUN ] || echo -e "\n###################\nWARNING: Please copy and keep $VAULT_KEYS_FILE in safe place!\n###################\n"
    
    kubectl apply -f tracer/0-proxy-service.yaml
    kubectl apply -f tracer/0-tracer-db-deployment.yaml
    kubectl apply -f tracer/0-tracer-db-service.yaml
    kubectl apply -f tracer/1-neon-tracer-service.yaml
    kubectl apply -f tracer/2-neon-rpc-deployment.yaml
    kubectl apply -f tracer/2-neon-rpc-service.yaml

    ###CREATING CRON TO CHECK VERSION AND UPGRADE/ROLLOUT
    #kubectl apply -f neon-proxy/update/cron.yaml

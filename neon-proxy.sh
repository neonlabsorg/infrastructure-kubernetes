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
  -e, Set environment (\"devnet\", \"testnet\" or \"mainnet\") \n
  -d, Postgres password\n
  -m, Use this option to set migrations\n
  -k, operator kyes dir \n
  -y, Assume \"yes\" as answer, run non-interactively \n
  "

## Get options
while getopts ":f:k:n:d:S:s:e:yhmir" opt; do
  case $opt in
    f) VAR_FILE=${OPTARG} ;;
    k) CLI_KEY_DIR=${OPTARG} ;;
    n) CLI_NAMESPACE=${OPTARG}`` ;;  
    d) CLI_POSTGRES_PASSWORD=${OPTARG} ;;
    S) CLI_SOLANA_URL=${OPTARG} ;;
    s) CLI_PP_SOLANA_URL=${OPTARG} ;;
    e) CLI_P_ENV=${OPTARG} ;;
    y) FORCE_APPLY=1 ;;
    m) DB_MIGRATION="true" ;;  
    i) FIRST_RUN="true";DB_MIGRATION="true" ;;
    r) CLI_READONLY="true" ;;
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
ENABLE_SEND_TX_API="YES"

# Set values from a command line
[ ! $CLI_NAMESPACE ] || NAMESPACE=$CLI_NAMESPACE
[ ! $CLI_POSTGRES_PASSWORD ] || POSTGRES_ADMIN_PASSWD=$CLI_POSTGRES_PASSWORD
[ ! $CLI_SOLANA_URL ] || SOLANA_URL=$CLI_SOLANA_URL
[ ! $CLI_PP_SOLANA_URL ] || PP_SOLANA_URL=$CLI_SOLANA_URL
[ ! $CLI_P_ENV ] || P_ENV=$CLI_P_ENV
[ ! $CLI_KEY_DIR ] || KEY_DIR=$CLI_KEY_DIR
[ ! $CLI_READONLY ] || ENABLE_SEND_TX_API="NO"

## Check variables

[ ! -z $P_ENV ] || {
  echo "ERROR: Environment don't set. Check $VAR_FILE (P_ENV=...) or set with -e option "
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
[ "$(ls $KEY_DIR/$KEY_MASK 2>/dev/null)" ] || { 
    echo "ERROR: Keypairs not found in $KEY_DIR/"
    exit 1 
}

## Read key files to variable $OPERATOR_KEYS
for k in $(awk '{print}' $KEY_DIR/$KEY_MASK );do OPERATOR_KEYS+=($k);done

[ $POSTGRES_HOST ] && [ $POSTGRES_DB ] && [ $POSTGRES_USER ] || {
    echo -e "ERROR: Postgres credentials not specified. Check $VAR_FILE\n
    POSTGRES_HOST=$POSTGRES_HOST
    POSTGRES_DB=$POSTGRES_DB
    POSTGRES_USER=$POSTGRES_USER\n"
    exit 1 
}

[[ $envs[*] =~ $P_ENV ]] || {
  echo -e "ERROR: Unsupported environment value \"$P_ENV\".\nCheck $VAR_FILE ( P_ENV=...) or set with -e option "
  echo -e $HELP
  exit 1
}

[[ $vault_types[*] =~ $VAULT_TYPE ]] || {
  echo -e "ERROR: Unsupported vault type \"$VAULT_TYPE\".\nCheck $VAR_FILE ( VAULT_TYPE=...) "
  echo -e $HELP
  exit 1
}

[[ $P_ENV = "devnet" ]] || [[ $VAULT_KEY_SHARED && $VAULT_KEY_THRESHOLD ]] || {
    echo -e "ERROR: Vault can't be run in \"$P_ENV\" environment without options. Check $VAR_FILE:\n
    VAULT_KEY_SHARED=$VAULT_KEY_SHARED
    VAULT_KEY_THRESHOLD=$VAULT_KEY_THRESHOLD\n"
    exit 1 
}

[[ $P_ENV = "devnet" ]] || [[ -f "$VAULT_KEYS_FILE" && -s "$VAULT_KEYS_FILE" ]] || {
  echo -e "\n###################\n"
  echo -e "WARNING: $VAULT_KEYS_FILE not found or file is empty! Vault will try to init storage!"
  echo -e "\n###################\n"
  sleep 5
}

function installVault() {
  [[ $VAULT_NAMESPACE ]] || {
    VAULT_NAMESPACE=$NAMESPACE
  }

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
      --namespace=$VAULT_NAMESPACE  --create-namespace \
      --set server.dev.devRootToken=$VAULT_ROOT_TOKEN \
      --set server.dev.enabled=true 
    kubectl wait --for=condition=ready pod vault-0 -n ${VAULT_NAMESPACE} 
  elif [[ $VAULT_TYPE = "standalone" ]]
  then
    helm upgrade --install --atomic vault hashicorp/vault -f vault/values.yaml \
      --namespace=$VAULT_NAMESPACE  --create-namespace \
      --set server.dev.enabled=false \
      --set server.standalone.enabled=true \
      --set server.ha.enabled=false \
      --set server.standalone.config="$VAULT_CONFIG"
    sleep 20
    kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- vault operator init -key-shares=${VAULT_KEY_SHARED} -key-threshold=${VAULT_KEY_THRESHOLD} -format=json > $VAULT_KEYS_FILE
    VAULT_UNSEAL_KEY=$(cat $VAULT_KEYS_FILE | jq -r ".unseal_keys_b64[]")
    VAULT_ROOT_TOKEN=$(cat $VAULT_KEYS_FILE | jq -r ".root_token")
    kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- /bin/sh -c "vault operator unseal ${VAULT_UNSEAL_KEY}"  
  elif [[ $VAULT_TYPE = "ha" ]]
  then  
    helm upgrade --install --atomic vault hashicorp/vault -f vault/values.yaml \
      --namespace=$VAULT_NAMESPACE  --create-namespace \
      --set server.dev.enabled=false \
      --set server.standalone.enabled=false \
      --set server.ha.enabled=true \
      --set server.ha.config="$VAULT_CONFIG"
    sleep 20
    for i in $(seq 0 $((VAULT_HA_REPLICAS-1)))
    do
      kubectl -n ${VAULT_NAMESPACE} exec vault-$i -- /bin/sh -c "vault operator unseal ${VAULT_UNSEAL_KEY}"
    done    
    kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- vault operator init -key-shares=${VAULT_KEY_SHARED} -key-threshold=${VAULT_KEY_THRESHOLD} -format=json > $VAULT_KEYS_FILE
    VAULT_UNSEAL_KEY=$(cat $VAULT_KEYS_FILE | jq -r ".unseal_keys_b64[]")
    VAULT_ROOT_TOKEN=$(cat $VAULT_KEYS_FILE | jq -r ".root_token")    
    #VAULT_UNSEAL_KEY=$(cat $VAULT_KEYS_FILE | tr { '\n' | tr , '\n' | tr } '\n' | grep unseal_keys_b64 -A 1 | awk  -F'"' 'NR==2 {print $2}')
    #VAULT_ROOT_TOKEN=$(cat $VAULT_KEYS_FILE | tr { '\n' | tr , '\n' | tr } '\n' | grep "root_token" | awk  -F'"' '{print $4}' ) 
  fi

}


## Get ready for start and show values
echo  "You can run this script with -h option" $'\n'
echo "SOLANA_URL: $SOLANA_URL"
echo "Environment: $P_ENV"
echo "Use namespase: $NAMESPACE"
echo "Read keys form: ${KEY_DIR}/ -- (found ${#OPERATOR_KEYS[@]} keys)"
echo "Proxy replicas: $PROXY_COUNT"
echo "Keys per proxy replica: $KEYS_PER_PROXY"
echo "

  POSTGRES_ENABLED=$POSTGRES_ENABLED
     VAULT_ENABLED=$VAULT_ENABLED
NEON_PROXY_ENABLED=$NEON_PROXY_ENABLED"
echo

## Simple check for keys and proxies values
k=${#OPERATOR_KEYS[@]}
p=$PROXY_COUNT
kp=$(( k / p ))

[ $kp -gt 0 ] || { 
    echo "ERROR: The number of proxies cannot be more than the adjusted keys"
    exit 1 
}

## Ask user if they are satisfied with the launch options
[ $FORCE_APPLY ] || {
  read -p "Continue? [y/N]" -n 1 -r
  [[ $REPLY =~ ^[Yy]$ ]] || { 
    exit 0 
    }
}

# ## RUN
helm repo add hashicorp https://helm.releases.hashicorp.com   ## Vault repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# ## 0. Create namespace
kubectl create namespace $NAMESPACE 2>/dev/null

# 1. Ingress-Nginx
[[ $INGRESS_ENABLED = "false" ]] || {
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

case $POSTGRES_STORAGE_CLASS in
  "efs") DRIVER_NAME="efs.csi.aws.com";;
  "scw-bssd") DRIVER_NAME="csi.scaleway.com";;
esac


helm upgrade --install --atomic postgres postgres/ \
  --namespace=$NAMESPACE \
  --set postgres.enabled=$POSTGRES_ENABLED \
  --set POSTGRES_ADMIN_USER=$POSTGRES_ADMIN_USER \
  --set POSTGRES_ADMIN_PASSWD=$POSTGRES_ADMIN_PASSWD \
  --set postgres.host=$POSTGRES_HOST \
  --set postgres.dbName=$POSTGRES_DB \
  --set postgres.user=$POSTGRES_USER \
  --set postgres.password=$POSTGRES_PASSWORD \
  --set service.port=$POSTGRES_PORT \
  --set postgres.ssl=$POSTGRES_SSL \
  --set persistence.storageClassName=$POSTGRES_STORAGE_CLASS \
  --set efsDriver.name=$DRIVER_NAME \
  --set efsDriver.efsId=$EFS_ID \
  --set persistence.hostPath=$POSTGRES_STORAGE_DIR \
  --set persistence.size=$POSTGRES_STORAGE_SIZE \
  --set migrate.enabled=$DB_MIGRATION \
  --set environment=$P_ENV

[[ $POSTGRES_ENABLED = "false" ]] || kubectl -n ${NAMESPACE} wait --for=condition=ready pod postgres-0 || { 
    echo "ERROR: Postgres installation failed"
    exit 1 
}

# ## 2. Vault
echo "Read operator keys"
SECRET=()
id=0
for((i=0; i < ${#OPERATOR_KEYS[@]}; i+=$KEYS_PER_PROXY))
do
  part=( "${OPERATOR_KEYS[@]:i:KEYS_PER_PROXY}" )
  SECRET+=$(echo -n neon-proxy-${id}=\"${part[*]}\"; echo -n " " )
  id=$((id+1))
done

if [[ $VAULT_TYPE = "dev" ]]
then
  VAULT_ROOT_TOKEN=$VAULT_DEV_TOKEN
else
  VAULT_ROOT_TOKEN=$(cat $VAULT_KEYS_FILE | jq -r ".root_token")
fi

echo "Run vault installation"
[[ ! $VAULT_ENABLED = "true" && ! $FIRST_RUN ]] || {
  installVault
}

echo "Setup vault install"

[[ ! $FIRST_RUN ]] || {
  kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- /bin/sh -c "export NAMESPACE=$NAMESPACE && vault login $VAULT_ROOT_TOKEN && `cat vault/vault.sh`"
  kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- /bin/sh -c "vault login $VAULT_ROOT_TOKEN && vault write auth/kubernetes/role/${NAMESPACE} bound_service_account_names=neon-proxy-sa bound_service_account_namespaces=${NAMESPACE} policies=neon-proxy ttl=24h"  
}

echo "Add keyes"

kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- /bin/sh -c "vault login $VAULT_ROOT_TOKEN && echo '$SECRET' | xargs vault kv put neon-proxy/proxy"


## 3. Proxy
[[ $NEON_PROXY_ENABLED = "false" ]] || {
  helm upgrade --install --atomic neon-proxy neon-proxy/ \
    --namespace=$NAMESPACE \
    --set ingress.host=$PROXY_HOST \
    --set ingress.className=$INGRESS_CLASS \
    --set solanaUrl=$SOLANA_URL \
    --set ppsolanaUrl=$PP_SOLANA_URL \
    --set proxyCount=$PROXY_COUNT \
    --set keysPerProxy=$KEYS_PER_PROXY \
    --set image.tag=$PROXY_VER \
    --set FAUCET_URL=$FAUCET_URL \
    --set PROXY_URL=$PROXY_URL \
    --set LOG_NEON_CLI_DEBUG=$LOG_FULL_OBJECT_INFO \
    --set FUZZING_BLOCKHASH=$FUZZING_BLOCKHASH \
    --set LOG_FULL_OBJECT_INFO=$LOG_FULL_OBJECT_INFO \
    --set CONFIG=$CONFIG \
    --set PYTH_MAPPING_ACCOUNT=$PYTH_MAPPING_ACCOUNT \
    --set MIN_OPERATOR_BALANCE_TO_WARN=$MIN_OPERATOR_BALANCE_TO_WARN \
    --set MIN_OPERATOR_BALANCE_TO_ERR=$MIN_OPERATOR_BALANCE_TO_ERR \
    --set MINIMAL_GAS_PRICE=$MINIMAL_GAS_PRICE \
    --set ENABLE_PRIVATE_API=$ENABLE_PRIVATE_API \
    --set ENABLE_SEND_TX_API=$ENABLE_SEND_TX_API \
    --set ALLOW_UNDERPRICED_TX_WITHOUT_CHAINID=$ALLOW_UNDERPRICED_TX_WITHOUT_CHAINID \
    --set EVM_LOADER=$EVM_LOADER \
    --set NEON_CLI_TIMEOUT=$NEON_CLI_TIMEOUT \
    --set CONFIRM_TIMEOUT=$CONFIRM_TIMEOUT \
    --set indexer.GATHER_STATISTICS=$IDX_GATHER_STATISTICS \
    --set indexer.LOG_FULL_OBJECT_INFO=$IDX_LOG_FULL_OBJECT_INFO \
    --set environment=$P_ENV
}


[ $VAULT_TYPE = "dev" ] || {
  echo -e "\n###################\n"
  echo -e "WARNING: Please copy and keep $VAULT_KEYS_FILE in safe place!"
  echo -e "\n###################\n"
}

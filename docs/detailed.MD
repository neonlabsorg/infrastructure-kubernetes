# Running neon-proxy with Kubernetes (operators)
## _Setup covers install steps for k8s_

[![Kubernetes](https://www.vectorlogo.zone/logos/kubernetes/kubernetes-ar21.svg)](https://kubernetes.io)


**-> Running neon-proxy (operator) with Kubernetes**
- Installation and Requirements:

    Our **operator** are based on three kind of **kubernetes providers**:
        1. **Local** development such as microk8s, kind, minikube, k3s.
        2. **GKE** - Google Kubernetes Engine based on GCP (Google Cloud Platform)
        3. **EKS** - Elastic Kubernetes Service based on AWS (Amazon Web Services)
     
- Hardware recommendations:

		For production: 
        
            - At least two VMs/Servers with Intel Processor x86_64 with:
            - 16vcpu, 32GB of RAM (each server)
            - 1TB of storage
        
		For development/local setup: 
        
            - Intel Processor x86_64 with:
            - 8vcpu, 16GB of RAM (each server)
            - 128GB of storage


2. In order to install it, you should give access to **github repository**:
  [https://github.com/neonlabsorg/infrastructure-kubernetes](https://github.com/neonlabsorg/infrastructure-kubernetes) 
 
    There are kubernetes install script for local development and work as operators `neon-proxy.sh`, and there it will deploy:

   a. `neon-proxy` namespace.
   
   b. `proxy-svc` Proxy service.
   
   c. `indexersvc` Indexer service.
   
   d. For local tests: `airdropper` and `faucet` services (devnet and testnet).
   
   e. Prometheus (used to gather application metrics from proxy and indexer services).
   
   f. Loki (tool for log collection from all applications inside the cluster).
   
   g. Grafana (Visual graph tool in order to create monitoring metrics from platform).

  For database, we have two options:
  
   - Postgresql database inside kubernetes as a pod.  `POSTGRES_ENABLED="true" ` 
   
   - Use your external database from the kubernetes cluster to your own PostgreSQL database such as RDS(AWS), CloudSQL(GCP) or other bare metal or Virtual Machine based install. (Recommended for production)   `POSTGRES_ENABLED="false" ` and then set the following:
   
   - `POSTGRES_HOST="postgres" `
   - `POSTGRES_DB="neon-db"`
   - `POSTGRES_USER="neon-proxy"`
   
3. **Install**
- Copy config.ini.sample to config.ini and check the following variables:
      
 - In next session you can just disable or enable some features like:
   
   `INGRESS_ENABLED="false" `
       (it disables the ingress for the cluster, valid options are true or false).

   `POSTGRES_ENABLED="true" `
    If you want to create local postgresql pods, it should be "true", as noticed in last session, if you have RDS, CloudSQL or your own external database, please set it as "false".

   `VAULT_ENABLED="true" `
       For hashicorp vault container inside your cluster as a service.
   
   `NEON_PROXY_ENABLED="true"`
   This section enable neonlabs proxy container.
  
   ***NAMESPACE*** section:
       `NAMESPACE='neon-proxy'`
        This is a namespace that proxy will be deployed inside your cluster, if you want to change it, just modify this value for your choice.

   ***Operator*** keys and path:
   
    `KEY_DIR='operator-keypairs'`
    
    `KEY_MASK="id*.json"`

		 KEY_DIR is a path in your device that has neon-labs operator keys, whitin in your current directory.
		 
         KEY_MASK is the regular expression that finds your json files.
	 
****Read-only mode****
	 
	 This install process has an option called (read-only mode), in this scenario, you don't need operator keys.
	 Just use ( -r ) parameter on install process.

   ***SOLANA*** section:
   
   There is an option to use in the install script -S option to set this variable
    
    `SOLANA_URL=`

Specifies a Solana URL RPC endpoint that a proxy is connecting to.
        
The public solana endpoints have limits for requests per minute (60).

The best scenario is to use an own solana node inside your infrastructure.

Here you need to set your ***neon_evm*** host or;

   | CONFIG | SOLANA_URL | NEON_CLIT_TIMEOUT | CANCEL_TIMEOUT | 
   | --- | --- | --- | --- |
   | devnet | https://api.devnet.solana.com/ | 10 | 60 (slot) | 
   | testnet | https://api.testnet.solana.com/ | 15 | 60 (slot) | 
   | local | http://localhost:8899 | 1 | 10 (slot) | 

   ***PP_SOLANA_URL***
    For standalone solana we need to use different values (SOLANA_URL and PP_SOLANA_URL) for these env vars.
    For testnet/devnet/mainnet-beta we can use same values for this env vars (SOLANA_URL and PP_SOLANA_URL)

   If disabled will be the same as `$SOLANA_URL`
      
`      PP_SOLANA_URL=`

   ***PROXY:***
    Set proxy/docker image version here.
`PROXY_VER="v0.13.x"` 

    PROXY_COUNT is the number of pods that you need to host in your cluster namespace.
`PROXY_COUNT="v0.13.x"` 

    KEYS_PER_PROXY is the number of keys that each pod will use from hashicorp vault.
`KEYS_PER_PROXY=20`

    If you want to use ingress to serve your own DNS name inside the cluster, set this PROXY_HOST value.
`PROXY_HOST="neom="proxy.example.com"`

   ***PROXY ENVS***
   
    PRX_FAUCET_URL="http://faucet-test:3344"
Internal name inside your namespace that calls faucet #application (only local development and devnet).

    PRX_PROXY_URL="http://neon-proxy:9090/solana"
Address of local neon-proxy that resides inside in your #namespace service.

    PRX_LOG_NEON_CLI_DEBUG="YES"
For debug purposes this value print in the log information #from neon cli.

    PRX_FUZZING_BLOCKHASH="NO"
    
    PRX_LOG_FULL_OBJECT_INFO="YES"
    
    PRX_CONFIG="CI"

    PRX_PYTH_MAPPING_ACCOUNT=""
    
    This setting uses a pyth network account in order to get solana current currency.
    
    PRX_MIN_OPERATOR_BALANCE_TO_WARN="4565760000"
    
    PRX_MIN_OPERATOR_BALANCE_TO_ERR="913152000"


    PRX_MINIMAL_GAS_PRICE="1"
Lowest fee for gas price.

    PRX_ENABLE_PRIVATE_API="YES"
Allow use of private apis.

    PRX_ALLOW_UNDERPRICED_TX_WITHOUT_CHAINID="YES"


    PRX_EVM_LOADER=""
Set defaults the following values for the variable PRX_EVM_LOADER (for local install only) :
    
| CONFIG | EVM_LOADER | 
| --- | --- |
| devnet | eeLSJgWzzxrqKv1UxtRVVH8FX3qCQWUs9QuAjJpETGU | 
| testnet | eeLSJgWzzxrqKv1UxtRVVH8FX3qCQWUs9QuAjJpETGU | 
| local | n/a | 


    PRX_NEON_CLI_TIMEOUT="10"
Set timeout from proxy to solana connectivity.

    PRX_CONFIRM_TIMEOUT="15"
Confirms timeout from proxy to solana connectivity.


   ***INDEXER*** ENVS
   
   	IDX_GATHER_STATISTICS="YES"
	
        IDX_LOG_FULL_OBJECT_INFO="NO"


4. ***PostgreSQL*** Database

      Database options offer two methods of connectivity:
      
      Local - Where your own cluster initiates an postgresql database as a cluster pod (statefulset) with a local storage.
      
      Remote - If your infrastructure already has postgresql database (RDS, CloudSQL etc) just set in the beginning of this file POSTGRES_ENABLED="false", and then, use your remote database as below;
      

`POSTGRES_HOST="postgres" `
if you use your database outside of the cluster, just replace it by hostname/ip of your database.

`POSTGRES_DB="neon-db"`
Schema name that will generate inside your database

`POSTGRES_USER="neon-proxy"`
Your database username

`POSTGRES_PORT="5432"`
Your database TCP port, default is 5432.

`POSTGRES_STORAGE_CLASS="host"`
Set as a 'host' if you set up your database in your local cluster.
Set as 'efs' if you already have an EFS (Elastic file system) storage that will keep your database files.

`If disabled, the password will be randomly generated.`

`It can be set with -d parameter: install_neon_proxy.sh -d some-password ...`

`Use this command to show password:`

`kubectl get secret postgres-secret #--template={{.data.POSTGRES_PASSWORD}} -n #neon-proxy | base64 --decode`

`POSTGRES_PASSWORD=<some password>`

The database password  can be set by using -d using install shell script, if you prefer this as a security standard and let the script generate a new password randomly, get your password from kubernetes secret object as a kubectl command above.
If you want to choose your password, please set `POSTGRES_PASSWORD`.

**Disclaimer**: For production environments, we recommend external PostgreSQL databases such as AWS RDS, GCP CLoudSQL or your database install.

 5.  ***VAULT***
     This setup includes a hashicorp vault that will store your private keys in a secure standard.
    `VAULT_TYPE="dev"`
    
This environment has 3 different options; `dev, standalone or ha`

    dev - for local install/development purposes.
    standalone - if you only want one container
    ha - if you want some high availability

The first install generates ***vault-keys.json*** file containing values for `VAULT_ROOT_TOKEN` and `VAULT_UNSEAL_KEY`.

    You should keep this file in a safe place!

For further installs/updates, please set this field and uncomment from previewed json file generated on first setup
`#VAULT_ROOT_TOKEN=`

`#VAULT_UNSEAL_KEY=`

DEV_TOKEN is a simple token for development environments only.
`VAULT_DEV_TOKEN="root"`

`VAULT_KEYS_FILE="vault-keys.json"`

key-shares (int: 5) - Number of key shares to split the generated master key into. This is the number of "unseal keys" to generate.
`VAULT_KEY_SHARED=1`

key-threshold (int: 3) - Number of key shares required to reconstruct the root key. This must be less than or equal to -key-shares
`VAULT_KEY_THRESHOLD=1`

replicas (number) Set the number of replicas of vault pods inside your cluster.
`VAULT_HA_REPLICAS=2`

# EXAMPLES

## First install with my operator keys

Running a operator for first time and all provisioned migrations ( -i ), with operator keys inside operator-keypairs-full path ( -k ) and using my local file ( -f ) named config.ini.local

[![asciicast](https://asciinema.org/a/Wr91t5WbJBaWs7AH5m7VXbMBG.svg)](https://asciinema.org/a/Wr91t5WbJBaWs7AH5m7VXbMBG)

## First install without keys and read only mode

In this option, I didn't have any operator key, and the proxy runs in read only mode ( -r )

[![asciicast](https://asciinema.org/a/aQygYbL2dnszJNm5Pw1f8rGZ7.svg)](https://asciinema.org/a/aQygYbL2dnszJNm5Pw1f8rGZ7)


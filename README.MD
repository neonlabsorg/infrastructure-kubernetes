### Requirements for proxy-operator

#### Solana RPC node:
https://docs.solana.com/running-validator/validator-reqs#hardware-recommendations

#### Kubernetes Cluster:

- 12 vcpu and 16GB RAM.
- At least 256GB disk space.
- Kubernetes already installed (at least 1.21)
- NFS server for storage
- Helm 3, Kubectl

If you are starting with kubernetes, please check [this getting started with k8s](https://github.com/neonlabsorg/infrastructure-kubernetes/blob/main/docs/k8s-setup-with-k0s.MD)

### Environments setup

Copy and set variables in config file
    
    cp config.ini.sample config.ini



### Operator keys

Copy your private keys on operator-keypairs path.


### Run setup

You can set some important variabels in command line;

#./neon-proxy.sh -h

    -f, Variabels file
    -i, Init setup
    -r, Read-only mode
    -S, SOLANA_URL
    -s, PP_SOLANA_URL
    -p, Set postgres admin password (can be used only with -i option)
    -m, Use this option to set migrations
    -k, Set keys directory
    -y, Assume "yes" as answer, run non-interactively

First setup you need run with -i key

### Testing

If your applications are up and running, just forward the proxy port for connectivity tests:

    kubectl port-forward pod/neon-proxy-0 9090:9090 --namespace neon-proxy
    
    ❯ curl localhost:9090/solana
    {"jsonrpc": "2.0", "error": {"code": -32000, "message": "'NoneType' object has no attribute 'decode'"}}%  
    
Please check detailed parameters in our docs directory.

# EXAMPLES

## First install with my operator keys

Running a operator for first time and all provisioned migrations ( -i ), with operator keys inside operator-keypairs-full path ( -k ) and using my local file ( -f ) named config.ini.local

[![asciicast](https://asciinema.org/a/Wr91t5WbJBaWs7AH5m7VXbMBG.svg)](https://asciinema.org/a/Wr91t5WbJBaWs7AH5m7VXbMBG)

## First install without keys and read only mode

In this option, I didn't have any operator key, and the proxy runs in read only mode ( -r )

[![asciicast](https://asciinema.org/a/aQygYbL2dnszJNm5Pw1f8rGZ7.svg)](https://asciinema.org/a/aQygYbL2dnszJNm5Pw1f8rGZ7)

   


## NFS Storage class example

NFS Server must be installed

[Ubuntu example](https://ubuntu.com/server/docs/service-nfs/)

Install NFS provisioner

    helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner

    helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
        --set nfs.server=x.x.x.x \
        --set nfs.path=/exported/path


Check name of NFS StorageClass

    kubectl get storageclass

In config.ini files set varables 

    POSTGRES_STORAGE_CLASS="nfs-client"

If you need monitoring part

    PROMETHEUS_STORAGE_CLASS="nfs-client"
    GRAFANA_STORAGE_CLASS="nfs-client"
    LOKI_STORAGE_CLASS="nfs-client"
    
## Gasless setup

 Set MINIMAL_GAS_PRICE to 0 + Remove/delete PYTH configuration, if you want 0 gas-price:
      In config.ini, set:
      
      PRX_MINIMAL_GAS_PRICE="0"
      # ...and
      # delete lines that contains:
      PYTH_MAPPING_ACCOUNT
      PP_SOLANA_URL      


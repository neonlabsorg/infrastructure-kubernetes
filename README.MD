### Requirements for proxy-operator

Kubernetes Cluster:

- 8 vcpu and 16GB RAM.
- At least 200GB disk space.
- Kubernetes already installed (at least 1.21)
- Helm 3, Kubectl

### Environments setup

Copy and set variables in config file
    
    cp config.ini.sample config.ini



### Operator keys

Copy your public keys on operator-keypairs path.


### Run setup

You can set some important variabels in command line;

#./neon-proxy.sh -h

    -f, Variabels file
    -i, Init setup
    -r, Read-only mode
    -S, SOLANA_URL 
    -s, PP_SOLANA_URL 
    -e, Set environment ("devnet", "testnet" or "mainnet")  
    -d, Postgres password
    -m, Use this option to set migrations
    -k, operator kyes dir
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

   



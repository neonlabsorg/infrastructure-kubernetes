### Requirements for proxy-operator

#### Solana RPC node:
From https://docs.solana.com/running-validator/validator-reqs

##### Minimum Hardware Requirements
Here are the minimum hardware requirements for running a Solana node in terms of memory, compute, storage, and operating system.

1. Memory

128GB, or more for consensus validator nodes

258GB, or more for RPC nodes

2. Compute

12 cores / 24 threads, or more @ minimum of 2.8GHz for consensus validator nodes

16 cores / 32 threads, or more for RPC nodes

3. Storage

For consensus validators:

PCIe Gen3 x4 NVME SSD, or better

Accounts: 500GB, or larger. High TBW (Total Bytes Written)

Ledger: 1TB or larger. High TBW suggested

For RPC nodes:

A larger ledger disk if longer transaction history is required, Accounts and ledger should not be stored on the same disk

GPUs are not strictly necessary

Network: 1 GBPS up and down link speed,  must be unshaped and unmetered


4. Operating System

Ubuntu 20.04, Windows 10 or later, macOS High Sierra or later.

##### How to run Solana node:

If your application requires a highly specific node configuration, running your own now may be preferable to using a Solana node provider. Running a node on the Solana network requires a few steps, including buying the aforementioned hardware, setting up the server, and creating an account and a Solana wallet.

##### 1. Create a Sol User
First, create a `sol` user with this command from your terminal:

`sudo adduser sol`

##### 2. Install Solana
Second, install Solana with this command:

`sh -c "$(curl -sSfL https://release.solana.com/v1.14.7/install)"`


##### 3. Create a Mount for Point for Ledger
Third, create a mount point for ledger (not required if you are just running as a RPC node)

`sudo mkdir -p /mnt/ledger`

`sudo chown -R sol:sol /mnt/ledger`

`sudo mount /dev/nvme0n1 /mnt/ledger`

##### 4. Connect to the Solana Devnet
Fourth, join the Solana Devnet cluster and test your connection:

`solana config set --url devnet`

`solana gossip`

##### 5. Create Four Solana Accounts
Fifth, create the four necessary accounts: a system account, a validator identity account, a voting account, and a staking account.

5a. System Account
A system account, which simulates the owners’ wallet, is also used to transfer voting funds to the validator and withdraw rewards from the vote account.

`solana-keygen new --outfile ~/system-wallet-keypair.json`  #(create a new key pair that identifies the system account)

`solana airdrop 1 ~/system-wallet-keypair.json` #(adding 1 SOL to wallet, only possible in devnet)

`solana balance ~/system-wallet-keypair.json`

#### Kubernetes Cluster:

- 8 vcpu and 16GB RAM.
- At least 200GB disk space.
- Kubernetes already installed (at least 1.21)
- Helm 3, Kubectl

If you are starting with kubernetes, please check [this getting started with k8s](https://github.com/neonlabsorg/infrastructure-kubernetes/blob/main/docs/k8s-setup-with-k0s.MD)

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

   



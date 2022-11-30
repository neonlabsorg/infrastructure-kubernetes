## Install kubernetes in MacOS

### Requirements

Install kubectl for [macos](https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/)

Install helm:

```bash
brew install helm
```

You need [brew](https://brew.sh/) already installed in your macos.

Now, we need docker daemon that brings docker-desktop application:

```bash
brew install --cask docker
```
![Alt text](https://www.endpointdev.com/blog/2022/06/getting-started-with-docker-and-kubernetes-on-macos/image-01.webp "docker desktop")

Now you can find docker app in your "Applications" folder:

![Alt text](https://www.endpointdev.com/blog/2022/06/getting-started-with-docker-and-kubernetes-on-macos/image-02.webp "docker desktop")

Open...

![Alt text](https://www.endpointdev.com/blog/2022/06/getting-started-with-docker-and-kubernetes-on-macos/image-03.webp "docker desktop")

Enable kubernetes in "Preferences"...

![Alt text](https://www.endpointdev.com/blog/2022/06/getting-started-with-docker-and-kubernetes-on-macos/image-07.webp "docker desktop")

Enable kubernetes, apply and restart:

![Alt text](https://www.endpointdev.com/blog/2022/06/getting-started-with-docker-and-kubernetes-on-macos/image-08.webp "docker desktop")

Check that kubernetes are in running state:

![Alt text](https://www.endpointdev.com/blog/2022/06/getting-started-with-docker-and-kubernetes-on-macos/image-09.webp "docker desktop")

Open your terminal and set the right context for your local kubernetes:

```bash
$ kubectl config use-context docker-desktop
Switched to context “docker-desktop”
```


You have lightweight alternatives for kubernetes testing/development purposes:

1. minikube
[Install](https://minikube.sigs.k8s.io/docs/start/) process for minikube website.

2. microk8s
[Install](https://microk8s.io/#install-microk8s) instructions for microk8s website.

3. kind
[Install](https://kind.sigs.k8s.io/docs/user/quick-start/) docs from kind.

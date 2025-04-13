Este repositorio contiene los archivos necesarios para desplegar una aplicación web estática en un cluster de Minikube.

## Requisitos Previos

- Minikube instalado.
```bash
minikube version
```

- kubectl instalado.
```bash
kubectl version --client
```

- Docker instalado.
```bash
docker --version
docker run hello-world
```

## Pasos para Desplegar el Entorno

1. Clona este repositorio:
```bash
git clone https://github.com/tu-usuario/mi-proyecto-kubernetes.git
cd mi-proyecto-kubernetes
```

2. Inicia Minikube:
```bash
minikube start --driver=docker
```

Habilita el addon ingress:
```bash
minikube addons enable ingress
```

Aplica los manifiestos:
```bash
kubectl apply -f manifests/persistentvolume/pv.yaml
kubectl apply -f manifests/persistentvolume/pvc.yaml
kubectl apply -f manifests/deployments/app-deployment.yaml
kubectl apply -f manifests/services/app-service.yaml
```

Obten la URL del servicio:
```bash
minikube service web-app-service --url
```

Abre la URL en tu navegador para ver la aplicación.
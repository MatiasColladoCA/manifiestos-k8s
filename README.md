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

### 1. Clona el repositorio de manifiestos en una carpeta
```bash
git clone https://github.com/tu-usuario/mi-proyecto-kubernetes.git
cd mi-proyecto-kubernetes
```

### 2. Clona el repositorio de contenido estático en otra carpeta
Clona el repositorio que contiene el contenido estático:

```bash
git clone https://github.com/MatiasColladoCA/static-website
```

### 3. Inicia Minikube:
```bash
minikube start
```

Habilita el addon ingress:
```bash
minikube addons enable ingress
```

### 4. Monta el Directorio Local en Minikube
Usa el comando `minikube mount` para montar el directorio local (ruta-de-contenido-estatico/) en un directorio dentro de Minikube:
```bash
minikube mount ./contenido-estatico/content:/mnt/static-content
```
`./ruta-de-contenido-estatico/content`: Es la ruta local donde tienes el contenido estático.

`/mnt/static-content`: Es la ruta dentro de Minikube donde estará disponible el contenido.

Finalmente, verifica que el contenido está montado correctamente dentro de Minikube:

Accede al shell de Minikube:
```bash
minikube ssh
```

Navega al directorio /mnt/static-content:
```bash
cd /mnt/static-content
```

Lista los archivos:
```bash
ls
```

Si ves los archivos de tu carpeta local, el montaje ha sido exitoso.


### 5. Aplica los manifiestos:
Estando en la carpeta del repositorio de manifiestos, ejecutar:

```bash
kubectl apply -f manifests/persistentvolume/pv.yaml
kubectl apply -f manifests/persistentvolume/pvc.yaml
kubectl apply -f manifests/deployments/app-deployment.yaml
kubectl apply -f manifests/services/app-service.yaml
```

Verifica que los recursos se hayan creado correctamente:

```bash
kubectl get all
```

Obten la URL del servicio:
```bash
minikube service web-app-service --url
```

Abre la URL en tu navegador para ver la aplicación.
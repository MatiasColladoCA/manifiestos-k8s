#!/usr/bin/env bash
# Script de despliegue automático para aplicación web estática en Kubernetes
# Autor: Matías Collado <matias.collado@gmail.com>
# Versión: 1.1.0
# Fecha: 2023-11-06
# Repo: https://github.com/MatiasColladoCA/manifiestos-k8s

# CONFIGURACIÓN (Variables configurables)
# ---------------------------------------
WORK_DIR="${HOME}/k8s-static-deploy"
REPO_URL="https://github.com/MatiasColladoCA/manifiestos-k8s.git"
STATIC_REPO="https://github.com/MatiasColladoCA/static-website.git"
MOUNT_LOCAL_DIR="${WORK_DIR}/static-website"
MOUNT_REMOTE_DIR="/mnt/static-content"
K8S_MANIFESTS_DIR="${WORK_DIR}/manifiestos-k8s/manifests"
MINIKUBE_PROFILE="default"
AUTO_INSTALL=false

# CONFIGURACIÓN OPCIONAL VIA ARGUMENTOS
# ------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --work-dir=*) WORK_DIR="${1#*=}"; shift ;;
        --repo-url=*) REPO_URL="${1#*=}"; shift ;;
        --static-repo=*) STATIC_REPO="${1#*=}"; shift ;;
        --auto-install)
            AUTO_INSTALL=true
            shift
            ;;
        -h|--help)
            echo "Uso: $0 [opciones]"
            echo "Opciones:"
            echo "  --work-dir=<dir>      Directorio de trabajo (por defecto: ${WORK_DIR})"
            echo "  --repo-url=<url>      Repo de manifiestos (por defecto: ${REPO_URL})"
            echo "  --static-repo=<url>   Repo de contenido estático (por defecto: ${STATIC_REPO})"
            echo "  --auto-install        Instalar dependencias automáticamente sin preguntar"
            exit 0
            ;;
        *)
            echo "Opción desconocida: $1"
            exit 1
            ;;
    esac
done

# CONFIGURACIÓN DE SEGURIDAD Y ESTILO
# ----------------------------------
set -o errexit  # Salir si hay errores
set -o pipefail # Detectar errores en tuberías
set -o nounset  # No permitir variables no definidas
IFS=$'\n\t'     # Configurar IFS para mayor seguridad

# FUNCIONES AUXILIARES
# --------------------

verify_docker_access() {
    if docker info &>/dev/null; then
        log "INFO" "Docker está instalado y accesible."
        return 0
    fi

    log "INFO" "Intentando aplicar permisos de Docker reiniciando el contexto del grupo..."
    
    # Intenta reiniciar el grupo
    if newgrp docker < /dev/null; then
        log "INFO" "Contexto de grupo reiniciado. Verificando nuevamente acceso a Docker..."
        
        if docker info &>/dev/null; then
            log "INFO" "Acceso a Docker verificado tras reiniciar el grupo."
            return 0
        else
            log "WARNING" "Aún no hay acceso a Docker después de reiniciar el grupo."
        fi
    else
        log "WARNING" "No se pudo reiniciar el grupo automáticamente."
    fi

    log "ERROR" "No se puede acceder al daemon de Docker. Es necesario reiniciar la sesión."
    log "INFO" "Por favor:"
    log "1. Cierre y abra nuevamente la terminal"
    log "2. Ejecute: sudo usermod -aG docker \$USER && newgrp docker"
    log "3. Vuelva a ejecutar este script"

    exit 1
}

log() {
    local level message

    if [[ $# -eq 1 ]]; then
        level="INFO"
        message="$1"
    elif [[ $# -ge 2 ]]; then
        level="$1"
        message="$2"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] No se proporcionó ningún mensaje a 'log'"
        return 1
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
}


ask_yes_no() {
    local question="$1"
    if [[ "$AUTO_INSTALL" == true ]]; then
        return 0
    fi
    
    read -r -p "$question (y/n): " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

check_dependencies() {
    local deps=("minikube" "kubectl" "docker")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log "WARNING" "Faltan dependencias: ${missing_deps[*]}"
        
        if ask_yes_no "¿Desea instalar las dependencias faltantes?"; then
            install_dependencies "${missing_deps[@]}"
        else
            log "ERROR" "Dependencias requeridas no encontradas. Instálalas manualmente y vuelve a intentar."
            exit 1
        fi
    fi
}

install_dependencies() {
    local deps_to_install=("$@")
    local os_type=$(uname -s)
    
    log "INFO" "Iniciando instalación de dependencias: ${deps_to_install[*]}"
    
    case "$os_type" in
        Linux*)
            install_dependencies_linux "${deps_to_install[@]}"
            ;;
        Darwin*)
            install_dependencies_mac "${deps_to_install[@]}"
            ;;
        *)
            log "ERROR" "Sistema operativo no soportado: $os_type"
            exit 1
            ;;
    esac
    
    log "INFO" "Verificando instalación..."
    for dep in "${deps_to_install[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            log "ERROR" "Fallo al instalar $dep"
            exit 1
        fi
    done
}

install_dependencies_linux() {
    local deps=("$@")
    
    # Actualizar paquetes
    sudo apt-get update -y || { log "ERROR" "Fallo al actualizar paquetes"; exit 1; }
    
    # Instalar dependencias necesarias para las instalaciones
    sudo apt-get install -y curl wget gnupg2 software-properties-common || { 
        log "ERROR" "Fallo al instalar dependencias básicas"; 
        exit 1; 
    }
    
    for dep in "${deps[@]}"; do
        case "$dep" in
            docker)
                log "INFO" "Instalando Docker..."
                curl -fsSL https://get.docker.com | sh || { 
                    log "ERROR" "Fallo al instalar Docker";
                    exit 1;
                }

                if ! groups "$USER" | grep -q &>/dev/null "docker"; then
                    log "INFO" "Agregando usuario $USER al grupo 'docker'..."
                    sudo usermod -aG docker "$USER" || {
                        log "WARNING" "No se pudo agregar el usuario al grupo docker.";
                        log "INFO" "Por favor, ejecute manualmente: sudo usermod -aG docker \$USER && newgrp docker";
                    }
                    
                    log "INFO" "Reiniciando contexto de shell para aplicar cambios..."
                    exec newgrp docker < /dev/null
                fi
                ;;
            minikube)
                log "INFO" "Instalando Minikube..."
                curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 || { 
                    log "ERROR" "Fallo al descargar Minikube";
                    exit 1;
                }
                sudo install minikube-linux-amd64 /usr/local/bin/minikube || { 
                    log "ERROR" "Fallo al instalar Minikube";
                    exit 1;
                }
                ;;
            kubectl)
                log "INFO" "Instalando kubectl..."
                curl -LO "https://dl.k8s.io/release/$(curl -LSs https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" || { 
                    log "ERROR" "Fallo al descargar kubectl";
                    exit 1;
                }
                sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl || { 
                    log "ERROR" "Fallo al instalar kubectl";
                    exit 1;
                }
                ;;
        esac
    done
}

install_dependencies_mac() {
    local deps=("$@")
    
    # Verificar Homebrew
    if ! command -v brew &>/dev/null; then
        log "INFO" "Instalando Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
            log "ERROR" "Fallo al instalar Homebrew";
            exit 1;
        }
    fi
    
    for dep in "${deps[@]}"; do
        case "$dep" in
            docker)
                log "INFO" "Instalando Docker Desktop para Mac..."
                log "WARNING" "Se requiere instalación manual desde https://www.docker.com/products/docker-desktop"
                ;;
            minikube)
                log "INFO" "Instalando Minikube..."
                brew install minikube || { 
                    log "ERROR" "Fallo al instalar Minikube";
                    exit 1;
                }
                ;;
            kubectl)
                log "INFO" "Instalando kubectl..."
                brew install kubernetes-cli || { 
                    log "ERROR" "Fallo al instalar kubectl";
                    exit 1;
                }
                ;;
        esac
    done
}

setup_directories() {
    mkdir -p "${WORK_DIR}" || true
    cd "${WORK_DIR}" || { log "ERROR" "No se puede acceder al directorio de trabajo"; exit 1; }
}

verify_minikube_status() {
    if ! minikube status --profile="${MINIKUBE_PROFILE}" &>/dev/null; then
        log "INFO" "Minikube no está corriendo. Iniciando..."
        minikube start --profile="${MINIKUBE_PROFILE}"
    fi
}

enable_addons() {
    if ! minikube addons list | grep -q "ingress.*enabled"; then
        log "INFO" "Habilitando addon 'ingress'..."
        minikube addons enable ingress --profile="${MINIKUBE_PROFILE}"
    fi
}

clone_repository() {
    local repo_url="$1"
    local target_dir="$2"
    
    if [[ ! -d "${target_dir}" ]]; then
        log "INFO" "Clonando repositorio ${repo_url}..."
        git clone "${repo_url}" "${target_dir}" || {
            log "ERROR" "Fallo al clonar el repositorio ${repo_url}"
            exit 1
        }
    else
        log "INFO" "Repositorio ${repo_url} ya existe. Saltando clonación."
    fi
}

verify_mount() {
    if [[ $# -lt 2 ]]; then
        log "ERROR" "Faltan parámetros en verify_mount. Uso: verify_mount <ruta-local> <ruta-remota>"
        exit 1
    fi

    local local_dir="$1"
    local remote_dir="$2"
    
    # Verificar si el montaje ya existe
    if minikube mount list | grep -q "${remote_dir}"; then
        log "INFO" "El directorio ${local_dir} ya está montado en Minikube como ${remote_dir}"
        return 0
    fi
    
    log "INFO" "Montando ${local_dir} en Minikube como ${remote_dir}..."
    minikube mount "${local_dir}:${remote_dir}" --profile="${MINIKUBE_PROFILE}" & export MOUNT_PID=$!
    sleep 5 # Esperar a que se establezca el montaje
    
    # Verificar si el montaje fue exitoso
    if ! minikube ssh "ls ${remote_dir}" &>/dev/null; then
        log "ERROR" "Fallo al montar el directorio ${local_dir}"
        kill "${MOUNT_PID}" 2>/dev/null || true
        exit 1
    fi
}

apply_manifests() {
    local manifests_dir="$1"
    
    # Aplicar solo si no existen (usando get para verificar)
    for manifest in pv pvc app-deployment app-service; do
        local file="${manifests_dir}/${manifest}.yaml"
        local resource_name
        
        if [[ ! -f "$file" ]]; then
            log "ERROR" "Archivo de manifiesto no encontrado: ${file}"
            continue
        fi
        
        resource_name=$(basename "${file}" .yaml)
        
        if ! kubectl get -f "$file" &>/dev/null; then
            log "INFO" "Aplicando manifiesto: ${resource_name}"
            kubectl apply -f "$file"
        else
            log "INFO" "Manifiesto ${resource_name} ya aplicado. Saltando..."
        fi
    done
}

get_service_url() {
    local retries=3
    local count=0
    local url=""
    
    while [[ $count -lt $retries ]]; do
        url=$(minikube service web-app-service --url --profile="${MINIKUBE_PROFILE}" 2>/dev/null)
        if [[ -n "$url" ]]; then
            echo "$url"
            return 0
        fi
        sleep 5
        ((count++))
    done
    
    log "WARNING" "No se pudo obtener la URL del servicio después de ${retries} intentos"
    return 1
}

# MANEJO DE SEÑALES
# -----------------
trap '{
    log "INFO" "Limpiando recursos..."
    if [[ -n "${MOUNT_PID+x}" ]]; then
        kill "${MOUNT_PID}" 2>/dev/null || true
        wait "${MOUNT_PID}" 2>/dev/null || true
    fi
    exit 130
}' SIGINT SIGTERM

# FLUJO PRINCIPAL
# ---------------
main() {
    log "INFO" "Iniciando despliegue automático de aplicación web estática"
    
    check_dependencies
    verify_docker_access
    setup_directories
    
    verify_minikube_status
    enable_addons
    
    clone_repository "${REPO_URL}" "manifiestos-k8s"
    clone_repository "${STATIC_REPO}" "static-website"
    
    verify_mount "${MOUNT_LOCAL_DIR}" "${MOUNT_REMOTE_DIR}"
    
    apply_manifests "${K8S_MANIFESTS_DIR}"
    
    log "INFO" "Verificando recursos desplegados..."
    kubectl get all
    
    local service_url
    service_url=$(get_service_url)
    if [[ -n "$service_url" ]]; then
        log "INFO" "Aplicación disponible en: ${service_url}"
    fi
    
    log "INFO" "Despliegue completado exitosamente"
}

# EJECUCIÓN
# ---------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

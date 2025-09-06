#!/bin/bash

# Script para verificar prerequisitos antes del despliegue
set -e

echo "🔍 Verificando prerequisitos para el despliegue..."

# Verificar que kubectl está disponible
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl no está instalado"
    exit 1
fi

# Verificar que istioctl está disponible
if ! command -v istioctl &> /dev/null; then
    echo "❌ istioctl no está instalado"
    exit 1
fi

# Verificar que minikube está corriendo
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Kubernetes cluster no está disponible"
    exit 1
fi

# Verificar versión de Istio
ISTIO_VERSION=$(istioctl version --short --remote=false 2>/dev/null || echo "unknown")
echo "📋 Istio version: $ISTIO_VERSION"

# Verificar que Docker está corriendo (para minikube)
if ! docker info &> /dev/null; then
    echo "⚠️  Docker no está corriendo, pero puede no ser necesario"
fi

echo "✅ Prerequisitos verificados correctamente"
echo "🚀 Puedes proceder con 'make deploy-all'"
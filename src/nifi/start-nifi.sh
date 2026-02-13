#!/bin/bash
# Script parametrizável para iniciar NiFi em Codespaces ou ambiente local

set -e

echo "=== Iniciando Apache NiFi ==="

# Detectar se está em Codespaces
if [ -n "$CODESPACE_NAME" ]; then
    echo "✓ Detectado ambiente: GitHub Codespaces"
    # Construir URL do proxy dinamicamente
    PROXY_HOST="${CODESPACE_NAME}-8443.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
    echo "  Proxy Host: $PROXY_HOST"
else
    echo "✓ Detectado ambiente: Local/VM"
    PROXY_HOST="localhost:8443"
    echo "  Proxy Host: $PROXY_HOST"
fi

# Credenciais
NIFI_USER="${NIFI_USER:-admin}"
NIFI_PASSWORD="${NIFI_PASSWORD:-adminadmin123}"

echo ""
echo "=== Configurações ==="
echo "  Usuário: $NIFI_USER"
echo "  Senha: $NIFI_PASSWORD"
echo "  Porta: 8443"
echo ""

# Verificar se container já existe
if docker ps -a --format '{{.Names}}' | grep -q '^nifi$'; then
    echo "⚠️  Container 'nifi' já existe. Removendo..."
    docker stop nifi 2>/dev/null || true
    docker rm nifi 2>/dev/null || true
fi

# Executar container
echo "🚀 Criando volume persistente..."
docker volume create nifi-data 2>/dev/null || echo "  Volume nifi-data já existe"

echo "🚀 Iniciando container..."
docker run -d \
  --name nifi \
  -p 8443:8443 \
  -e SINGLE_USER_CREDENTIALS_USERNAME="$NIFI_USER" \
  -e SINGLE_USER_CREDENTIALS_PASSWORD="$NIFI_PASSWORD" \
  -e NIFI_WEB_HTTPS_PORT=8443 \
  -e NIFI_WEB_PROXY_HOST="$PROXY_HOST" \
  -v nifi-data:/opt/nifi/nifi-current/conf \
  --link minio:minio \
  --link schema-registry:schema-registry \
  apache/nifi:1.25.0

echo ""
echo "✅ Container iniciado!"
echo ""
echo "⏳ Aguarde 2-3 minutos para inicialização completa..."
echo ""
echo "📍 Acesso:"
if [ -n "$CODESPACE_NAME" ]; then
    echo "   URL: https://$PROXY_HOST"
else
    echo "   URL: https://localhost:8443/nifi"
fi
echo "   Usuário: $NIFI_USER"
echo "   Senha: $NIFI_PASSWORD"
echo ""
echo "📝 Para verificar logs:"
echo "   docker logs -f nifi"

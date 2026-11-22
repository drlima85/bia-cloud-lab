#!/usr/bin/env bash
# ==============================================================================
# check-availability.sh — Monitoramento Contínuo de Disponibilidade e Latência
# Projeto: BIA Cloud Lab — Formação AWS / D2NS
# Trilha: Estratégias de Deploy & Resiliência (Desafio 02)
# ==============================================================================
# Uso:
#   ./check-availability.sh [-E app|alb] [-u <URL>] [-i 2] [-c 10]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/common.sh" ]]; then
  # shellcheck source=./common.sh
  source "$SCRIPT_DIR/common.sh"
fi

DEFAULT_ALB_URL="${ALB_URL:-http://localhost:8080/api/versao}"
TARGET_URL="${TARGET_URL:-$DEFAULT_ALB_URL}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-2}"
MAX_REQUESTS="${MAX_REQUESTS:-0}" # 0 = contínuo até Ctrl+C
TIMEOUT_SECONDS=5

TOTAL_REQ=0
COUNT_2XX=0
COUNT_4XX=0
COUNT_5XX=0
COUNT_ERR=0
TOTAL_TIME_MS=0

show_help() {
  cat << EOF
$(basename "$0") — Monitoramento Contínuo de Disponibilidade HTTP e Latência

USO:
  $(basename "$0") [OPÇÕES]

OPÇÕES:
  -E, --env NOME              Ambiente alvo [app | alb | didatico] (padrão: ${TARGET_ENV:-app})
  -u, --url URL               URL alvo para monitoramento (padrão: $DEFAULT_ALB_URL)
  -i, --interval SECONDS      Intervalo entre requisições em segundos (padrão: $INTERVAL_SECONDS)
  -c, --count NUM             Número máximo de requisições a enviar (0 = contínuo)
  -t, --timeout SECONDS       Timeout por requisição em segundos (padrão: $TIMEOUT_SECONDS)
  -h, --help                  Exibe esta mensagem de ajuda

EXEMPLO:
  # Monitorar o ambiente principal (app):
  $(basename "$0") -i 1

  # Monitorar o ambiente secundário (alb):
  $(basename "$0") -E alb -i 1

  # Enviar exatamente 10 requisições para validação rápida:
  $(basename "$0") -c 10
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -E|--env)
      if declare -f load_environment >/dev/null; then
        load_environment "$2"
        TARGET_URL="$ALB_URL"
      fi
      shift 2
      ;;
    -u|--url) TARGET_URL="$2"; shift 2 ;;
    -i|--interval) INTERVAL_SECONDS="$2"; shift 2 ;;
    -c|--count) MAX_REQUESTS="$2"; shift 2 ;;
    -t|--timeout) TIMEOUT_SECONDS="$2"; shift 2 ;;
    -h|--help) show_help; exit 0 ;;
    *) echo "[ERROR] Opção desconhecida: $1" >&2; show_help; exit 1 ;;
  esac
done

if ! command -v curl &> /dev/null; then
  echo "[ERROR] curl não está instalado no sistema." >&2
  exit 1
fi

print_summary() {
  echo ""
  echo "=========================================================="
  echo "            Sumário de Disponibilidade e Latência         "
  echo "=========================================================="
  echo "URL Monitorada:       $TARGET_URL"
  echo "Total de Requisições: $TOTAL_REQ"
  echo "Respostas HTTP 2XX:   $COUNT_2XX"
  echo "Respostas HTTP 4XX:   $COUNT_4XX"
  echo "Respostas HTTP 5XX:   $COUNT_5XX"
  echo "Erros de Conexão:     $COUNT_ERR"
  if [[ $TOTAL_REQ -gt 0 && $((TOTAL_REQ - COUNT_ERR)) -gt 0 ]]; then
    local valid_reqs=$((TOTAL_REQ - COUNT_ERR))
    local avg_ms=$((TOTAL_TIME_MS / valid_reqs))
    local success_rate=$(( (COUNT_2XX * 100) / TOTAL_REQ ))
    echo "Tempo Médio (ms):     ${avg_ms} ms"
    echo "Taxa de Sucesso 2XX:  ${success_rate}%"
  fi
  echo "=========================================================="
}

trap print_summary EXIT

echo "Iniciando monitoramento de disponibilidade..."
echo "URL: $TARGET_URL | Intervalo: ${INTERVAL_SECONDS}s | Pressione Ctrl+C para encerrar."
echo "--------------------------------------------------------------------------------"

while true; do
  TOTAL_REQ=$((TOTAL_REQ + 1))
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

  # curl formata: http_code|time_total_seconds
  HTTP_RESULT=$(curl -s -o /dev/null \
    -w "%{http_code}|%{time_total}" \
    --max-time "$TIMEOUT_SECONDS" \
    "$TARGET_URL" 2>/dev/null || echo "000|0")

  HTTP_CODE=$(echo "$HTTP_RESULT" | cut -d'|' -f1)
  TIME_SEC=$(echo "$HTTP_RESULT" | cut -d'|' -f2)

  # Converte segundos fracionários para ms inteiros
  TIME_MS=$(awk "BEGIN {print int($TIME_SEC * 1000)}")
  TOTAL_TIME_MS=$((TOTAL_TIME_MS + TIME_MS))

  # Classificação do status
  if [[ "$HTTP_CODE" =~ ^2[0-9]{2}$ ]]; then
    COUNT_2XX=$((COUNT_2XX + 1))
    COLOR="\033[0;32m" # Verde
  elif [[ "$HTTP_CODE" =~ ^4[0-9]{2}$ ]]; then
    COUNT_4XX=$((COUNT_4XX + 1))
    COLOR="\033[1;33m" # Amarelo
  elif [[ "$HTTP_CODE" =~ ^5[0-9]{2}$ ]]; then
    COUNT_5XX=$((COUNT_5XX + 1))
    COLOR="\033[0;31m" # Vermelho
  else
    COUNT_ERR=$((COUNT_ERR + 1))
    HTTP_CODE="ERR"
    COLOR="\033[0;35m" # Roxo
  fi
  NC="\033[0m"

  echo -e "[$TIMESTAMP] Status: ${COLOR}${HTTP_CODE}${NC} | Latência: ${TIME_MS}ms | Req #$TOTAL_REQ"

  if [[ "$MAX_REQUESTS" -gt 0 && "$TOTAL_REQ" -ge "$MAX_REQUESTS" ]]; then
    break
  fi

  sleep "$INTERVAL_SECONDS"
done

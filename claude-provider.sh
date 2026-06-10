# claude-provider.sh — Claude Code provider switching
#
# Source this file (don't execute). Defines `claude-provider`, which mutates
# env vars in the current shell to point Claude Code at one of three backends:
# Claude Max subscription, Vertex AI, or a raw Anthropic API key.
#
#   source ~/Projects/dotfiles/claude-provider.sh
#
# Subcommands: max | vertex | apikey [KEY] | status | check | fix | push
# Short alias: cprov
#
# Vertex config (project, region, push target) is read from env vars set in
# ~/.secrets. Sensible defaults are baked in so the script still works if the
# vars are unset. See ~/CLAUDE.md for usage and HAAK's
# platform/methods/model/model-router.md for Vertex config authority.

claude-provider() {
    local GREEN='\033[0;32m' YELLOW='\033[1;33m' RED='\033[0;31m' BOLD='\033[1m' RESET='\033[0m'
    local GCP_PROJECT="${VERTEX_PROJECT_ID:-cr-mainen}"
    local GCP_REGION="${VERTEX_REGION:-europe-west1}"
    local REMOTE_HOST="${VERTEX_KEY_PUSH_TARGET:-haak-personal}"
    local ADC_PATH="${GOOGLE_APPLICATION_CREDENTIALS:-$HOME/.config/gcloud/legacy_credentials/vertex@${GCP_PROJECT}.iam.gserviceaccount.com/adc.json}"
    local _os LOCAL_HOSTNAME IS_MAC=false IS_REMOTE_TARGET=false ROLE_LABEL
    _os="$(uname -s)"
    LOCAL_HOSTNAME="$(hostname -s)"
    [ "$_os" = "Darwin" ] && IS_MAC=true
    if $IS_MAC; then
        ROLE_LABEL="local (Mac)"
    else
        IS_REMOTE_TARGET=true
        case "$LOCAL_HOSTNAME" in
            *"$REMOTE_HOST"*|*exoscale*) ROLE_LABEL="remote ($REMOTE_HOST)" ;;
            *) ROLE_LABEL="remote ($LOCAL_HOSTNAME)" ;;
        esac
    fi
    local cmd="${1:-status}"

    case "$cmd" in
        status)
            echo ""
            printf "  ${BOLD}Claude Code Provider${RESET}\n\n"
            if [ "${ANTHROPIC_AUTH_TOKEN:-}" = "ollama" ]; then
                printf "  ${GREEN}●${RESET} Provider: ${GREEN}Ollama${RESET} (${ANTHROPIC_BASE_URL:-http://localhost:11434})\n"
            elif [ "${CLAUDE_CODE_USE_VERTEX:-}" = "1" ]; then
                printf "  ${GREEN}●${RESET} Provider: ${GREEN}Vertex AI${RESET} (project: ${ANTHROPIC_VERTEX_PROJECT_ID:-unset})\n"
                printf "    Region:  ${CLOUD_ML_REGION:-unset}\n"
            elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
                printf "  ${YELLOW}●${RESET} Provider: ${YELLOW}API key${RESET} (%s...)\n" "$(printf %s "$ANTHROPIC_API_KEY" | cut -c1-12)"
            else
                printf "  ${BOLD}●${RESET} Provider: ${BOLD}Claude Max${RESET} (subscription)\n"
            fi
            echo ""
            printf "  ${BOLD}Machine${RESET}\n"
            printf "    Hostname: %s\n" "$LOCAL_HOSTNAME"
            printf "    Role:     %s\n\n" "$ROLE_LABEL"
            printf "  ${BOLD}Env vars${RESET}\n"
            if [ -n "${CLAUDE_CODE_USE_VERTEX:-}" ]; then
                printf "    CLAUDE_CODE_USE_VERTEX      = ${GREEN}%s${RESET}\n" "$CLAUDE_CODE_USE_VERTEX"
            else
                printf "    CLAUDE_CODE_USE_VERTEX      = ${RED}(unset)${RESET}\n"
            fi
            if [ -n "${ANTHROPIC_VERTEX_PROJECT_ID:-}" ]; then
                printf "    ANTHROPIC_VERTEX_PROJECT_ID = ${GREEN}%s${RESET}\n" "$ANTHROPIC_VERTEX_PROJECT_ID"
            else
                printf "    ANTHROPIC_VERTEX_PROJECT_ID = ${RED}(unset)${RESET}\n"
            fi
            if [ -n "${CLOUD_ML_REGION:-}" ]; then
                printf "    CLOUD_ML_REGION             = %s\n" "$CLOUD_ML_REGION"
            else
                printf "    CLOUD_ML_REGION             = (unset)\n"
            fi
            if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
                printf "    ANTHROPIC_API_KEY           = ${YELLOW}%s...${RESET}\n" "$(printf %s "$ANTHROPIC_API_KEY" | cut -c1-12)"
            else
                printf "    ANTHROPIC_API_KEY           = (unset)\n"
            fi
            echo ""
            ;;

        vertex)
            # Consult sentinel health verdict before switching.
            local _haak_db="${HAAK_ROOT:-$HOME/Projects/haak}/infra/var/haak.db"
            if [ -f "$_haak_db" ] && command -v sqlite3 >/dev/null 2>&1; then
                local _vertex_errors
                _vertex_errors=$(sqlite3 "$_haak_db" \
                    "SELECT error_class FROM model_registry WHERE provider='vertex' AND error_class IS NOT NULL AND error_class != '' GROUP BY error_class" 2>/dev/null)
                if [ -n "$_vertex_errors" ]; then
                    case "$_vertex_errors" in
                        *auth*)
                            printf "  ${RED}⚠ Vertex auth broken${RESET} — sentinel detected credential failure.\n"
                            printf "  Fix: gcloud auth activate-service-account vertex@%s.iam.gserviceaccount.com --key-file=%s\n" "$GCP_PROJECT" "$ADC_PATH"
                            printf "  Falling back to ${BOLD}Max${RESET}.\n\n"
                            claude-provider max
                            return ;;
                        *not_enabled*)
                            printf "  ${YELLOW}⚠ Some models not enabled on Vertex${RESET} — enable in GCP Model Garden console.\n" ;;
                        *rate_limit*)
                            if [ "$GCP_REGION" != "global" ]; then
                                printf "  ${YELLOW}⚠ Regional quota exhausted${RESET} — switching to global endpoint.\n"
                                GCP_REGION="global"
                            fi ;;
                    esac
                fi
            fi
            export CLAUDE_CODE_USE_VERTEX=1
            export ANTHROPIC_VERTEX_PROJECT_ID="$GCP_PROJECT"
            export CLOUD_ML_REGION="$GCP_REGION"
            unset ANTHROPIC_API_KEY 2>/dev/null
            # Bind ADC to the non-expiring service-account key. Without this,
            # google-auth falls back to ~/.config/gcloud/application_default_credentials.json
            # (an OAuth authorized_user token that silently expires) — the June 2026 outage.
            if [ -f "$ADC_PATH" ]; then
                export GOOGLE_APPLICATION_CREDENTIALS="$ADC_PATH"
            else
                printf "  ${YELLOW}Warning:${RESET} SA key not found at %s — Vertex auth may fall back to OAuth ADC.\n" "$ADC_PATH"
            fi
            printf "  ${GREEN}●${RESET} Switched to ${GREEN}Vertex AI${RESET} (project: %s, region: %s)\n" "$GCP_PROJECT" "$GCP_REGION"
            ;;

        apikey)
            local _key="${2:-}"
            if [ -z "$_key" ]; then
                if [ -f "$HOME/.anthropic/api_key" ]; then
                    _key="$(tr -d '[:space:]' < "$HOME/.anthropic/api_key")"
                    printf "  Read API key from ${BOLD}~/.anthropic/api_key${RESET}\n"
                else
                    printf "  ${YELLOW}No key argument and ~/.anthropic/api_key not found.${RESET}\n"
                    printf "  Enter API key: "
                    read -r _key
                    if [ -z "$_key" ]; then
                        printf "  ${RED}No key provided. Aborting.${RESET}\n"
                        return 1
                    fi
                fi
            fi
            unset CLAUDE_CODE_USE_VERTEX ANTHROPIC_VERTEX_PROJECT_ID CLOUD_ML_REGION GOOGLE_APPLICATION_CREDENTIALS 2>/dev/null
            export ANTHROPIC_API_KEY="$_key"
            printf "  ${GREEN}●${RESET} Switched to ${GREEN}API key${RESET} (%s...)\n" "$(printf %s "$_key" | cut -c1-12)"
            ;;

        max)
            unset CLAUDE_CODE_USE_VERTEX ANTHROPIC_VERTEX_PROJECT_ID CLOUD_ML_REGION ANTHROPIC_API_KEY GOOGLE_APPLICATION_CREDENTIALS 2>/dev/null
            unset ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL 2>/dev/null
            printf "  ${BOLD}●${RESET} Switched to ${BOLD}Claude Max${RESET} (subscription)\n"
            if ! command -v claude >/dev/null 2>&1 || ! claude auth status >/dev/null 2>&1; then
                printf "  ${YELLOW}Reminder:${RESET} run ${BOLD}claude login${RESET} if you haven't authenticated yet.\n"
            fi
            ;;

        ollama)
            local _url="${2:-http://localhost:11434}"
            local _model="${3:-qwen3-coder}"
            unset CLAUDE_CODE_USE_VERTEX ANTHROPIC_VERTEX_PROJECT_ID CLOUD_ML_REGION ANTHROPIC_API_KEY GOOGLE_APPLICATION_CREDENTIALS 2>/dev/null
            export ANTHROPIC_AUTH_TOKEN=ollama
            export ANTHROPIC_BASE_URL="$_url"
            printf "  ${GREEN}●${RESET} Switched to ${GREEN}Ollama${RESET} (%s)\n" "$_url"
            printf "    Model hint: ${BOLD}claude --model %s${RESET}\n" "$_model"
            if ! curl -sf "$_url/api/tags" >/dev/null 2>&1; then
                printf "  ${YELLOW}Warning:${RESET} Ollama not reachable at %s\n" "$_url"
                printf "  Start with: ${BOLD}ollama serve${RESET}\n"
            fi
            ;;

        fix)
            printf "  ${GREEN}SA key auth does not require re-authentication.${RESET}\n"
            printf "  Key path: %s\n" "$ADC_PATH"
            if [ -f "$ADC_PATH" ]; then
                printf "  ${GREEN}Key file exists.${RESET}\n"
            else
                printf "  ${RED}Key file not found!${RESET} Place your SA key at %s\n" "$ADC_PATH"
            fi
            ;;

        push)
            if ! $IS_MAC; then
                printf "  ${RED}You're already on the remote (%s). Nothing to push to yourself.${RESET}\n" "$LOCAL_HOSTNAME"
                return 1
            fi
            if [ ! -f "$ADC_PATH" ]; then
                printf "  ${RED}SA key not found:${RESET} %s\n" "$ADC_PATH"
                return 1
            fi
            printf "  Testing SSH to ${BOLD}%s${RESET}...\n" "$REMOTE_HOST"
            if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$REMOTE_HOST" true 2>/dev/null; then
                printf "  ${RED}Cannot reach %s. Check SSH config.${RESET}\n" "$REMOTE_HOST"
                return 1
            fi
            printf "  Pushing SA key (one-time operation)...\n"
            scp "$ADC_PATH" "${REMOTE_HOST}:~/sa-key.json" || return 1
            printf "  ${GREEN}SA key pushed.${RESET} This does not need to be repeated — SA keys don't expire.\n"
            ;;

        check)
            echo ""
            printf "  ${BOLD}Credential check${RESET}\n\n"
            if [ "${CLAUDE_CODE_USE_VERTEX:-}" = "1" ]; then
                printf "  Provider: ${GREEN}Vertex AI${RESET}\n"
                if [ -f "$ADC_PATH" ]; then
                    printf "  ${GREEN}SA key present:${RESET} %s\n" "$ADC_PATH"
                    printf "  SA keys don't expire — no refresh needed.\n"
                else
                    printf "  ${RED}SA key not found:${RESET} %s\n" "$ADC_PATH"
                    printf "  Place your service account key at %s\n" "$ADC_PATH"
                fi
                if [ "${GOOGLE_APPLICATION_CREDENTIALS:-}" = "$ADC_PATH" ]; then
                    printf "  ${GREEN}ADC bound to SA key${RESET} (GOOGLE_APPLICATION_CREDENTIALS set)\n"
                else
                    printf "  ${RED}ADC NOT bound to SA key${RESET} — GOOGLE_APPLICATION_CREDENTIALS=%s\n" "${GOOGLE_APPLICATION_CREDENTIALS:-(unset)}"
                    printf "  Re-run ${BOLD}claude-provider vertex${RESET} to bind it (else auth falls back to expiring OAuth ADC).\n"
                fi
            elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
                printf "  Provider: ${YELLOW}API key${RESET}\n"
                case "$ANTHROPIC_API_KEY" in
                    sk-ant-*) printf "  ${GREEN}Key format: valid (sk-ant-...)${RESET}\n" ;;
                    *)        printf "  ${RED}Key format: unexpected — missing sk-ant- prefix${RESET}\n" ;;
                esac
            else
                printf "  Provider: ${BOLD}Claude Max${RESET} (subscription)\n"
                printf "  No credentials to check — uses OAuth.\n"
                printf "  If auth fails, run: ${BOLD}claude login${RESET}\n"
            fi
            echo ""
            ;;

        probe)
            # Read sentinel health verdicts from haak.db.
            local _haak_db="${HAAK_ROOT:-$HOME/Projects/haak}/infra/var/haak.db"
            echo ""
            printf "  ${BOLD}Model health (from sentinel)${RESET}\n\n"
            if [ ! -f "$_haak_db" ]; then
                printf "  ${YELLOW}No haak.db at %s — sentinel not running.${RESET}\n\n" "$_haak_db"
                return
            fi
            if ! command -v sqlite3 >/dev/null 2>&1; then
                printf "  ${RED}sqlite3 not found.${RESET}\n\n"
                return
            fi
            # Show per-provider health summary
            local _results
            _results=$(sqlite3 -separator '|' "$_haak_db" \
                "SELECT provider, alias, model_id, status, COALESCE(error_class,'—'), COALESCE(error_msg,''), COALESCE(verified_at,'never'), COALESCE(failed_at,'never') FROM model_registry ORDER BY provider, alias" 2>/dev/null)
            if [ -z "$_results" ]; then
                printf "  ${YELLOW}No models in registry.${RESET}\n\n"
                return
            fi
            printf "  %-10s %-8s %-28s %-12s %-12s %s\n" "PROVIDER" "ALIAS" "MODEL" "STATUS" "ERROR" "LAST OK"
            printf "  %-10s %-8s %-28s %-12s %-12s %s\n" "--------" "-----" "-----" "------" "-----" "-------"
            echo "$_results" | while IFS='|' read -r _p _a _m _s _ec _em _v _f; do
                local _color="$GREEN"
                case "$_s" in
                    active) _color="$GREEN" ;;
                    failed|auth_failed) _color="$RED" ;;
                    *) _color="$YELLOW" ;;
                esac
                printf "  %-10s %-8s %-28s ${_color}%-12s${RESET} %-12s %s\n" "$_p" "$_a" "$_m" "$_s" "$_ec" "${_v:0:19}"
            done
            echo ""
            ;;

        help|*)
            echo ""
            printf "  ${BOLD}claude-provider${RESET} — Claude Code provider switching\n\n"
            printf "  ${BOLD}Usage:${RESET}\n"
            printf "    claude-provider status         Show current provider + env vars\n"
            printf "    claude-provider vertex         Switch to Vertex AI (%s / %s)\n" "$GCP_PROJECT" "$GCP_REGION"
            printf "    claude-provider apikey [KEY]   Switch to API key auth\n"
            printf "    claude-provider max            Switch to Claude Max (subscription)\n"
            printf "    claude-provider ollama [URL]   Switch to Ollama (local LLM)\n"
            printf "    claude-provider probe          Show sentinel model health verdicts\n"
            printf "    claude-provider fix            Check SA key (no reauth needed)\n"
            printf "    claude-provider push           scp SA key to %s (one-time)\n" "$REMOTE_HOST"
            printf "    claude-provider check          Validate current credentials\n"
            printf "    claude-provider help           Show this message\n\n"
            printf "  ${BOLD}Alias:${RESET} cprov\n\n"
            ;;
    esac
}

alias cprov=claude-provider

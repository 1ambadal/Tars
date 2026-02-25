#!/usr/bin/env bash

# --- CONFIGURATION ---
DEFAULT_MODEL="gemini-2.5-flash-lite"
PRO_MODEL="gemini-2.5-flash"

# 1. SETUP: Check API Key
if [ -z "$GEMINI_API_KEY" ]; then
    echo "Error: GEMINI_API_KEY environment variable not set."
    echo "Get a free key here: https://aistudio.google.com/app/apikey"
    exit 1
fi

# --- ARGUMENT PARSING & MODEL SWITCHER ---
MODEL="$DEFAULT_MODEL"
ARGS=()
for arg in "$@"; do
    if [ "$arg" == "--pro" ]; then
        MODEL="$PRO_MODEL"
    else
        ARGS+=("$arg")
    fi
done
set -- "${ARGS[@]}"

# --- INPUT HANDLING & PIPE SUPPORT ---
STDIN_DATA=""
if [ -p /dev/stdin ]; then
    STDIN_DATA=$(cat)
fi

# Combine into single query string safely
if [ -n "$STDIN_DATA" ]; then
    USER_QUERY="$*
$STDIN_DATA"
else
    USER_QUERY="$*"
fi

if [ -z "$USER_QUERY" ]; then
    echo "Usage: tars [question]"
    exit 1
fi

# 🎨 Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: 'jq' is not installed.${NC}"
    exit 1
fi
if ! command -v curl &> /dev/null; then
    echo -e "${RED}Error: 'curl' is not installed.${NC}"
    exit 1
fi

# Context Awareness
OS_INFO=$(uname -s)
SHELL_INFO=$(basename "$SHELL")
CURRENT_DIR=$(pwd)

# --- LOADING SPINNER ---
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Construct System Prompt for JSON response
read -r -d '' SYSTEM_PROMPT <<EOF
You are a command line expert on $OS_INFO using $SHELL_INFO.
Current Working Directory: $CURRENT_DIR

Return ONLY a valid JSON object with the following structure:
{
  "command": "the bash command",
  "explanation": "short simple explanation",
  "is_dangerous": true/false
}

Rules:
1. Provide the single best command. IF the user is asking for an explanation of code/text and no bash command is needed, return an empty string "" for the command field.
2. No markdown formatting in the JSON values.
3. is_dangerous should be true for destructive/irreversible actions.

User question: $USER_QUERY
EOF

# 🚀 Create JSON Payload
JSON_PAYLOAD=$(jq -n --arg text "$SYSTEM_PROMPT" '{contents: [{parts: [{text: $text}]}]}')

# 📡 Call Gemini API (with spinner)
(curl -s "https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${GEMINI_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD" > /tmp/gemini_res.json) &

spinner $!
RESPONSE=$(cat /tmp/gemini_res.json)

# 🔍 Parse Response
ERROR_MSG=$(echo "$RESPONSE" | jq -r '.error.message // empty')
if [ -n "$ERROR_MSG" ]; then
    echo -e "${RED}API Error:${NC} $ERROR_MSG"
    exit 1
fi

# Extract JSON from the AI's text response (handling potential markdown wrappers)
RAW_CONTENT=$(echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text')
# Clean potential markdown backticks if AI ignores instructions
CLEAN_JSON=$(echo "$RAW_CONTENT" | sed 's/```json//g' | sed 's/```//g')

COMMAND=$(echo "$CLEAN_JSON" | jq -r '.command // empty')
EXPLANATION=$(echo "$CLEAN_JSON" | jq -r '.explanation // empty')
IS_DANGEROUS=$(echo "$CLEAN_JSON" | jq -r '.is_dangerous // false')

if [ -z "$COMMAND" ] && [ -z "$EXPLANATION" ]; then
    echo -e "\n${YELLOW}⚠️  The AI response was unparseable:${NC}"
    echo "$RAW_CONTENT"
    exit 1
fi

# 🚨 Risk Detection
if [ "$IS_DANGEROUS" = "true" ]; then
    echo -e "\n${RED}${BOLD}⚠️  WARNING: POTENTIALLY DANGEROUS COMMAND DETECTED! ⚠️${NC}"
fi

# --- SUDO AWARENESS ---
REQUIRES_SUDO=0
[[ "$COMMAND" == sudo* ]] && REQUIRES_SUDO=1

# 🖨️ Output
if [ -n "$COMMAND" ]; then
    echo -e "\n${CYAN}${BOLD}💻 COMMAND${NC}"
    echo -e "${GREEN}$COMMAND${NC}"
    [ $REQUIRES_SUDO -eq 1 ] && echo -e "${RED}(Requires sudo privileges)${NC}"

    echo -e "\n${CYAN}${BOLD}📘 EXPLANATION${NC}"
    echo -e "$EXPLANATION"

    # --- INTERACTIVE EXECUTE & ALIAS ---
    if [ "$IS_DANGEROUS" = "true" ]; then
        echo -e "\nIf you need to run this, copy it manually."
        exit 0
    fi

    echo -e "\n${BOLD}Options:${NC}"
    echo -e "[E]xecute  [A]lias  [Q]uit"
    read -n 1 -r -p "> " ACTION < /dev/tty
    echo ""

    case "$ACTION" in
        e|E)
            eval "$COMMAND"
            ;;
        a|A)
            read -p "Enter alias name: " ALIAS_NAME < /dev/tty
            RC_FILE=""
            [[ "$SHELL" == */zsh ]] && RC_FILE="$HOME/.zshrc"
            [[ "$SHELL" == */bash ]] && RC_FILE="$HOME/.bashrc"
            
            if [[ -n "$ALIAS_NAME" && -n "$RC_FILE" ]]; then
                echo "alias $ALIAS_NAME='$COMMAND'" >> "$RC_FILE"
                echo -e "${GREEN}Alias '$ALIAS_NAME' added to $RC_FILE${NC}"
                echo "Restart shell or run: source $RC_FILE"
            fi
            ;;
        *)
            echo "Aborted."
            ;;
    esac
else
    # 🖨️ Explanation-Only Output
    echo -e "\n${CYAN}${BOLD}📘 EXPLANATION${NC}"
    echo -e "$EXPLANATION\n"
fi

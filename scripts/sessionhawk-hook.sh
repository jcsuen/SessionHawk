#!/bin/bash

# sessionhawk-hook.sh
# Sourced in shell config (.zshrc or .bashrc) to monitor agent actions and report to SessionHawk.

SH_PORT=9422
SH_URL="http://localhost:9422/v1/event"

# Detect shell type
if [ -n "$ZSH_VERSION" ]; then
    SHELL_TYPE="zsh"
elif [ -n "$BASH_VERSION" ]; then
    SHELL_TYPE="bash"
else
    SHELL_TYPE="sh"
fi

# Function to auto-detect provider from command
detect_provider() {
    local cmd="$1"
    if [[ "$cmd" == *"claude"* ]]; then
        echo "claude"
    elif [[ "$cmd" == *"gemini"* ]]; then
        echo "gemini"
    elif [[ "$cmd" == *"cursor"* ]]; then
        echo "cursor"
    elif [[ "$cmd" == *"codex"* ]]; then
        echo "codex"
    else
        echo "custom"
    fi
}

# Function to escape JSON string values
escape_json() {
    local value="$1"
    # Replace backslashes, quotes, and control chars for safe JSON
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    echo "$value"
}

# Send event to SessionHawk
send_cw_event() {
    local state="$1"
    local cmd="$2"
    local provider=$(detect_provider "$cmd")
    
    local esc_cmd=$(escape_json "$cmd")
    local esc_dir=$(escape_json "$PWD")
    local esc_title=$(escape_json "${TERMINAL_TITLE:-ShellSession}")
    
    # Send event asynchronously so it never slows down the terminal prompt
    (
        curl -s -X POST "$SH_URL" \
            -H "Content-Type: application/json" \
            -d @- <<EOF >/dev/null 2>&1 &
{
  "pid": $$,
  "provider": "$provider",
  "state": "$state",
  "terminalTitle": "$esc_title",
  "workingDirectory": "$esc_dir",
  "commandLine": "$esc_cmd"
}
EOF
    )
}

# Register Hooks
if [ "$SHELL_TYPE" = "zsh" ]; then
    # Zsh Hooks
    sessionhawk_preexec() {
        # Active execution started
        send_cw_event "working" "$1"
    }
    
    sessionhawk_precmd() {
        # Prompt returned, waiting for input
        send_cw_event "waitingForInput" ""
    }
    
    # Append hooks if not already registered
    if [[ ! " ${preexec_functions[*]} " =~ " sessionhawk_preexec " ]]; then
        preexec_functions+=(sessionhawk_preexec)
    fi
    if [[ ! " ${precmd_functions[*]} " =~ " sessionhawk_precmd " ]]; then
        precmd_functions+=(sessionhawk_precmd)
    fi
    
elif [ "$SHELL_TYPE" = "bash" ]; then
    # Bash hooks: PROMPT_COMMAND for waitingForInput, a DEBUG trap for the
    # preexec-equivalent "working" signal (bash has no native preexec). The
    # at-prompt flag limits the trap to the first command after each prompt.
    sessionhawk_bash_precmd() {
        SESSIONHAWK_AT_PROMPT=1
        send_cw_event "waitingForInput" ""
    }

    sessionhawk_bash_preexec() {
        [ -n "$COMP_LINE" ] && return                       # tab completion, not execution
        # DEBUG fires once per PROMPT_COMMAND component — skip all of them
        [[ ";$PROMPT_COMMAND;" == *";$BASH_COMMAND;"* ]] && return
        [[ "$BASH_COMMAND" == sessionhawk_* ]] && return
        [ -n "$SESSIONHAWK_AT_PROMPT" ] || return
        SESSIONHAWK_AT_PROMPT=""
        send_cw_event "working" "$BASH_COMMAND"
    }

    if [[ "$PROMPT_COMMAND" != *"sessionhawk_bash_precmd"* ]]; then
        PROMPT_COMMAND="sessionhawk_bash_precmd;$PROMPT_COMMAND"
        # Note: replaces any existing DEBUG trap — bash allows only one.
        trap 'sessionhawk_bash_preexec' DEBUG
    fi
fi

echo "🟢 SessionHawk shell hook loaded successfully (PID $$)."

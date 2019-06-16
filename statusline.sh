#!/bin/bash
#use tempfile to persist tput output credits:
#https://stackoverflow.com/a/51898464

# bash-preexec.sh -- Bash support for ZSH-like 'preexec' and 'precmd' functions.
# https://github.com/rcaloras/bash-preexec
#
#
# 'preexec' functions are executed before each interactive command is
# executed, with the interactive command as its argument. The 'precmd'
# function is executed before each prompt is displayed.
#
# Author: Ryan Caloras (ryan@bashhub.com)
# Forked from Original Author: Glyph Lefkowitz
#
# V0.3.7
#

if [[ "${__bp_imported:-}" == "defined" ]]; then
    return 0
fi
__bp_imported="defined"

__bp_last_ret_value="$?"
BP_PIPESTATUS=("${PIPESTATUS[@]}")
__bp_last_argument_prev_command="$_"

__bp_inside_precmd=0
__bp_inside_preexec=0

__bp_require_not_readonly() {
  for var; do
    if ! ( unset "$var" 2> /dev/null ); then
      echo "bash-preexec requires write access to ${var}" >&2
      return 1
    fi
  done
}

__bp_adjust_histcontrol() {
    local histcontrol
    histcontrol="${HISTCONTROL//ignorespace}"
    if [[ "$histcontrol" == *"ignoreboth"* ]]; then
        histcontrol="ignoredups:${histcontrol//ignoreboth}"
    fi;
    export HISTCONTROL="$histcontrol"
}

__bp_preexec_interactive_mode=""

__bp_trim_whitespace() {
    local var=$@
    var="${var#"${var%%[![:space:]]*}"}"   # remove leading whitespace characters
    var="${var%"${var##*[![:space:]]}"}"   # remove trailing whitespace characters
    echo -n "$var"
}

__bp_interactive_mode() {
    __bp_preexec_interactive_mode="on";
}
__bp_precmd_invoke_cmd() {
    __bp_last_ret_value="$?" BP_PIPESTATUS=("${PIPESTATUS[@]}")
    if (( __bp_inside_precmd > 0 )); then
      return
    fi
    local __bp_inside_precmd=1

    local precmd_function
    for precmd_function in "${precmd_functions[@]}"; do

        if type -t "$precmd_function" 1>/dev/null; then
            __bp_set_ret_value "$__bp_last_ret_value" "$__bp_last_argument_prev_command"
            "$precmd_function"
        fi
    done
}

__bp_set_ret_value() {
    return ${1:-}
}

__bp_in_prompt_command() {
    local prompt_command_array
    IFS=';' read -ra prompt_command_array <<< "$PROMPT_COMMAND"
    local trimmed_arg
    trimmed_arg=$(__bp_trim_whitespace "${1:-}")
    local command
    for command in "${prompt_command_array[@]:-}"; do
        local trimmed_command
        trimmed_command=$(__bp_trim_whitespace "$command")
        if [[ "$trimmed_command" == "$trimmed_arg" ]]; then
            return 0
        fi
    done
    return 1
}

__bp_preexec_invoke_exec() {
    __bp_last_argument_prev_command="${1:-}"
    if (( __bp_inside_preexec > 0 )); then
      return
    fi
    local __bp_inside_preexec=1
    if [[ ! -t 1 && -z "${__bp_delay_install:-}" ]]; then
        return
    fi

    if [[ -n "${COMP_LINE:-}" ]]; then
        return
    fi
    if [[ -z "${__bp_preexec_interactive_mode:-}" ]]; then
        return
    else
        if [[ 0 -eq "${BASH_SUBSHELL:-}" ]]; then
            __bp_preexec_interactive_mode=""
        fi
    fi

    if  __bp_in_prompt_command "${BASH_COMMAND:-}"; then
        __bp_preexec_interactive_mode=""
        return
    fi

    local this_command
    this_command=$(
        export LC_ALL=C
        HISTTIMEFORMAT= builtin history 1 | sed '1 s/^ *[0-9][0-9]*[* ] //'
    )

    if [[ -z "$this_command" ]]; then
        return
    fi

    local preexec_function
    local preexec_function_ret_value
    local preexec_ret_value=0
    for preexec_function in "${preexec_functions[@]:-}"; do

        if type -t "$preexec_function" 1>/dev/null; then
            __bp_set_ret_value ${__bp_last_ret_value:-}
            "$preexec_function" "$this_command"
            preexec_function_ret_value="$?"
            if [[ "$preexec_function_ret_value" != 0 ]]; then
                preexec_ret_value="$preexec_function_ret_value"
            fi
        fi
    done

    __bp_set_ret_value "$preexec_ret_value" "$__bp_last_argument_prev_command"
}

__bp_install() {
    if [[ "${PROMPT_COMMAND:-}" == *"__bp_precmd_invoke_cmd"* ]]; then
        return 1;
    fi

    trap '__bp_preexec_invoke_exec "$_"' DEBUG

    local prior_trap=$(sed "s/[^']*'\(.*\)'[^']*/\1/" <<<"${__bp_trap_string:-}")
    unset __bp_trap_string
    if [[ -n "$prior_trap" ]]; then
        eval '__bp_original_debug_trap() {
          '"$prior_trap"'
        }'
        preexec_functions+=(__bp_original_debug_trap)
    fi

    __bp_adjust_histcontrol
    if [[ -n "${__bp_enable_subshells:-}" ]]; then

        set -o functrace > /dev/null 2>&1
        shopt -s extdebug > /dev/null 2>&1
    fi;

    PROMPT_COMMAND="__bp_precmd_invoke_cmd; __bp_interactive_mode"

    precmd_functions+=(precmd)
    preexec_functions+=(preexec)

    eval "$PROMPT_COMMAND"
}

__bp_install_after_session_init() {
    if [[ -z "${BASH_VERSION:-}" ]]; then
        return 1;
    fi
    __bp_require_not_readonly PROMPT_COMMAND HISTCONTROL HISTTIMEFORMAT || return
    if [[ -n "$PROMPT_COMMAND" ]]; then
      eval '__bp_original_prompt_command() {
        '"$PROMPT_COMMAND"'
      }'
      precmd_functions+=(__bp_original_prompt_command)
    fi
    PROMPT_COMMAND=$'\n__bp_trap_string="$(trap -p DEBUG)"\ntrap DEBUG\n__bp_install\n'
}

if [[ -z "$__bp_delay_install" ]]; then
    __bp_install_after_session_init
fi;

function is_git_dirty {
    if test -n "$(git status --porcelain)"
    then
        echo "unclean!"
    fi
}

parse_git_to_file() {
    local BRANCH_CHAR=$'\ue0a0'
    local ref=$(git symbolic-ref HEAD 2> /dev/null) || ref="$(git rev-parse     --short HEAD 2> /dev/null)"
    if [ ! -z "$ref" ]
    then
        ref_formatted=${ref/refs\/heads\//$BRANCH_CHAR}
        echo -ne " " $ref_formatted $(is_git_dirty) > "$BOTTOM_LINE_CONTENT_FILE"
    else
        echo -ne "not in git repo" > "$BOTTOM_LINE_CONTENT_FILE"
    fi
}

echo_statusline_value() {
    local SEGMENT_SEPARATOR=$'\ue0b0'
    tput sc
    tput csr 0 $(($(tput lines) - 3))
    tput cup $(tput lines) 0
    tput rev
    echo -n " $(cat ${BOTTOM_LINE_CONTENT_FILE}) "
    tput sgr0
    echo -n $SEGMENT_SEPARATOR
    tput rc
}

draw_statusline() {
    local bottomLinePromptSeq='$(echo_statusline_value)'
    if [[ "$PS1" != *$bottomLinePromptSeq* ]]
    then
        PS1="$bottomLinePromptSeq$PS1"
    fi
    if [ -z "$BOTTOM_LINE_CONTENT_FILE" ]
    then
        export BOTTOM_LINE_CONTENT_FILE="$(mktemp --tmpdir bottom_line.$$.XXX)"
    fi
    parse_git_to_file
    echo_statusline_value
}

precmd() {
    draw_statusline
}

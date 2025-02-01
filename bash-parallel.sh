#!/bin/bash

#Please provide a bash script that takes as piped input multiple lines of bash code.  It will execute these in parallel in the current shell instance, using eval so that it is able to share in-scope environment variables.  It will accept as optional arguments -j or --max-procs (like gnu parallel) to limit how many statements can run in parallel at once; if neither -j nor --max-procs is specified, the default will be equal to the number of real processor cores (if you can limit it to the number of P-cores or performance cores that would be even better).  Each line's output will be logged to a file dedicated to that line, and not to the console; stdout and stderr will be mixed, writing to the same file; the name of the log file will be patterned as <derived_basename>_running.log where derived_basename is the first 50 characters of the output, with any characters that are not legal in both ext4 and ntfs filename replaced with an underscore, and all spaces also replaced with an underscore.  These log files will be placed in a subdirectory called execlog; this subdirectory will be created if it does not exist.  Upon each line completing execution, the log file name will be renamed to <derived_basename>_<exitcode>.log where <exitcode> is the exit code of the line's execution.  The main script will block until all lines are complete and will print a status, updated once a second, of how many lines are not yet completed.  After all lines have exited, it will print a list of the log file paths.   It should be executable on Ubuntu bash or WSL2.

set -euo pipefail

# Determine default max parallel processes (number of physical cores)
if grep -qE "Microsoft|WSL" /proc/version &>/dev/null; then
    default_max_procs=$(nproc --all)
else
    default_max_procs=$(lscpu | awk -F: '/Core\(s\) per socket/{cores=$2} /Socket\(s\)/{sockets=$2} END{print cores * sockets}')
fi
max_procs=$default_max_procs

# Parse optional arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -j|--max-procs)
            max_procs="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

mkdir -p execlog  # Ensure log directory exists

declare -a pids

task() {
    local cmd="$1"
    local derived_basename=$(echo "$cmd" | head -c 50 | tr -c 'A-Za-z0-9_' '_')
    local log_file="execlog/${derived_basename}_running.log"
    eval "$cmd" &> "$log_file"
    local exit_code=$?
    mv "$log_file" "execlog/${derived_basename}_${exit_code}.log"
    return $exit_code
}

exec_tasks() {
    local running=()
    local total=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        while [[ "${#running[@]}" -ge "$max_procs" ]]; do
            sleep 1
            running=( "${running[@]/$(wait -n 2>/dev/null || echo)}" )
        done
        task "$line" &
        running+=( $! )
        ((total++))
    done
    
    while [[ "${#running[@]}" -gt 0 ]]; do
        sleep 1
        running=( "${running[@]/$(wait -n 2>/dev/null || echo)}" )
        echo "Pending tasks: ${#running[@]} of $total remaining..."
    done
    echo "All tasks completed. Log files:"
    ls -1 execlog/
}

exec_tasks

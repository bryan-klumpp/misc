#!/bin/bash
# Please provide a single source script file with a bash script that takes as piped input multiple lines of bash code; the script will execute these lines in parallel as subshells.  Lines can contain multiple statements separated by a semicolon, but each line should be execute as a whole in the subshell.  The script will accept as optional arguments -j or --max-procs (like gnu parallel) to limit how many statements can run in parallel at once; if neither -j nor --max-procs is specified, the default will be equal to the number of real processor cores (if you can limit it to the number of P-cores or performance cores that would be even better).  Each line's output will be logged to a file dedicated to that line, and not to the console; stdout and stderr will be mixed, writing to the same file; the name of the log file will be patterned as <derived_basename>_running.log where derived_basename is the first 50 characters of the output, with any characters that are not legal in both ext4 and ntfs filename replaced with an underscore, and all spaces also replaced with an underscore.  These log files will be placed in a subdirectory called execlog; this subdirectory will be created if it does not exist.  Upon each line completing execution, the log file name will be renamed to <derived_basename>_exitcode<exitcode>.log where <exitcode> is the exit code of the line's subshell execution.  The main script will block until all lines are complete.  Once per second it will clear the console screen and then print the full file names of the contents of the log file directory, followed by "Still running..."   After all lines have exited, it will print a list of the log file paths (fully-qualified file names) for all logs that do not end in "exitcode0.log" It should be executable on Ubuntu bash or WSL2.  Before execution, this script will delete any log files from previous runs.  Include all of this text I've entered in this prompt (with this sentence also) as a single-line comment at the top of the file for documentation and easy updates.

# Create execlog directory if it doesn't exist and clear previous logs
mkdir -p execlog
rm -f execlog/*

# Default number of parallel jobs to the number of processor cores
DEFAULT_JOBS=$(nproc --all)
MAX_PROCS=$DEFAULT_JOBS

# Parse optional arguments
while [[ "$1" =~ ^- && ! "$1" == "--" ]]; do case $1 in
  -j | --max-procs )
    shift; MAX_PROCS=$1
    ;;
esac; shift; done
if [[ "$1" == '--' ]]; then shift; fi

# Function to sanitize filenames
sanitize_filename() {
  echo "$1" | tr -cd '[:alnum:]_.-' | cut -c1-50 | tr ' ' '_'
}

# Read lines of bash code from piped input
LINES=()
while IFS= read -r line; do
  LINES+=("$line")
done

# Execute lines in parallel
PIDS=()
for (( i=0; i<${#LINES[@]}; i++ )); do
  while (( $(jobs -r | wc -l) >= MAX_PROCS )); do
    sleep 1
  done

  {
    LINE="${LINES[$i]}"
    BASENAME=$(sanitize_filename "$LINE")
    LOGFILE="execlog/${BASENAME}_running.log"
    eval "{ $LINE; }" &> "$LOGFILE"
    EXITCODE=$?
    mv "$LOGFILE" "execlog/${BASENAME}_exitcode${EXITCODE}.log"
  } &
  PIDS+=($!)
done

# Monitor and wait for all jobs to complete
while (( ${#PIDS[@]} )); do
  for PID in "${PIDS[@]}"; do
    if ! kill -0 $PID 2>/dev/null; then
      PIDS=(${PIDS[@]/$PID/})
    fi
  done
  clear
  echo "Still running..."
  ls -1 "$(pwd)/execlog"
  sleep 1
done

# Print list of log file paths for logs that do not end in "exitcode0.log"
echo -e "\nExecution complete. Log files with non-zero exit codes:"
find "$(pwd)/execlog" -type f ! -name '*exitcode0.log'
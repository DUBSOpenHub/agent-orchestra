#!/usr/bin/env bash
set +e
"/Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/scripts/copilot-preflight.sh" > "/Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/logs/copilot-preflight.log" 2>&1
code=$?
echo "EXIT:$code" >> "/Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/logs/copilot-preflight.log"
exit "$code"

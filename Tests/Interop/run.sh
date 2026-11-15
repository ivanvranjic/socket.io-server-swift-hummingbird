#!/bin/sh
# Runs the core repo's interop clients (official JS + Swift socket.io clients) against the Hummingbird server.
# Pass --no-swift to skip the Swift client.
set -e
cd "$(dirname "$0")/../.."
CORE=../socket.io-server-swift
swift build --product InteropServer
(cd $CORE/Tests/Interop && [ -d node_modules ] || npm install --silent)

PORT=8099 .build/debug/InteropServer >/dev/null 2>&1 &
PID1=$!
PORT=8098 PING_INTERVAL=0.5 PING_TIMEOUT=0.5 .build/debug/InteropServer >/dev/null 2>&1 &
PID2=$!
trap 'kill $PID1 $PID2 2>/dev/null' EXIT
sleep 2

node $CORE/Tests/Interop/client.mjs http://127.0.0.1:8099
node $CORE/Tests/Interop/ping-timeout.mjs http://127.0.0.1:8098
if [ "$1" != "--no-swift" ]; then
  (cd $CORE/Tests/InteropSwiftClient && swift run -q SwiftClient http://127.0.0.1:8099)
fi

#!/usr/bin/env bash
set -euo pipefail

# Minimal test script to reproduce WAITING_RESTART restart issue
# and verify that manual restart works.

echo "PM2 version (global, from local build):"
pm2 -v || pm2 -v

# Path to fixture
FIXTURE_DIR=/usr/src/app/test/programmatic/fixtures/restart-delay
cd "$FIXTURE_DIR" || exit 1

# Cleanup any existing pm2 processes
pm2 delete all > /dev/null 2>&1 || true

# Start the test app with restart_delay so it will go to WAITING_RESTART after crash
pm2 start wrong.js --restart-delay 500 --name wrongtest

# Wait for status to be waiting restart, poll until found (timeout 5s)
TIMEOUT=5000
INTERVAL=100
elapsed=0
while true; do
  STATUS=$(pm2 jlist | node -e "const fs=require('fs');const data=JSON.parse(fs.readFileSync(0,'utf-8')); const p=data.find(x=>x.name==='wrongtest'); if(!p) process.exit(1); console.log((p && p.pm2_env && p.pm2_env.status) || 'N/A')")
  if [ "$STATUS" = "waiting restart" ]; then
    echo "Process is in WAITING_RESTART"
    break
  fi
  sleep 0.1
  elapsed=$((elapsed+INTERVAL))
  if [ $elapsed -ge $TIMEOUT ]; then
    echo "Timeout waiting for WAITING_RESTART"
    pm2 list
    pm2 show wrongtest
    exit 2
  fi
done

# Show process status
echo "--- pm2 show wrongtest ---"
pm2 show wrongtest || pm2 show wrongtest || true

# Attempt a manual restart using pm_id instead of name
PM_ID=$(pm2 jlist | node -e "const fs=require('fs'); const data=JSON.parse(fs.readFileSync(0,'utf-8')); const p=data.find(x=>x.name==='wrongtest'); if(p && p.pm2_env) { console.log(p.pm2_env.pm_id) } else { process.exit(1) }")

echo "Attempting manual restart (pm_id: $PM_ID)"
pm2 list
set +e
pm2 restart $PM_ID
R=$?
set -e

if [ $R -eq 0 ]; then
  echo "Restart succeeded"
else
  echo "Restart failed with exit code $R"
  pm2 list
  pm2 show wrongtest
  exit $R
fi

# Final status
pm2 list
pm2 show wrongtest

# Do a tidy kill
pm2 kill

exit 0

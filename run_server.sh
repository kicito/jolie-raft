# #!/bin/bash

# TOTAL_SERVERS=$1
# SERVER_ID=$2

# jolie -C SERVER_ID=$SERVER_ID -C LOCAL_PORT=\""socket://localhost:800${SERVER_ID}"\" -C CLIENT_PORT=\""socket://localhost:900${SERVER_ID}"/\" -C RAFT_PORT=\""socket://localhost:1000${SERVER_ID}"\" -C TOTAL_SERVERS=$TOTAL_SERVERS server.ol

TOTAL_SERVERS=$1

RUNNING_NUM=$(($TOTAL_SERVERS - 1))

gnome-terminal -- bash -c "jolie -C TOTAL_SERVERS=$TOTAL_SERVERS monitor.ol ; exec bash" &

for SERVER_ID in `seq 0 ${RUNNING_NUM}`;
  do
  gnome-terminal -- bash -c "jolie -C SERVER_ID=$SERVER_ID -C LOCAL_PORT=\\\"socket://localhost:800${SERVER_ID}\\\" -C CLIENT_PORT=\\\"socket://localhost:900${SERVER_ID}/\\\" -C RAFT_PORT=\\\"socket://localhost:1000${SERVER_ID}\\\" -C TOTAL_SERVERS=$TOTAL_SERVERS server.ol ; exec bash" &
done 


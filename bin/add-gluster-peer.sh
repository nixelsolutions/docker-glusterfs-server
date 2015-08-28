#!/bin/bash

# Exit status = 0 means the peer was successfully joined
# Exit status = 1 means there was an error while joining the peer to the cluster

# NOTE that $PEER is the hostname

set -e

[ "$DEBUG" == "1" ] && set -x && set +e

function echo_output() {
   builtin echo $(basename $0): [From container ${MY_IP}] $1
}

function detach() {
   echo "=> Some error ocurred while trying to add peer ${PEER} to the cluster - detaching it ..."
   gluster peer detach ${PEER} force
   rm -f ${SEMAPHORE_FILE}
   exit 1
}

PEER=$1

if [ -z "${PEER}" ]; then
   echo_output "=> ERROR: I was supposed to add a new gluster peer to the cluster but no IP was specified, doing nothing ..."
   exit 1
fi

GLUSTER_CONF_FLAG=/etc/gluster.env
SEMAPHORE_FILE_DIR=/tmp
SEMAPHORE_FILE_NAME=adding-gluster-node.
SEMAPHORE_FILE=/${SEMAPHORE_FILE_DIR}/${SEMAPHORE_FILE_NAME}${PEER}
SEMAPHORE_TIMEOUT=120
source ${GLUSTER_CONF_FLAG}

# Add PEER to /etc/hosts if it's not already added
PEER_IP=`echo ${PEER} | sed "s/-/\./g"`
if ! grep " ${PEER}$" /etc/hosts >/dev/null; then
   echo "${PEER_IP} ${PEER}" >> /etc/hosts
fi 

echo_output "=> Checking if I can reach gluster container ${PEER} ..."
if sshpass -p ${ROOT_PASSWORD} ssh ${SSH_OPTS} ${SSH_USER}@${PEER} "hostname" >/dev/null 2>&1; then
   echo_output "=> Gluster container ${PEER} is alive"
else
   echo_output "*** Could not reach gluster master container ${PEER} - exiting ..."
   exit 1
fi

# Gluster does not like to add two nodes at once
for ((SEMAPHORE_RETRY=0; SEMAPHORE_RETRY<SEMAPHORE_TIMEOUT; SEMAPHORE_RETRY++)); do
   if [ `find ${SEMAPHORE_FILE_DIR} -name "${SEMAPHORE_FILE_NAME}*" | wc -l` -eq 0 ]; then
      break
   fi
   echo_output "*** There is another container joining the cluster, waiting $((SEMAPHORE_TIMEOUT-SEMAPHORE_RETRY)) seconds ..."
   sleep 1     
done

if [ `find ${SEMAPHORE_FILE_DIR} -name "${SEMAPHORE_FILE_NAME}*" | wc -l` -gt 0 ]; then
   echo_output "*** Error: another container is joining the cluster"
   echo_output "and after waiting ${SEMAPHORE_TIMEOUT} seconds I could not join peer ${PEER}, giving it up ..."
   exit 1
fi
touch ${SEMAPHORE_FILE}

# Check how many peers are already joined in the cluster - needed to add a replica
NUMBER_OF_REPLICAS=`gluster volume info ${GLUSTER_VOL} | grep "Number of Bricks:" | awk '{print $6}'`

# Check if peer container is already part of the cluster
PEER_STATUS=`gluster peer status | grep -A2 "Hostname: ${PEER}$" | grep State: | awk -F: '{print $2}'`
if echo_output "${PEER_STATUS}" | grep "Peer Rejected"; then
   if gluster volume info ${GLUSTER_VOL} | grep ": ${PEER}:${GLUSTER_BRICK_PATH}$" >/dev/null; then
      echo_output "=> Peer container ${PEER} was part of this cluster but must be dropped now ..."
      gluster --mode=script volume remove-brick ${GLUSTER_VOL} replica $((NUMBER_OF_REPLICAS-1)) ${PEER}:${GLUSTER_BRICK_PATH} force
      sleep 5
   fi
      gluster peer detach ${PEER} force
      sleep 5
fi

# Probe the peer
if ! echo_output "${PEER_STATUS}" | grep "Peer in Cluster" >/dev/null; then
    # Peer probe
    echo_output "=> Probing peer ${PEER} ..."
    gluster peer probe ${PEER}
    sleep 5
fi

# Check how many peers are already joined in the cluster - needed to add a replica
NUMBER_OF_REPLICAS=`gluster volume info ${GLUSTER_VOL} | grep "Number of Bricks:" | awk '{print $6}'`
# Create the volume
if ! gluster volume list | grep "^${GLUSTER_VOL}$" >/dev/null; then
   echo_output "=> Creating GlusterFS volume ${GLUSTER_VOL}..."
   MY_IP_HOSTNAME=`echo ${MY_IP} | sed "s/\./-/g"`
   gluster volume create ${GLUSTER_VOL} replica 2 ${MY_IP_HOSTNAME}:${GLUSTER_BRICK_PATH} ${PEER}:${GLUSTER_BRICK_PATH} force || detach
   sleep 1
fi

# Start the volume
if ! gluster volume status ${GLUSTER_VOL} >/dev/null; then
   echo_output "=> Starting GlusterFS volume ${GLUSTER_VOL}..."
   gluster volume start ${GLUSTER_VOL}
   sleep 1
   # Enable quota on this volume
   gluster volume quota ${GLUSTER_VOL} enable 
fi

if ! gluster volume info ${GLUSTER_VOL} | grep ": ${PEER}:${GLUSTER_BRICK_PATH}$" >/dev/null; then
   echo_output "=> Adding brick ${PEER}:${GLUSTER_BRICK_PATH} to the cluster (replica=$((NUMBER_OF_REPLICAS+1)))..."
   gluster volume add-brick ${GLUSTER_VOL} replica $((NUMBER_OF_REPLICAS+1)) ${PEER}:${GLUSTER_BRICK_PATH} force || detach
fi

rm -f ${SEMAPHORE_FILE}
exit 0

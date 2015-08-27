#!/bin/bash

set -e 

[ "$DEBUG" == "1" ] && set -x && set +e

if [ "${GLUSTER_PEERS}" == "**ChangeMe**" -o -z "${GLUSTER_PEERS}" ]; then
   echo "*** ERROR: you need to define GLUSTER_PEERS environment variable - Exiting ..."
   exit 1
fi

if [ "${MY_IP}" == "**ChangeMe**" -o -z "${MY_IP}" ]; then
   echo "*** ERROR: you need to define MY_IP environment variable - Exiting ..."
   exit 1
fi

if [ "${ROOT_PASSWORD}" == "**ChangeMe**" -o -z "${ROOT_PASSWORD}" ]; then
   echo "*** ERROR: you need to define ROOT_PASSWORD environment variable - Exiting ..."
   exit 1
fi

echo "root:${ROOT_PASSWORD}" | chpasswd

# Prepare a shell to initialize docker environment variables for ssh
echo "#!/bin/bash" > ${GLUSTER_CONF_FLAG}
echo "ROOT_PASSWORD=\"${ROOT_PASSWORD}\"" >> ${GLUSTER_CONF_FLAG}
echo "SSH_PORT=\"${SSH_PORT}\"" >> ${GLUSTER_CONF_FLAG}
echo "SSH_USER=\"${SSH_USER}\"" >> ${GLUSTER_CONF_FLAG}
echo "SSH_OPTS=\"${SSH_OPTS}\"" >> ${GLUSTER_CONF_FLAG}
echo "GLUSTER_VOL=\"${GLUSTER_VOL}\"" >> ${GLUSTER_CONF_FLAG}
echo "GLUSTER_BRICK_PATH=\"${GLUSTER_BRICK_PATH}\"" >> ${GLUSTER_CONF_FLAG}
echo "DEBUG=\"${DEBUG}\"" >> ${GLUSTER_CONF_FLAG}
echo "MY_IP=\"${MY_IP}\"" >> ${GLUSTER_CONF_FLAG}

join-gluster.sh &
/usr/bin/supervisord

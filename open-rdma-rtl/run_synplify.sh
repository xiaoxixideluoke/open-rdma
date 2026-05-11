#! /bin/sh

set -o errexit
set -o nounset
set -o xtrace

# xauth info
# xauth list
XAUTHORITY_FILE=`xauth info | grep Authority | awk '{print $3}'`

WORK_DIR=/root/work
ACE_DIR_HOST=$HOME/Downloads/Achronix-linux
ACE_DIR=/tools/Achronix-linux/
    #--entrypoint /tools/synopsys/linux64/bin/start.sh \
docker run --rm -it \
    -e DEBIAN_FRONTEND=noninteractive \
    -e DISPLAY \
    -e ACE_INSTALL_DIR=$ACE_DIR \
    -v /tmp/.X11-unix/:/tmp/.X11-unix/:ro \
    --mount type=bind,source=$XAUTHORITY_FILE,target=/root/.Xauthority,readonly \
    --hostname `hostname` \
    --mac-address 3c:ec:ef:78:f1:9e \
    -v $ACE_DIR_HOST:$ACE_DIR \
    -v $PWD:$WORK_DIR \
    -w $WORK_DIR \
    synplify:achronix /tools/synopsys/linux64/bin/start.sh $@

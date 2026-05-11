
trap "kill 0" SIGINT

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

echo $SCRIPT_DIR

# 编译 rust driver
DTLD_DIR=$SCRIPT_DIR/../../../dtld-ibverbs
cd $DTLD_DIR
cargo build --no-default-features --features=mock


mkdir -p $SCRIPT_DIR/../log/mock
LOG_DIR=$(cd "$SCRIPT_DIR/../log/mock" && pwd)

cd $SCRIPT_DIR/..

echo $(pwd)

make

make nompi_hack_rank0 &> $LOG_DIR/rccl-1.log &
make nompi_hack_rank1 &> $LOG_DIR/rccl-2.log &



# make nompi_hack_rank0 &
# make nompi_hack_rank1 &
wait


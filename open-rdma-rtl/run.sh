#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o xtrace

BASH_PROFILE=$HOME/.bash_profile
if [ -f "$BASH_PROFILE" ]; then
    source $BASH_PROFILE
fi

TEST_DIR=`realpath ./test`
LOG_DIR=`realpath ./tmp`
ALL_LOG=$TEST_DIR/run.log

mkdir -p $LOG_DIR
cd $TEST_DIR
echo "" > $ALL_LOG

make -j8 TESTFILE=TestAddressChunker.bsv TOPMODULE=mkTestAddressChunker 2>&1 | tee -a $ALL_LOG

make -j8 TESTFILE=TestButterflyMerge.bsv TOPMODULE=mkTestFourChannelButterflyMergeCreateInstance 2>&1 | tee -a $ALL_LOG
make -j8 TESTFILE=TestButterflyMerge.bsv TOPMODULE=mkTestFourChannelButterflyMergeSingleBeatTest 2>&1 | tee -a $ALL_LOG

make -j8 TESTFILE=TestEthernetFrameIO.bsv TOPMODULE=mkTestEthernetFrameIO 2>&1 | tee -a $ALL_LOG

make -j8 TESTFILE=TestFullyPipelinedUpdateBram.bsv TOPMODULE=mkTestFullyPipelinedUpdateBram 2>&1 | tee -a $ALL_LOG

make -j8 TESTFILE=TestPacketGenAndParse.bsv TOPMODULE=mkTestPacketGen 2>&1 | tee -a $ALL_LOG

make -j8 TESTFILE=TestPayloadGenAndCon.bsv TOPMODULE=mkTestPayloadGenAndCon 2>&1 | tee -a $ALL_LOG

make -j8 TESTFILE=TestStreamShifter.bsv TOPMODULE=mkTestBiDirectionStreamShifter 2>&1 | tee -a $ALL_LOG

make -j8 TESTFILE=TestPsnContinousChecker.bsv TOPMODULE=mkTestCpsnCounter 2>&1 | tee -a $ALL_LOG



# make -j8 -f Makefile.test all TESTDIR=$TEST_DIR LOGDIR=$LOG_DIR
# cat $LOG_DIR/*.log | tee $ALL_LOG

FAIL_KEYWORKS='Error\|ImmAssert\|ImmFail'
grep -w $FAIL_KEYWORKS $LOG_DIR/*.log | cat
ERR_NUM=`grep -c -w $FAIL_KEYWORKS $ALL_LOG | cat`
if [ $ERR_NUM -gt 0 ]; then
    echo "FAIL"
    false
else
    echo "PASS"
fi

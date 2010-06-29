#!/bin/sh
#
# Helper script to pipe the SMSG payload into the Baracus FIFO
#

BARACUS_FIFO="/tmp/.Baracus-zVM"

echo $1 $2 $3 >> $BARACUS_FIFO

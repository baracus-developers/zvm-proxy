#!/bin/sh
#
# Helper script to pipe the SMSG payload into the Baracus FIFO
#

BARACUS_FIFO="/var/run/bazvmproxy.fifo"

echo $1 $2 $3 >> $BARACUS_FIFO

#!/bin/bash


fio --name=fio-rand-readwrite --filename=/dev/rbdblock --readwrite=randrw --bs=4K --direct=1 --numjobs=1 --time_based=1 --runtime=60 --size=4G --iodepth=4 --invalidate=1 --fsync_on_close=1 --rwmixread=75 --ioengine=libaio --rate=4k --rate_process=poisson --output-format=json &> /dev/null


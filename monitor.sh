#!/bin/bash

# A script to gather various instance performance metrics and push them to CloudWatch

INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

USED_MEMORY=$(free -m | awk 'NR==2{printf "%.2f\t", $3*100/$2 }')
TCP_CONN=$(netstat -t | tail -n +2 | wc -l)
TCP_CONN_HTTP=$(netstat -t | tail -n +2 | grep http | wc -l)
TCP_CONN_SSH=$(netstat -t | tail -n +2 | grep ssh | wc -l)
IO_WAIT=$(iostat | awk 'NR==4 {print $4}')
CPU_STEAL=$(iostat | awk 'NR==4 {print $5}')
AVAILABLE_VIRTUAL_STORAGE=$(printf %.3f `echo $(df | awk '$1 == "/dev/xvda1" {print $4}') / 1000000 | bc -l`)

MEMORY_BOTTLENECK=0
if [[ $IO_WAIT > 70 && $USEDMEMORY > 80 ]]; then
  MEMORY_BOTTLENECK=1
fi

MULTIPLE_SSH_CONNECTIONS=0
if [[ $TCP_CONN_SSH > 1 ]]; then
  MULTIPLE_SSH_CONNECTIONS=1
fi

LOW_VIRTUAL_STORAGE=0
if [[ $AVAILABLE_VIRTUAL_STORAGE < 2 ]]; then
  LOW_VIRTUAL_STORAGE=1
fi

aws cloudwatch put-metric-data --metric-name memory_usage --dimensions Instance=$INSTANCE_ID --namespace "Custom" --value $USED_MEMORY
aws cloudwatch put-metric-data --metric-name tcp_connections --dimensions Instance=$INSTANCE_ID --namespace "Custom" --value $TCP_CONN
aws cloudwatch put-metric-data --metric-name tcp_connections_http --dimensions Instance=$INSTANCE_ID --namespace "Custom" --value $TCP_CONN_HTTP
aws cloudwatch put-metric-data --metric-name tcp_connections_ssh --dimensions Instance=$INSTANCE_ID --namespace "Custom" --value $TCP_CONN_SSH
aws cloudwatch put-metric-data --metric-name io_wait --dimensions Instance=$INSTANCE_ID --namespace "Custom" --value $IO_WAIT
aws cloudwatch put-metric-data --metric-name cpu_steal --dimensions Instance=$INSTANCE_ID --namespace "Custom" --value $CPU_STEAL
aws cloudwatch put-metric-data --metric-name available_virtual_storage --dimensions Instance=$INSTANCE_ID --namespace "Custom" --value $AVAILABLE_VIRTUAL_STORAGE
aws cloudwatch put-metric-data --metric-name memory_bottleneck --dimensions Instance=$INSTANCE_ID --namespace "Custom" --value $MEMORY_BOTTLENECK
aws cloudwatch put-metric-data --metric-name multiple_ssh_connections --dimensions Instance=$INSTANCE_ID --namespace "Custom" --value $MULTIPLE_SSH_CONNECTIONS
aws cloudwatch put-metric-data --metric-name low_virtual_storage --dimensions Instance=$INSTANCE_ID --namespace "Custom" --value $LOW_VIRTUAL_STORAGE

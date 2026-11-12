#!/bin/bash
#Usage: getLastOSPartition.sh PathToManagedDisk

if (( "$#" != 1 ))
then
  echo "Error: the path the managed disk is required"
  exit 1
fi

pathToManagedDisk="$1"

lsblk -lnpo PATH,TYPE,PKNAME | awk -v d="$pathToManagedDisk" '$2 == "part" && $3 == d { print $1 }' | sort -V | tail -n 1

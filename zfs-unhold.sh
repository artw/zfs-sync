#!/bin/sh

if [ -z "$1" -o "-h" == "$1" ]; then
  echo "Release all holds on all snapshots recursively in a dataset"
  echo "	usage $0 <dataset>"
  return 1
fi

fs=$1

for snap in $(zfs list -Hp -o name -t snapshot -r $fs | sort); do
  for hold in $(zfs holds -H -r $snap | sed -e "s/\t/;/g" -e "s/ //g"); do
    s=$(echo $hold | cut -d ";" -f 1)
    t=$(echo $hold | cut -d ";" -f 2)
    zfs release -r $t $s 
  done
done

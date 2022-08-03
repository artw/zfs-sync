#!/bin/sh
set -e  # exit on any error
if [ -z "$1" -o -z "$2" -o "-h" == "$1" ]; then
  echo "usage $0: <config_file> <snapshot_name_prefix> [snapshots_to_keep]"
  exit 1
fi


if [ -f $1 ]; then
  CONFIGFILE=$1
  . $CONFIGFILE
else
  echo "specify the config file as the first argument"
fi

SNAP_PREFIX=$2

if [ "$3" -gt 0 ]; then
  KEEP_SNAPS=$3
fi

if [ -z "$FSMAP" ]; then
 echo "FSMAP is a required property"
 exit 1
fi

if [ -z "$DEST_NAME" ]; then
 echo "DEST_NAME is a required property"
 exit 1
fi

## defaults
test -z "$SEND_ARGS"      && SEND_ARGS="-Re"
test -z "$RECV_ARGS"      && RECV_ARGS="-vFu -o canmount=off"
test -z "$LAST_SNAP_PROP" && LAST_SNAP_PROP="lv.make.zfs.sync.${DEST_NAME}:last_synced_snapshot"
test -z "$KEEP_SNAPS"     && KEEP_SNAPS=5
test -z "$LOCKFILE"       && LOCKFILE="/var/tmp/zfs-sync.lock"

if [ -e $LOCKFILE ]; then
  echo "Lock file $LOCKFILE exists, can't start"
  exit 1
else
  touch $LOCKFILE
fi


for fs in $FSMAP; do
  src=$(echo $fs | cut -d ":" -f 1)
  dst=$(echo $fs | cut -d ":" -f 2)
  last_snap=$(zfs get -Hp -o value $LAST_SNAP_PROP $src)
  # incremental stream only if there is a previous snap
  if [ "-" != "$last_snap" ]; then
    last_snap_name=${src}@${last_snap}
    incr="-I $last_snap_name"
  else 
    last_snap_name=""
    incr=""
  fi
  new_snap="${DEST_NAME}:${SNAP_PREFIX}:$(date +%Y-%m-%d_%H:%M:%S)"
  new_snap_name=${src}@${new_snap}

  echo "==> Creating recursive snapshot $new_snap_name"
  $SRC_PREFIX zfs snapshot -r $new_snap_name
  echo ""

  echo "==> Replicating [ $src ] to [ $dst ]"
  $SRC_PREFIX zfs send $SEND_ARGS $incr $new_snap_name | \
  $DEST_PREFIX zfs recv $RECV_ARGS $dst \
  && $SRC_PREFIX zfs set $LAST_SNAP_PROP=$new_snap $src
  echo ""

  echo "==> Deleting extra snaps"
  i=0
  for snap in $(${SRC_PREFIX} zfs list -Hp -o name -t snapshot -r -d 1 $src | sort -r | grep @${DEST_NAME}:${SNAP_PREFIX}: | grep -v $new_snap ); do
    i=$(($i+1))
    if [ $i -gt $KEEP_SNAPS ]; then
      echo "deleting $snap"
      $SRC_PREFIX zfs destroy -r $snap
    fi
  done
  echo ""
done;
rm $LOCKFILE

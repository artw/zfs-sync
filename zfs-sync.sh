#!/bin/sh
if [ -z "$1" -o "-h" == "$1" ]; then
  echo "usage $0: <snapshot_name_prefix> [snapshots_to_keep]"
  exit 1
fi
SNAP_PREFIX=$1

CONFIGFILE=zfs-sync.conf
if [ -f $CONFIGFILE ]; then
  . $CONFIGFILE
fi

if [ -z "$DEST_HOST" ]; then 
  echo "DEST_HOST is a required property"
  exit 1
fi

if [ -z "$FSMAP" ]; then
 echo "FSMAP is a required property"
 exit 1
fi

test -z "$SEND_ARGS"      && SEND_ARGS="-Re"
test -z "$RECV_ARGS"      && RECV_ARGS="-vFu"
test -z "$LAST_SNAP_PROP" && LAST_SNAP_PROP="lv.make:last_sync_snap"
test -z "$KEEP_SNAPS"     && KEEP_SNAPS=5
test -z "$LOCKFILE"       && LOCKFILE="/var/tmp/zfs-sync.lock"

if [ -e $LOCKFILE ]; then
  echo "Lock file $LOCKFILE exists, can't start"
  exit 1
else
  touch $LOCKFILE
fi

if [ "$2" -gt 0 ]; then
  KEEP_SNAPS=$2
fi

ssh_args=$DEST_HOST
test -z "$DEST_LOGIN" || ssh_args="${DEST_LOGIN}@${ssh_args}"
test -f "$DEST_KEY" && ssh_args="$ssh_args -i $DEST_KEY"

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
  new_snap="${SNAP_PREFIX}_$(date +%Y-%m-%d_%H:%M:%S)"
  new_snap_name=${src}@${new_snap}

  echo "==> Creating snapshot $new_snap_name"
  zfs snapshot -r $new_snap_name
  echo ""


  echo "==> Replicating $src to $dst"
  zfs send $SEND_ARGS $incr $new_snap_name | ssh $ssh_args $DEST_PREFIX zfs recv $RECV_ARGS $dst && zfs set $LAST_SNAP_PROP=$new_snap $src
  echo ""

  echo "==> Deleting extra snaps"
  i=0
  for snap in $(zfs list -Hp -o name -t snapshot -r -d 1 $src | sort -r | grep @${SNAP_PREFIX}_ | grep -v $new_snap ); do
    i=$(($i+1))
    if [ $i -gt $KEEP_SNAPS ]; then
      echo "deleting $snap"
      zfs destroy -r $snap
    fi
  done
  echo ""
done;
rm $LOCKFILE

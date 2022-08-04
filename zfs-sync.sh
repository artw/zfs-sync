#!/bin/sh
set -e  # exit on any error
set -o pipefail  # pipe matters
#set -x  # echo commands

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

if [ -z "$JOB_NAME" ]; then
 echo "JOB_NAME is a required property"
 exit 1
fi

## defaults
test -z "$SEND_ARGS"      && SEND_ARGS="-Re"
test -z "$RECV_ARGS"      && RECV_ARGS="-vFu -o canmount=off"
test -z "$KEEP_SNAPS"     && KEEP_SNAPS=5
test -z "$LAST_SNAP_PROP" && LAST_SNAP_PROP="lv.make.zfs.sync.${JOB_NAME}:last_synced_snapshot"
test -z "$LOCK_PROP"      && LOCK_PROP="lv.make.zfs.sync.${JOB_NAME}:lock"
test -z "$HOLD_TAG_PROP"  && HOLD_TAG_PROP="lv.make.zfs.sync.${JOB_NAME}:hold_tag"
test -z "$FORCE"          && FORCE=0
test -z "$RESET"          && RESET=0

src_host=$( $SRC_PREFIX hostname -s )
dest_host=$( $DEST_PREFIX hostname -s )

zfs="/sbin/zfs"

for fs in $FSMAP; do
  src=$(echo $fs | cut -d ":" -f 1)
  dest=$(echo $fs | cut -d ":" -f 2)

  # force open locks
  if [ $FORCE -gt 0 -o $RESET -gt 0 ]; then
    $SRC_PREFIX $zfs inherit $LOCK_PROP $src
    $DEST_PREFIX $zfs inherit $LOCK_PROP $dest
  else
    # check if already locked
    src_locked=$( $SRC_PREFIX $zfs get -Hp -o value $LOCK_PROP $src )
    dest_locked=$( $DEST_PREFIX $zfs get -Hp -o value $LOCK_PROP $dest )

    if [ "-" != "$src_locked" ]; then
      echo "(!) [ $src ] is locked by [$src_locked]"
      echo "run this to unlock: "
      echo "$SRC_PREFIX $zfs inherit $LOCK_PROP $src"
      return 1
    elif [ "-" != "$dest_locked" ]; then
      echo "(!) [ $dest ] is locked by [$dest_locked]"
      echo "run this to unlock: "
      echo "$DEST_PREFIX $zfs inherit $LOCK_PROP $dest"
      return 1
    fi
  fi

  # reset metadata
  if [ $RESET -gt 0 ]; then
    $SRC_PREFIX $zfs inherit $LAST_SNAP_PROP $src
    $DEST_PREFIX $zfs inherit $LAST_SNAP_PROP $dest
  fi

  # locking fs
  lock="${src_host}:${src}__${dest_host}:${dest}__$$"
  $SRC_PREFIX $zfs set ${LOCK_PROP}=${lock} $src
  $DEST_PREFIX $zfs set ${LOCK_PROP}=${lock} $dest

  last_snap_src=$( $SRC_PREFIX $zfs get -Hp -o value $LAST_SNAP_PROP $src )
  last_snap_dest=$( $DEST_PREFIX $zfs get -Hp -o value $LAST_SNAP_PROP $dest )

  if [ "-" != "$last_snap_src" ]; then
    hold_tag_src=$( $SRC_PREFIX $zfs get -Hp -o value $HOLD_TAG_PROP ${src}@${last_snap_src} )
  else 
    hold_tag_src=""
  fi

  if [ "-" != "$last_snap_dest" ]; then
    hold_tag_dest=$( $dest_PREFIX $zfs get -Hp -o value $HOLD_TAG_PROP ${src}@${last_snap_dest} )
  else 
    hold_tag_dest=""
  fi

  # generate incremental stream only if there is a previous snap
  if [ "$last_snap_dest" == "$last_snap_src" -a "$last_snap_src" != "-" ]; then
    incr="-I $last_snap_src"  # will be appended to zfs send
  else
    echo "snapshot metadata mismatch"
    incr=""
  fi

  new_snap="${JOB_NAME}:${SNAP_PREFIX}:$(date +%Y-%m-%d_%H:%M:%S)"
  new_snap_src=${src}@${new_snap}
  new_snap_dest=${dest}@${new_snap}

  echo "==> Creating and holding new recursive snapshot [ $new_snap_src ]"
  $SRC_PREFIX $zfs snapshot -r $new_snap_src
  $SRC_PREFIX $zfs hold -r $lock $new_snap_src
  echo ""


  echo "==> Replicating [ ${src_host}:${src} ] to [ ${dest_host}:${dest} ]"
  $SRC_PREFIX $zfs send $SEND_ARGS $incr $new_snap_src | \
  $DEST_PREFIX $zfs recv $RECV_ARGS $dest \
  && $SRC_PREFIX $zfs set $LAST_SNAP_PROP=$new_snap $src \
  && $DEST_PREFIX $zfs set $LAST_SNAP_PROP=$new_snap $dest
  echo ""

  echo "==> Hold the new snap on dest [ $new_snap_dest ]"
  $DEST_PREFIX $zfs hold -r $lock $new_snap_dest
  echo ""

  echo "==> Unlocking [ ${src_host}:${src} ] and releasing previous snapshot"
  $SRC_PREFIX $zfs inherit ${LOCK_PROP} $src
  $DEST_PREFIX $zfs inherit ${LOCK_PROP} $dest
  
  if [ "-" != "$last_snap_src" -a "-" != "$hold_tag_src" ]; then
    $SRC_PREFIX $zfs release -r $hold_tag_src ${src}@${last_snap_src}
  fi

  if [ "-" != "$last_snap_dest" -a "-" != "$hold_tag_dest" ]; then
    $DEST_PREFIX $zfs release -r $hold_tag_dest ${dest}@${last_snap_dest}
  fi

  echo "==> Cleaning up extra snaps on ${src_host}:${src}"
  i=0
  for snap in $(${SRC_PREFIX} $zfs list -Hp -o name -t snapshot -r -d 1 $src | sort -r | grep @${JOB_NAME}:${SNAP_PREFIX}: | grep -v $new_snap ); do
    i=$(($i+1))
    if [ $i -gt $KEEP_SNAPS ]; then
      echo "deleting $snap"
      $SRC_PREFIX $zfs destroy -r $snap
    fi
  done
  echo ""
done;

# zfs-sync
## yet another zfs replication script
This thing syncronizes two ZFS dataset trees (or standalone datasets) using zfs send receive. It will save the last sent snapshot in the custom properties on both source and destination and hold the snapshots to prevent accidental deletion. \
\
Both source and destination can be remote or local, you can just prefix whatever commands you need to get to the shell that can run zfs send/recv \
\
You don't need sudo, but can just have required permissions on the source and destionation datasets using `zfs allow` command
- source: `send,destroy,userprop,hold,release`
- destination: `mount,receive,create,destroy,userprop,canmount,mountpoint,hold,release`

Random fails can leave orphaned locking properties, you can set `FORCE=1` for the command to override.\
\
You can nuke all relevant metadata if you set `RESET=1`

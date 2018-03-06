# zfs-sync
###yet another zfs replication script
- Snapshots every local filesystem specified (local/fs:remote/fs) in ```FSMAP```
- Sends the snapshot to corresponding remote filesystem on ```DEST_HOST``` via SSH. Snapshots are labeled using the first argument and date-time-to-seconds, like this ```manual_2018-03-06_23:13:56```. 
- If successful, sets a custom zfs property with the snapshot label
- If launched again with the same prefix, will use the last snapshot as the incremental stream base. 
- Deletes all older snapshots with the same prefix if there are more than `KEEP_SNAPS`. The new snapshot is not counted.

##To use as an automatic backup solution:  
1. configure using self documenting conf file  
2. use sudo on the local site or allow the local user to `snapshot`,`send`, `destroy` using `zfs allow` from root 
3. allow passwordless sudo on the remote site for `zfs` command, using sudoers: `leet ALL=(ALL) ALL, NOPASSWD:/usr/bin/zfs`, or allow user to use `receive` and `zfs destroy` using  `zfs allow` (zfs requires root/sudo on Linux)
4. set up a crontab like this: 
``` 
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
#-Minute (0-59)
# #-Hour (0-23)  
# # #-Day of the month (1-31)
# # # #-Month (1-12)
# # # # #-Weekday (0-6)
# # # # # #-command
0 3 * * * /home/leet/src/zfs-sync/zfs-sync.sh daily 30 >/home/leet/src/zfs-sync/zfs-sync-nuke_daily.log 2>&1
0 3 * * 6 /home/leet/src/zfs-sync/zfs-sync.sh weekly 4 >/home/leet/src/zfs-sync/zfs-sync-nuke_weekly.log 2>&1
0 4 1 * * /home/leet/src/zfs-sync/zfs-sync.sh monthly 6  >/home/leet/src/zfs-sync/zfs-sync-nuke_monthlhy.log 2>&1
```
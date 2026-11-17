# suse_update_timer

Stops and disables `transactional-update.timer` at the start of a play when
`suse_disable_update_timer` is true. On SL Micro the timer is `OnCalendar=daily`,
`RandomizedDelaySec=2h`, `Persistent=true`: once `rke2_setup` or `suse_selinux_policy`
restarts it after their install step, a fresh image catches up within two hours and the
daily update holds the `transactional-update` lock that `zypper` and `rke2-uninstall.sh`
need. Those roles only pause the timer inside blocks that may be skipped (policy already
loaded, SELinux disabled), so the test playbooks run this role first. No-op when the unit
does not exist or the switch is false; BYO callers keep their timer with
`-e suse_disable_update_timer=false`.

| Variable | Default | Description |
|----------|---------|-------------|
| `suse_disable_update_timer` | `false` | Stop and disable the timer for the run |

# SELinux Notes (Fedora/RHEL)

Server Monitor is a confined service. To run under SELinux enforcing with strict file paths:

- Install to `/opt/server-monitor/server` (binary)
- Config in `/etc/server-monitor/config.yaml`
- TLS in `/etc/server-monitor/tls/`
- State in `/var/lib/server-monitor/`
- Run as user/group `servermon`

Label suggested types:

- Binary: `bin_t` (default) or create custom type `servermon_exec_t`
- Config/TLS: `etc_t`
- State dir: `var_lib_t`
- Systemd unit: `systemd_unit_file_t`

If SELinux denies network bind on 8443, allow privileged port or change to high port:

```
# Option 1: allow binding to 8443
sudo semanage port -a -t http_port_t -p tcp 8443

# Option 2: change ListenAddress to high port (e.g., 9443)
```

If you need a custom SELinux policy module, generate a baseline from audit logs:

```
sudo ausearch -m AVC -ts recent | audit2allow -M servermon
sudo semodule -i servermon.pp
```

Use `restorecon -Rv` to fix labels after installation:

```
sudo restorecon -Rv /opt/server-monitor /etc/server-monitor /var/lib/server-monitor
```

> Note: On hardened systems, consider `CapabilityBoundingSet` in systemd instead of SELinux changes.


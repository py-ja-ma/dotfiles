# Private host definitions

Per-host blocks go here as `*.conf` files, for example `homelab.conf`, mode 0600.
`~/.ssh/config` includes them first, so their settings win over its defaults.
Only this README is tracked; `*.conf` files here are gitignored.

```sshconfig
Host router
    HostName 192.168.1.1
    User admin
    # old network gear: re-enable legacy algorithms for this host only
    #KexAlgorithms +diffie-hellman-group14-sha1
    #HostKeyAlgorithms +ssh-rsa
    #PubkeyAcceptedAlgorithms +ssh-rsa
    # tiny embedded sshd's often dislike multiplexing:
    #ControlMaster no

Host nas pve1
    User admin
```

The config these load into: [dotfiles/.ssh/README.md](../README.md).

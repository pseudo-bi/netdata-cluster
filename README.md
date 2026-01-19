# netdata-cluster

Apt-based Netdata bootstrap for a small Ubuntu lab cluster.

## Scope
- Install Netdata via apt
- Configure head (receiver) / child (stream)
- Child connects to head by IP (DHCP-friendly; no /etc/hosts)
- Provide connectivity tests and uninstall rollback

## Assumptions
- Ubuntu 24.04 LTS (mostly) + one Ubuntu 22.04 LTS node
- Hostname is managed manually (node identity in Netdata UI)
- Long-term history is not required

## Layout
- bin/: entrypoint scripts (install/configure/test/uninstall)
- conf/: minimal config templates
- lib/: shared shell helpers

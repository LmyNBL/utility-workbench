# Profile Overlay Helper

This folder contains a non-secret local profile overlay helper.

It is designed to be used with a generated Clash/Mihomo YAML file. It does not
store subscriptions, nodes, UUIDs, passwords, or runtime endpoints.

## Files

- `groups.yml`: group list and generic overlay settings.
- `apply-profile-overlay.rb`: local post-processing script.

## What It Does

The script keeps original groups and nodes unchanged. For each group listed in
`groups.yml`, it creates a parallel group with the configured suffix and clones
that group's nodes. The cloned nodes receive a `dialer-proxy` field pointing at
the local dialer node.

Example:

```text
🇭🇰 香港节点
🇭🇰 香港节点-dialer-proxy
```

## Usage

Run this only on a trusted local machine or router, because the input YAML may
contain private node credentials.

```bash
export DIALER_SERVER="192.168.50.41"
export DIALER_PORT="7891"
export DIALER_USERNAME="..."
export DIALER_PASSWORD="..."

ruby apply-profile-overlay.rb groups.yml /etc/openclash/ALL.yaml /tmp/ALL.with-overlay.yaml
```

Then validate the generated YAML with the target Mihomo binary before replacing
any live configuration.

## Source Template

The current group plan is based on the ACL4SSR Online Full NoAuto template:

```text
https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/refs/heads/master/Clash/config/ACL4SSR_Online_Full_NoAuto.ini
```

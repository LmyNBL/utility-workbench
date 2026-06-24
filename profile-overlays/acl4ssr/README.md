# Profile Overlay Helper

This folder contains a non-secret local profile overlay helper.

It is designed to be used with a generated Clash/Mihomo YAML file. It does not
store subscriptions, nodes, UUIDs, passwords, or runtime endpoints.

## Files

- `groups.yml`: group list and generic overlay settings.
- `full-noauto-plus.ini`: Subconverter template based on ACL4SSR Online
  Full NoAuto. Use this as the `config=` parameter in Subconverter.
- `apply-profile-overlay.rb`: local post-processing script.
- `serve-overlay.rb`: small HTTP wrapper that runs Subconverter and the overlay
  script for every subscription request.

## How It Fits Subconverter

Your normal chain can stay the same:

```text
Sub Store -> Subconverter -> Clash/Mihomo YAML -> local overlay -> OpenClash
```

Use `full-noauto-plus.ini` in the Subconverter URL where the upstream
ACL4SSR template was previously used. It keeps the ACL4SSR rules and adds
parallel selection groups such as:

```text
🇭🇰 香港节点
🇭🇰 香港节点-dialer-proxy
```

Subconverter templates can define rules and proxy groups, but they do not
rewrite every generated node with Mihomo-only fields such as `dialer-proxy`.
That final node cloning step is handled by `apply-profile-overlay.rb`.

If Sub Store is doing the final post-processing, use the Sub Store file endpoint
as the final OpenClash config subscription. Do not put that final YAML endpoint
back through Subconverter as a normal node subscription, or Mihomo-only fields
such as `dialer-proxy` may be stripped again.

Example final endpoint shape:

```text
http://SERVER:25500/<api-prefix>/api/file/All-Dialer-Profile
```

## What The Overlay Does

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

## Automatic Wrapper

Run `serve-overlay.rb` on a trusted local server and point OpenClash at:

```text
http://SERVER:25502/sub-overlay/all
```

Every request performs this chain:

```text
fetch Subconverter YAML -> apply profile overlay -> return final YAML
```

Required environment variables:

```text
DIALER_SERVER=192.168.50.41
DIALER_PORT=7891
```

Optional environment variables:

```text
DIALER_USERNAME=...
DIALER_PASSWORD=...
WRAPPER_BIND=0.0.0.0
WRAPPER_PORT=25502
SUBCONVERTER_URL=http://127.0.0.1:25501/sub
SUBSTORE_URL=http://192.168.11.142:25500/.../download/collection/All
SUBCONVERTER_CONFIG_URL=https://raw.githubusercontent.com/LmyNBL/utility-workbench/main/profile-overlays/acl4ssr/full-noauto-plus.ini
```

## Sub Store Final File Mode

The Sub Store file named `All-Dialer-Profile` can own the complete chain:

```text
Sub Store collection -> Subconverter with full-noauto-plus.ini -> Sub Store script restores dialer-proxy -> OpenClash
```

Use the `api/file/All-Dialer-Profile` URL directly in OpenClash as a config
subscription. The `download/collection/All-Dialer` URL is only a node collection;
it does not contain `proxy-groups` or `rules`, so OpenClash may place everything
under a default global group if it is used directly.

## Raw Template URL

Use this URL as the Subconverter `config=` value after this repository is
published:

```text
https://raw.githubusercontent.com/LmyNBL/utility-workbench/main/profile-overlays/acl4ssr/full-noauto-plus.ini
```

## Source Template

The current group plan is based on the ACL4SSR Online Full NoAuto template:

```text
https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/refs/heads/master/Clash/config/ACL4SSR_Online_Full_NoAuto.ini
```

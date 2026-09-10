# puppet-lego

Puppet module for the [lego](https://go-acme.github.io/lego/) ACME client.

Each host obtains and renews **its own** TLS certificate, solving the DNS-01
challenge against Amazon Route 53. No certificate and no private key is ever
distributed by Puppet: the key is generated on the host and never leaves it.

```
Puppet installs:   the lego binary, its configuration, a systemd timer and a
                   deploy hook
The host does:     request the certificate, renew it on its own schedule,
                   deploy it and reload the service
Puppet installs:   no certificates, no private keys
```

## Why DNS-01

It is the only challenge type that can issue wildcards, and it needs neither
port 80 open to the internet nor public A records for every name served. That
matters on hosts whose vhost names are not published in DNS, or whose HTTP port
is closed: HTTP-01 would require opening it and would publish every name in the
Certificate Transparency logs.

## Requirements

- systemd
- The `lego` release tarball for your platform in `files/` (see *Vendored
  binary* below)
- AWS credentials reachable by the host. An EC2 instance profile is enough; no
  credentials are written to disk.

> **Tested on Debian-family Linux only** (developed against Ubuntu 22.04).
> Nothing in the module is deliberately distribution-specific except the
> configuration check described in *Reloading the service*, but no other family
> has been tried. Patches welcome.

## Usage

```puppet
include lego

lego::cert { 'www':
  domains        => ['www.example.com', 'example.com'],
  email          => 'admin@example.com',
  hosted_zone_id => 'Z0EXAMPLE1234567',
  deploy_cert    => '/etc/ssl/certs/example.crt',
  deploy_key     => '/etc/ssl/private/example.key',
  reload_command => 'systemctl reload apache2',
}
```

Declare one `lego::cert` per certificate the host needs.

### Cross-account zones

Route 53 does not support resource-based policies, so a host cannot be granted
access to a hosted zone owned by another AWS account directly: it has to assume
a role there. lego supports this natively.

```puppet
  assume_role_arn => 'arn:aws:iam::123456789012:role/acme-dns01',
```

The role in the zone's account needs `route53:ChangeResourceRecordSets` on that
zone and `route53:GetChange` on `*`. The write can be narrowed so that a
compromised host can only touch the challenge records and nothing else:

```json
{
  "Effect": "Allow",
  "Action": "route53:ChangeResourceRecordSets",
  "Resource": "arn:aws:route53:::hostedzone/Z0EXAMPLE1234567",
  "Condition": {
    "ForAllValues:StringEquals": {
      "route53:ChangeResourceRecordSetsRecordTypes": ["TXT"],
      "route53:ChangeResourceRecordSetsActions": ["UPSERT", "DELETE"]
    },
    "ForAllValues:StringLike": {
      "route53:ChangeResourceRecordSetsNormalizedRecordNames": ["_acme-challenge.*"]
    }
  }
}
```

`route53:ListHostedZones` is **not** required as long as `hosted_zone_id` is
set: lego only needs it to auto-detect the zone from the domain name.

## How it works

Two systemd units per certificate:

```
lego-<name>.service    oneshot: runs, does the whole thing, exits. Not a daemon.
lego-<name>.timer      the clock: starts that service periodically
```

Starting the service by hand *is* doing the whole process once, which makes the
first issuance easy to supervise:

```bash
systemctl start lego-www.service
journalctl -fu lego-www.service
```

In lego 5.x a single `run` command both obtains and renews, so there is no
wrapper deciding between the two. Every lego option has a `LEGO_*` environment
variable, so the whole configuration lives in one environment file and the unit
takes no arguments.

The **deploy hook** is executed by lego after a successful issuance or renewal,
not by Puppet. It copies the material to `deploy_cert` and `deploy_key` — the
key as `0600`, owned by root — writing atomically via a temporary file so the
web server can never read a half-written certificate. It then runs
`reload_command`. If anything fails, the hook exits non-zero, cleans up its
temporary files and **does not reload**, so the old certificate keeps being
served and the failure is visible in the journal.

### Reloading the service

Reloading a web server with a broken configuration takes it down, so the hook
verifies the configuration before reloading. **That check is hardcoded to
`/usr/sbin/apache2ctl configtest`**, which is Apache as packaged by Debian and
Ubuntu:

| Situation | Behaviour |
|---|---|
| `apache2ctl configtest` passes | reloads |
| `apache2ctl` is not installed | reloads **without checking** |
| `apache2ctl configtest` fails | does not reload, exits non-zero |

So on any other web server, or on a distribution that names the binary
differently — `httpd -t` on RHEL family, for instance — the check silently does
not happen and `reload_command` runs unverified. It still works, and a broken
reload will surface as a failed unit, but you lose the safety net.

Making the check a parameter alongside `reload_command` is the obvious
improvement and has not been done yet.

## Vendored binary

The tarball ships in `files/`, and `lego::install` extracts it. The distribution
package is deliberately not used: on Ubuntu 22.04 it is lego 4.1.3, which does
not support `AWS_ASSUME_ROLE_ARN` and therefore cannot solve a challenge in a
zone owned by another account.

To update, download the release and its checksums, verify, and drop the tarball
in `files/`:

```bash
V=5.4.1
curl -sLO https://github.com/go-acme/lego/releases/download/v${V}/lego_v${V}_linux_amd64.tar.gz
curl -sLO https://github.com/go-acme/lego/releases/download/v${V}/lego_${V}_checksums.txt
sha256sum -c --ignore-missing lego_${V}_checksums.txt
```

Then bump `$version` in `manifests/params.pp`. The extraction is guarded by the
installed version, so it runs on the first agent pass and again only when the
version changes.

## Parameters

### `lego`

| | | |
|---|---|---|
| `version` | `5.4.1` | Vendored version. `files/lego_v${version}_linux_amd64.tar.gz` must exist |
| `install_dir` | `/usr/local/bin` | Where the binary goes |
| `data_dir` | `/etc/lego` | Accounts and certificates (`$LEGO_PATH`), mode `0700` |
| `manage_data_dir` | `true` | `false` installs the binary only — useful when baking an image |

### `lego::cert`

| | | |
|---|---|---|
| `domains` | — | **Required.** First name is the CN, the rest are SANs |
| `email` | — | **Required.** ACME account address. The CA warns here when a renewal fails, so use one somebody reads |
| `hosted_zone_id` | — | **Required.** Route 53 zone to write the challenge into |
| `assume_role_arn` | `undef` | Role to assume when the zone lives in another account |
| `deploy_cert` / `deploy_key` | `undef` | Where the hook copies the material. Both or neither |
| `deploy_chain` | `undef` | Optional path for the issuer chain alone |
| `reload_command` | `undef` | Run after a successful deployment. The configuration check that precedes it is Apache/Debian-specific — see *Reloading the service* |
| `server` | `letsencrypt-staging` | `letsencrypt` for production. Staging issues untrusted certificates with far higher rate limits: use it until the configuration is proven |
| `key_type` | `RSA2048` | lego's own default is `EC256`; this module is explicit so the algorithm never changes by accident |
| `renew_days` | `0` | `0` lets lego decide, using a third of the remaining lifetime and the ARI endpoint (RFC 9773) |
| `check_interval` | `12h` | How often it **checks**, not how often it renews |
| `enable_timer` | `false` | `false` leaves the timer installed and stopped, so nothing is requested until someone starts it |
| `aws_region` | `eu-west-1` | |

## Notes

Start against `letsencrypt-staging`. Let's Encrypt allows only 5 authorization
failures per identifier per hour, so a misconfigured permission will lock you
out for an hour if you debug against production.

With `enable_timer => false` Puppet leaves everything in place and requests
nothing. That makes the first issuance a supervised, deliberate act — which is
when permission problems show up.

## License

MIT — see [LICENSE](LICENSE).

The `lego` binary shipped in `files/` is redistributed unmodified and is also
MIT licensed; its copyright notice is kept alongside it in
[`files/LICENSE.lego`](files/LICENSE.lego) and inside the tarball itself.
Copyright (c) 2017-2024 Ludovic Fernandez, (c) 2015-2017 Sebastian Erhart.

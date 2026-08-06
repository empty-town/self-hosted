# Self-hosting behind your own reverse proxy — the step-by-step

A few days ago I posted [*You do not need a tunnel to securely expose your self-hosted services*](https://www.reddit.com/r/selfhosted/comments/1vd73zw/you_do_not_need_a_tunnel_to_securely_expose_your/).

But a fair chunk of the comments said the same thing: *This is too long. No one will read this. it's a valid approach, but not something I can actually follow.* Point taken. It explained the "why" but didn't provide an example of "how". This is an OPINION based guide/demo. The purpose of this repo is for users to experiment/learn with **dummy** data about the processes, technologies, and methods of securely hosting public services. Use it at your own risk, and I will not be maintaining it. 

So here's the "how." A ready-to-run repo, and clear step-by-step instructions to stand it up on your own (linux) home server. Caddy with a CrowdSec bouncer compiled in, threat detection, per-service network isolation. It is based upon my own services that I have been running for many years. Clone it, follow the steps, and you've got the setup from the original post running.

I also encourage the same commenters on the previous post to continue sharing their concerns, improvements, doubt, warnings, or other musings.

Curious what this actually stands up on the public internet? This same repo runs a live demo:

- **Jellyfin** — [jellyfin.starman.app](https://jellyfin.starman.app)
- **Immich** (photos) — [photos.starman.app](https://photos.starman.app)
- **Nextcloud** (files) — [cloud.starman.app](https://cloud.starman.app)

I expect it will go down with too many users clicking it due to the fact it only has 1G memory. I will be taking it down in 30 days. The IP is 67.207.88.112. If someone wants to DDoS it, go for it, but I won't be putting it back up.

## What this does NOT protect against

This architecture contains and deters; it does not make you unhackable. Know what's still on you:

- **A fresh exploit in an exposed app.** A new CVE in Jellyfin/Immich/Nextcloud is reachable until your next update. Patch speed is the defense.
- **Stolen or phished passwords.** A correct password looks like a login, not an attack. Unique passwords + 2FA (or SSO in front).
- **A poisoned upstream image.** Updates trust the app publishers. Digest pinning (see *Image versions*) is the opt-in defense.
- **DNS or registrar account takeover.** Whoever controls your DNS can impersonate your services with a valid certificate. Hardware-key 2FA on those accounts.
- **Attackers already on your LAN.** The firewall rule blocks containers→LAN, not LAN→server. VLANs fix this.
- **Container escape via a kernel exploit.** All containers share one kernel. Accepted residual risk; a DMZ/VLAN caps the damage.
- **DDoS.** A saturated home uplink can't be fixed from behind the router.
- **Quiet intrusions.** CrowdSec bans noisy attackers, silently. Nobody is alerted unless you add notifications.
- **Data destruction through a valid account or popped app.** Ransomware on a family laptop, or a compromised app deleting its own data. Only tested, offline backups fix this.
- **Physical theft of the server.** Data is unencrypted at rest unless you add disk encryption (LUKS).

## ! Important !
One thing this guide deliberately leaves out: **your router**. Security, networking, port-forwarding, VLANs, DMZ, look different on every make and model, and there's no way to write one set of steps that fits them all. **Your router configuration is up to you to research and decide on**.

---

## Before you expose anything: are you ready?

I encourage learning by doing. But a few things need to be true before you point the internet at your public IP. Read them. Each one you fail tells you what you need to learn.

**1. Does anyone but you actually need access?** If it's only ever you, stop here and use a VPN — Tailscale or WireGuard, done. Public exposure buys you nothing and costs you attack surface. The rest of this guide is for when you have decided that *other people* need to reach your services without installing anything first.

**2. Do you have a real public IP?** Open your router's admin page and find its WAN IP. Now load [whatismyip.com](https://whatismyip.com). Same number? You have a public IP. Different number? You're behind carrier-grade NAT — your ISP is sharing that address with other customers, and no amount of port-forwarding will reach you. Call your ISP and ask for a public IP, or use a cheap VPS in front of your services as your public endpoint. While you're in there: does that WAN IP stay the same or change? If it changes, you'll need dynamic DNS, this guide can help you set it up.

**3. Can you describe the path a request takes?** Roughly: DNS resolves the name to your IP, the request hits your router, the router forwards the port to one machine, something terminates TLS, the app answers. If that sentence is fog, spend a weekend on how web traffic works before you expose anything.

**4. Do you own your network?** Can you log into your router, add a port-forward, and turn UPnP *off* so apps can't quietly open ports behind your back? Could you confirm (from *outside* your network) exactly which ports answer on your public IP? If not, that's time spent with your router software.

**5. Will you actually maintain it?** Are you willing to update frequently, use a strong password on every login page, enable 2fa when applicable, and have *some* way to notice when something breaks — a log you read, an alert? A box you stand up perfectly and then forget is how most real compromises start. If the honest answer is "no," expose nothing until it's "yes."

**6. Can you restore from a backup?** Assume that one day a service gets popped, a disk dies, a `docker compose down -v`. Do you have backups of your data and your configs? Have you actually restored one to confirm it works? An untested backup is a guess. Bonus points, ZFS with snapshots, and sync to off-site backup.

**7. Do you know what hardware Admin panels are?** Do you trust them? Do you know not to expose an all-in-one appliance's admin panel? A consumer NAS web UI — the kind with a history of critical CVEs and slow patches — is exactly what gets mass-scanned and mass-exploited. **Never** expose any administrator interfaces for hardware you are running.

**8. Do you own a consumer router?** Use **non-consumer** hardware, especially when it comes to the router. Whether it's a router, NAS, switch, etc. Low-cost routers/NAS are buggy, poorly developed, poorly maintained, and targeted as we saw with QNAP/QLocker. OPNSense or PFSense, DD-WRT are the top preferred router operating systems, and can run on very meager hardware. If you don't have this, there's your first focus. 

**9. Do you know the basics of networking?** You should be able to say in a sentence each what these are and why they matter to what you're about to do: an IP address and a subnet; a port, and TCP vs UDP; NAT and port-forwarding; DNS, and the difference between an `A`, `CNAME`, and wildcard record; what a reverse proxy is; HTTP vs HTTPS and what TLS actually protects; and a firewall. Worth *recognizing* or considering: VLANs and network segmentation.

If you're even close to unsure about any of these, you should read up on individual things until you're confident you know the risks, configuration, and abilities of individual technologies. 

---

## What this is

This is a *reverse proxy* service architecture. Here, Caddy is the only thing on your network the outside world can talk to. A request arrives, Caddy handles the HTTPS encryption, works out which service it's for, and passes it inward. Your actual apps — Jellyfin, Immich, Nextcloud, etc — never face the internet directly. They only ever hear from Caddy.

Why funnel everything through Caddy? Because every service you expose directly is another attack surface, and another thing you have to keep patched/know is exposed. Also this terminates TLS at one point.

Behind Caddy, each service runs in its own container network, and Docker walls those networks off from each other — break into one and you can't step through into the next. Reaching the other machines on your home network is blocked too — by a firewall rule this setup installs. Getting past all of that would mean breaking out of the container and into the host — which takes a separate, much harder exploit. The blast radius is one part of a secure setup, not everything.

Additionally, CrowdSec watches the proxy's (Caddy) logs, and the moment an IP starts attempting infiltration — scanning for admin pages, trying known exploits — it gets banned before it reaches any app. The internet will start probing you within minutes of going live; this is what helps you manage common attackers.

None of this needs a VPN or a tunnel. That's the whole point of the original post, and the opinion this guide is willing to stand behind: if other people need to reach your services without installing anything, you can expose them directly *and* safely — provided you understand achitecture well enough.

---

## Repo Structure

Everything is plain files — compose YAML, a Caddyfile, three shell scripts.

```
self-hosted/
├── docker-compose.yml       Edge stack — Caddy + CrowdSec (and optional dynamic DNS, off by default)
├── .env.example             Copy to .env: DOMAIN, TZ, and the secrets bootstrap fills in
├── renovate.json            Push to a Git remote → Renovate opens image-update PRs
│
├── caddy/
│   ├── Dockerfile           Builds caddy:2 with the CrowdSec bouncer compiled in (xcaddy)
│   └── Caddyfile            Vhosts, automatic TLS, security headers, the `crowdsec` handler
│
├── crowdsec/
│   └── acquis.yaml          Points CrowdSec at Caddy's access log (what it watches to ban IPs)
│
├── scripts/
│   ├── bootstrap.sh         Creates networks, fills secrets, installs the DOCKER-USER LAN block
│   ├── verify-exposure.sh   External nmap sweep — proves only 80/443 answer from outside
│   └── update.sh            Pull + redeploy every stack (the Watchtower you don't run)
│
└── stacks/                  One folder per service group; each is its own compose project
    ├── media/               Jellyfin (public) + Radarr/Sonarr/Prowlarr (loopback-only)
    │   └── docker-compose.yml
    ├── immich/              Photos — server + machine-learning + Postgres + Redis (public)
    │   └── docker-compose.yml
    └── nextcloud/           Files — app + Postgres + Redis (public)
        └── docker-compose.yml
```

The **root `docker-compose.yml` is only the edge** — the proxy. The apps live under `stacks/`, and each one is a separate compose project. You start only the stacks you want.

## How it fits works

**Caddy** is the only container bound to `0.0.0.0` (ports 80/443), with the **CrowdSec bouncer** compiled in — known-bad IPs are dropped at the proxy before they reach a service. Every backend sits on its own Docker network and publishes **no** host ports at all. That's stricter than binding to `127.0.0.1`: there's no host port to bind. 

Each stack actually gets **two** networks: Caddy joins only the app-facing one, while the databases, caches, and helper containers sit on an internal one Caddy is not attached to — so even a compromised proxy can talk to the app containers only, never to a Postgres or Redis port.

```
internet ──▶ router (80/443 only) ──▶ caddy ──▶ per-stack networks
                                        │
                                     crowdsec (reads caddy logs, bans IPs)
```

---

## Deploying it

Continuing assumes your router is configured for security, UPnP is disabled, and ports 80 and 443 are forwarded to your server. 

### 0. Before you start

You need these things ready:

- A home server with a modern Linux operating system. I used Debian.
- Docker Engine and the Docker Compose plugin. See the [official install guide](https://docs.docker.com/engine/install/).
- A user that can run Docker (add it to the `docker` group, or use `sudo`).
- Ports 80 and 443 forwarded to this server, with UPnP off. This is your router's job.
- A domain name. Step 1 shows how to get one.

Download the repo and go into its folder. Run every later command from inside this folder:

```bash
git clone https://github.com/empty-town/self-hosted.git
cd self-hosted
```

### 1. Get a domain and point it at your server

Buy a domain from a registrar. Cloudflare, Porkbun, and Namecheap are common choices. Then use a DNS provider to manage it. Cloudflare is free (besides the domain purchase) and works well.

Add one `A` record per service you expose, each pointing at your public IP:

```
jellyfin.example.com   A   <your-public-ip>    # media
photos.example.com     A   <your-public-ip>    # immich
cloud.example.com      A   <your-public-ip>    # nextcloud
```

Add only the names you actually run. Prefer these explicit records over a wildcard (`*.example.com`): a wildcard points *every* possible name at your server, including ones you never meant to publish, which only helps someone mapping your setup. One record per real service keeps what is public equal to what you actually serve. (A record for the bare domain is optional — nothing is served there.)

Add **only `A` records — no `AAAA`**. This setup is IPv4-only: Step 2 disables IPv6 on the server, and an `AAAA` record would advertise a path that none of this guide's protections cover.

If you use Cloudflare, set each record to **DNS only** (grey cloud), not **Proxied** (orange cloud). The orange cloud hides the real visitor IP. CrowdSec needs the real IP to ban attackers.

Check that the domain works before you continue:

```bash
dig NS example.com +short        # lists your DNS provider's nameservers
dig +short jellyfin.example.com  # returns your public IP
```

Empty output means the domain is not ready. Fix it at your registrar first.

### 2. Set your secrets and prepare the host

Copy the example file and lock its permissions:

```bash
cp .env.example .env && chmod 600 .env
```

Open `.env` and set each value. The file explains every line:

- `DOMAIN` — your domain from Step 1.
- `TZ` — your timezone, for example `America/New_York`.
- `IMMICH_UPLOAD_DIR` and `NC_DATA_DIR` — change these only if you want the data in a different folder.
- Leave every value under "Generated by bootstrap.sh" empty. The next command fills them.
- Leave `CF_API_TOKEN` empty unless you turn on dynamic DNS (see the end of this step).

Run `bootstrap.sh` to prepare the host. Pass your own LAN range:

```bash
sudo LAN_SUBNET=192.168.1.0/24 ./scripts/bootstrap.sh   # use your LAN range
```

`bootstrap.sh` does four things:

1. It creates the Docker networks that keep the stacks apart — a Caddy-facing network per stack, plus an internal network per stack for the databases and caches, which Caddy cannot reach.
2. It writes a random secret into each empty value in `.env` (the CrowdSec key and the database passwords).
3. It adds a firewall rule (the DOCKER-USER chain) that stops any container from reaching the other machines on your LAN.
4. It installs a small systemd unit, `docker-user-lan-block.service`, with your LAN range baked in. Docker clears the DOCKER-USER chain on every reboot; this unit re-applies the rule after each boot. (`iptables-persistent` is deliberately not used — alongside Docker it saves and duplicates Docker's own rules.)

Verify the unit is in place:

```bash
systemctl status docker-user-lan-block.service   # loaded, enabled
sudo iptables -L DOCKER-USER                     # ACCEPT (established), then DROP to your LAN
```

Two limits of that LAN rule worth knowing. It filters *forwarded* traffic only, so it does not stop a container from reaching services the host itself listens on — keep host services on loopback or key-only (SSH). And it is IPv4-only — which is the whole story here, because you disable IPv6 on this server below.

**Disable IPv6 on the server.** This guide is IPv4-only by design. Every client that needs your services can reach them over IPv4.

```bash
echo 'net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1' | sudo tee /etc/sysctl.d/99-disable-ipv6.conf
sudo sysctl --system
ip -6 addr   # should print nothing
```

This affects only this server — the rest of your LAN keeps IPv6 if your router provides it. (One honest exception: if your ISP has you behind CGNAT and IPv6 is your only real public path, this guide's IPv4-only stance doesn't fit your network — use the VPS-in-front option from the readiness checklist instead, or accept that proper v6 hosting needs its own checklist: `AAAA` records, router v6 pinholes for 80/443 only, `ip6tables` mirrors of the LAN block, and v6 exposure scans.)

**Optional — dynamic DNS.** Turn this on only if your public IP changes. Set `CF_API_TOKEN` in `.env`, then uncomment the `ddns` service in `docker-compose.yml`. A static IP does not need this.

### 3. Start the edge and check the certificates

```bash
docker compose up -d --build
```

The `--build` step compiles Caddy with the CrowdSec bouncer. This is the slowest step. Give it a minute on a small server.

Check that the bouncer registered:

```bash
docker exec crowdsec cscli bouncers list   # the caddy bouncer must appear
```

Check that Caddy got its TLS certificates. This is the step that fails most often, and the cause is almost always a DNS mistake in Step 1:

```bash
docker logs caddy 2>&1 | grep -i "certificate obtained"
curl -sI https://jellyfin.example.com   # a reply (even 502) means TLS works
```

A missing certificate line means Caddy could not get a certificate. Check your DNS records and start again. A `502` reply from `curl` is fine here — the app itself starts in Step 4.

### 4. Create the data folders and start the stacks you want

Each app stores its data in a folder on the host. Create the folders first, or the apps start with the wrong permissions:

```bash
sudo mkdir -p /mnt/media /mnt/photos /mnt/nextcloud-data
```

Match these paths to `.env`. `/mnt/media` is the Jellyfin library. `/mnt/photos` is `IMMICH_UPLOAD_DIR`, and `/mnt/nextcloud-data` is `NC_DATA_DIR`.

Jellyfin runs as a non-root user (`user: "1000:1000"` in its compose file). Docker creates fresh named volumes owned by root, so if you run the media stack, set the owner of Jellyfin's two volumes **before** the first start:

```bash
docker run --rm -v media_jellyfin_config:/config -v media_jellyfin_cache:/cache \
  alpine chown -R 1000:1000 /config /cache
```

(This creates the volumes with the right owner; Compose then uses them and may print a "not created by Compose" notice, which is fine.)

Start only the stacks you want. Each one is independent:

```bash
docker compose --project-directory stacks/media     --env-file .env up -d
docker compose --project-directory stacks/immich    --env-file .env up -d
docker compose --project-directory stacks/nextcloud --env-file .env up -d
```

Caddy serves each stack at its own name: `jellyfin.<DOMAIN>`, `photos.<DOMAIN>`, and `cloud.<DOMAIN>`. The `*arr` apps in the media stack (Radarr, Sonarr, Prowlarr) are not exposed. You need to access them over your VPN or LAN, because these are management applications.

### 5. Verify your exposure from outside

Run `verify-exposure.sh` from a machine on a different network. A phone on cellular data works:

```bash
./scripts/verify-exposure.sh example.com
```

`verify-exposure.sh` scans your public IP with `nmap`. It confirms that only ports 80 and 443 answer from the internet. If any other port is open, stop and fix it before you continue.

### 6. Harden the apps

Open each app in a browser and finish its setup:

- Create your admin account in Jellyfin, Immich, and Nextcloud.
- Turn on two-factor authentication (2FA) where the app supports it.
- Use a strong, unique password for every account.

### What success looks like

- `dig` returns your public IP for your service names.
- `cscli bouncers list` shows the caddy bouncer.
- `docker logs caddy` shows a certificate for each service.
- `verify-exposure.sh` reports only ports 80 and 443 open.
- `dig AAAA` returns nothing for your service names; `ip -6 addr` on the server prints nothing.
- Each app loads over HTTPS, and 2FA is on.

---

## Design decisions

- **No published backend ports** instead of `127.0.0.1` binds. Same effect, smaller surface, and no Docker/iptables interaction to reason about. The `*arr` apps keep loopback binds because you reach them off-proxy (VPN/LAN).
- **No Docker socket anywhere.** No Watchtower, no Portainer, no Traefik discovery. Updates run from the host (`update.sh` / Renovate).
- **DOCKER-USER chain** for the LAN block. Docker evaluates this chain and does not overwrite it, unlike raw ufw rules.
- **IPv4-only, on purpose.** No `AAAA` records, IPv6 disabled on the server (Step 2), and Caddy's ports published on `0.0.0.0` explicitly so nothing answers on v6 even if IPv6 is ever re-enabled. Every client can reach you over IPv4, so v6 adds zero reachability for this use case — while adding a parallel, NAT-less attack surface that the DOCKER-USER block (iptables/v4) and the exposure scan would not cover. A surface that costs nothing to remove, removed.
- **Isolation & residual risk** The defended failure mode is "attacker gets code execution in a container," and the layers here contain that: no host ports, per-stack Docker networks (Docker drops traffic *between* bridges at the kernel), a second internal network per stack that keeps Caddy away from the databases and caches, and the DOCKER-USER LAN block. A popped backend can reach only Caddy; a popped Caddy can reach only the app containers it proxies — never a Postgres or Redis port; reaching anything *else* needs a separate container-escape-to-host exploit — targeted-attacker behavior, not scanner behavior. A **DMZ/VLAN** is the best value-per-effort upgrade for that residual case (cheap if you already run OPNsense — one VLAN, a few firewall rules — and it caps your worst case at "rebuild one host"). But none of it is *required* for this threat model; it's what cheap containment of the residual risk looks like. VM-per-service is disproportionate for self-hosted apps, and the extra patching surface is itself a security cost.
- **CrowdSec is included** — active IP banning at the proxy. This goes *beyond* the original post's minimum (which recommends watching your logs); it's the automated version of that. Collections: caddy, http-cve, base-http-scenarios. One blind spot to know when reading its metrics: CrowdSec sees only requests that match a configured site. Raw-IP / no-SNI scans fail the TLS handshake before anything is logged — fine, they reach nothing — but don't read `cscli metrics` as a complete census of what's probing you.
- **`oznu/cloudflare-ddns` is archived.** this uses `favonia/cloudflare-ddns` instead.
- **`no-new-privileges`** on every container. Cheap, no downsides.
- **Non-root where the image supports it.** Jellyfin runs under `user: "1000:1000"` — nothing in that container ever runs as root (the official image ignores linuxserver-style `PUID`/`PGID`, so those vars are not used). Several other official images (MariaDB, Postgres, Valkey, Nextcloud, Immich) start their entrypoints as root and drop to a service user; that pattern is accepted here. Root inside a container is still namespace- and capability-bounded — not host root — but a non-root process makes the container-escape residual risk harder, since most escape exploits need capabilities only container root holds.
- Possible future option that is not included here: forward-auth SSO (Pocket ID or Authelia) in front of the weaker app login pages.

## Automation

| Task | Method |
|---|---|
| TLS certificates | Caddy / ACME. Fully automatic. |
| Dynamic DNS (optional) | Turn on the `ddns` container (off by default). It then keeps your DNS record current. |
| IP bans | CrowdSec + bouncer. Fully automatic. |
| Image updates | `scripts/update.sh` pulls new images and redeploys every stack — run it on a cron/systemd timer. Or push this repo to a Git remote and let **Renovate** open update PRs (`renovate.json` included). |
| Exposure check | `verify-exposure.sh` from a cheap VPS on a timer, alert on diff. |
| Uptime | Add Uptime Kuma on `frontend` if wanted. |

Not automatable: router configuration, registrar setup, and the decision of which apps to expose.

## Image versions

Every image is **pinned by tag**, not by an exact digest. Most track a tag that holds a major line (`mariadb:11`, `valkey:8`) or a project's rolling stable tag (`jellyfin:latest`, the `*arr` images). `scripts/update.sh` runs `docker compose pull`, which advances each to its newest build within that line, then redeploys.

**Major version upgrades are always manual.** A new major can drop support, change a config format, or run a one-way database migration, so it must never land from an unattended `pull`. The two apps most likely to bite get special handling:

- **Nextcloud** is pinned to a specific major (`nextcloud:34-apache`), not the rolling `stable-apache` tag. `update.sh` gives you patch fixes within that major; to move to the next one you edit the number by hand in `stacks/nextcloud/docker-compose.yml` — after reading the [upgrade notes](https://docs.nextcloud.com/server/latest/admin_manual/maintenance/upgrade.html) and taking a backup. Nextcloud refuses to skip a major, so do them one at a time.
- **Immich** is pre-1.0, ships breaking changes often, and has no major tag to pin to. `update.sh` **skips it**; update Immich deliberately after reading the [release notes](https://github.com/immich-app/immich/releases). Its Postgres image is a VectorChord/pgvector build version-locked to the release (there is no plain `:16`), so bump the app images and the DB tag together, copying both from Immich's official compose.

`renovate.json` matches this: patch and minor bumps automerge, but Nextcloud and Immich are held for manual review.

**Want reproducible builds instead?** This is the hardening tier: enable `"pinDigests": true` in `renovate.json`. Renovate then appends `@sha256:…` to every tag and opens a PR each time a digest changes — you get frozen bytes *and* a reviewed update trail, at the cost of running Renovate against your own copy of the repo. Pick this if supply-chain reproducibility matters more to you than clone-and-go simplicity.

---

The [`docs/`](docs/) folder is the build log — the exact host setup and deployment notes, including what the internet threw at it in the first hour.
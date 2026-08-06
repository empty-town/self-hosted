# What I did: stack deployment (edge + services)

> **Scope note.** Same as `host-setup.md` — transparency record / "further reading," not part of the guide.

The example server runs the **exact repo at the root of this project** — the same files a reader downloads. There is no separate reduced config. The only differences are host-specific values set at deploy time (domain, LAN range, data paths), listed below.

## Decisions (and why)

- **Full stack on the 1 GB box** Caddy + CrowdSec (edge), the media stack (Jellyfin + Radarr/Sonarr/Prowlarr), Immich, and Nextcloud. Immich's machine-learning container and the two database stacks are memory-heavy, so this leans on swap at idle and swaps harder under load. It is slow under real use but fine for a demo, and it proves the whole repo comes up on modest hardware.
  - Jellyfin runs **direct-play only** — no transcoding headroom on 1 vCPU.
  - The **\*arr apps** (Radarr/Sonarr/Prowlarr) come up but are **not exposed** — they are loopback/LAN management tools, reached over the VPN, never from the internet.
- **CrowdSec** It is *not* in the original post's recommended list, but readers said the active-defense piece was missing. It is already integrated (bouncer compiled into Caddy, `crowdsec` service in the edge compose), so it adds **no extra reader steps**.
- **Dynamic DNS left off.** The droplet has a static IP, so the `ddns` service stays commented out (its default in the repo). A home reader on a dynamic IP turns it on.

## DNS (Cloudflare, `starman.app`)

All records **DNS-only (grey cloud), not proxied**, because:
1. CrowdSec must see **real attacker IPs** — orange cloud masks them as Cloudflare IPs and the bans/metrics become meaningless.
2. Probing / `nmap` should hit the origin directly.
3. Let's Encrypt's challenge resolves cleanly to the origin.

Explicit `A` records → droplet IP `67.207.88.112` (grey cloud). Chose explicit records over a wildcard — Cloudflare only proxies wildcards on Enterprise, and explicit records dodge the edge cases:
- `jellyfin.starman.app`
- `photos.starman.app`
- `cloud.starman.app`

**[verify]** `dig NS starman.app` shows Cloudflare NS (domain actually delegated), then `dig +short jellyfin.starman.app` returns the droplet IP — *before* letting Caddy retry ACME.

## Host-specific values at deploy time

The repo ships generic (`example.com`, `192.168.1.0/24`). On this box:
- `DOMAIN=starman.app` in `.env`.
- `bootstrap.sh` run with `LAN_SUBNET=10.0.0.0/8` (the DO private range; home users use their LAN, e.g. `192.168.1.0/24`).
- Data dirs created on the host before the stacks: `sudo mkdir -p /mnt/media /mnt/photos /mnt/nextcloud-data`.
- `ddns` left commented out (static IP).

Run order: `bootstrap.sh` → `docker compose up -d --build` (edge) → each stack under `stacks/` with `--project-directory … --env-file .env`.

## Live — first-hour snapshot (edge)

The edge went public within the hour and CrowdSec was banning real scanners immediately. `cscli metrics` after ~43 min (1.39k Caddy log lines parsed):

- **Bans:** jira_cve-2021-26086 ×5, http-probing ×3, http-sensitive-files ×1, http-crawl-non_statics ×1.
- **Scenarios also firing:** http-admin-interface-probing, http-wordpress-scan, http-technology-probing.
- Real external IPs — grey-cloud DNS means Caddy sees true client IPs; whitelists correctly pass CDN / Google / public-DNS ranges.

This scanning is aimed at the IP and generic paths, so it is independent of which apps sit behind the proxy.

## Operational notes

- **DOCKER-USER persistence** via `docker-user-lan-block.service` (systemd oneshot, re-applies the rule after `docker.service`). `iptables-persistent` deliberately avoided — it snapshots and duplicates Docker's own rules.
- **Images pinned by tag, not digest.** Most track a major line (`mariadb:11`, `valkey:8`) or a rolling stable tag (`jellyfin:latest`, the `*arr` images), so `update.sh`'s `docker compose pull` advances them within that line. **Major upgrades are manual:** Nextcloud is pinned to a specific major (`nextcloud:34-apache`, bumped by hand), and Immich (pre-1.0, frequent breaking changes) is **skipped** by `update.sh` and updated deliberately — its Postgres image is a VectorChord build version-locked to the release (`14-vectorchord…`, no plain `:16`), bumped together with the app. A digest pin can't be advanced by `pull`, only by editing the file — digest pinning is documented as an opt-in reproducibility tier (Renovate `pinDigests`) in the README. `renovate.json` also holds Nextcloud and Immich for manual review.
Update: (manually) Rearranged for consumption. Moved common threat models to a comment because it was long, and probably less useful.

Everyone on this sub says "do not expose your services to the internet without a tunnel". "Use Cloudflare Tunnel." Use "Tailscale".

It is, in most cases, a misunderstanding of how the internet works and a conflation of two very different problems. I feel I needed to share this explanation for this audience to help people understand the reality of the overall risks.
Two different problems, two different solutions

The first problem: "I want to access my services when I am away from home." This is a private access problem. Tailscale, WireGuard, ZeroTier — these are correct tools for this. They create an encrypted overlay network between your devices. Nobody else can see or reach your services. If all you want is to check your Home Assistant dashboard from a hotel, stop reading here and set up Tailscale. It is good software that solves this problem well.

The second problem: "I want other people to use my services." You want your family on Immich without installing a VPN client on their phones. You want friends to stream from your Jellyfin. You want to share a Nextcloud folder with a collaborator. This is a public access problem. No VPN solves it, because the entire point is that the other party should not need special software. This is the problem the rest of the post addresses.

The community treats these as the same question with the same answer. They are not. And the belief that public exposure is inherently dangerous has quietly become the default position without much examination of what, exactly, the danger is supposed to be.
This is how the internet works

Every website you have ever visited runs on the same architecture you would use to expose Jellyfin from your house. A DNS record points a domain name to an IP address. Traffic arrives on ports 80 and 443. A reverse proxy terminates TLS, inspects the request, and routes it to a backend service. The backend service runs in a container, a VM, or a process on bare metal.

Your bank does this. Every SaaS product you pay for does this. The blog post telling you not to do this was served to your browser using exactly this method. There is nothing experimental about it. The architecture is decades old and is the most scrutinized, battle-tested pattern in all of computing.

The difference between your homelab and a production deployment at a mid-size company is operational maturity — monitoring, patching cadence, redundancy. It is not a fundamental architectural gap. The stack is the same.
"But my IP is exposed"

This is the most common objection, and it is the weakest. Your residential IP address is already visible to every website you visit, every multiplayer game you play, every email you send (depending on your provider), and every person on your local network. It is not a secret. It has never been a secret. Hosting a service on it does not meaningfully change its exposure.

The question is not "can someone find my IP." The question is "what can they reach when they do." If the answer is a TLS-terminating reverse proxy on port 443 and nothing else — no other forwarded ports, no UPnP, no services bound to 0.0.0.0 on random high ports — then the attack surface is small, well-defined, and identical to what every web server on the internet presents.

An attacker knowing your IP address is not a threat model. It is a precondition that already exists. Treating it as the threat itself leads to tunnel-dependency that solves a problem you did not actually have.
Docker

Docker does not make a service secure. It makes a breach containable.

Containers share the host kernel. A kernel-level exploit — a privilege escalation bug in the Linux kernel itself — can break out of any container and reach the host. This is a real attack class. It is also rare, requires a specific unpatched CVE, and is not the kind of thing automated scanners attempt against residential IPs. For the self-hosting threat model, it is a background risk, not a primary concern.

What Docker does provide is process, filesystem, and memory isolation between containers. Two containers on the same bridge network can reach each other's listening ports over TCP/IP. They cannot read each other's files, inspect each other's processes, or access each other's memory. A compromised Jellyfin container does not grant any shortcut into your Radarr container — an attacker would need a second, independent exploit against Radarr's network-accessible service. That is not "container hopping." That is two entirely separate attacks.

Three Four rules (Thanks for the comments highlighting an additional) determine whether your Docker setup provides meaningful isolation, and this is exactly how I've been doing it, and hosting my own services for roughly 10 years (before that things were different).

Segment networks by trust level. Group containers that need to communicate on the same bridge network. Your media stack (Jellyfin, Radarr, Sonarr, Prowlarr) belongs together. They make API calls to each other and that is correct design. Your password manager (Vaultwarden) does not belong on that network. Your reverse proxy sits on a frontend network that connects to each service's published port but does not bridge your backend networks together.

Do not mount the Docker socket. Mounting /var/run/docker.sock into a container gives that container full root-equivalent control over the Docker daemon, which means control over every container and the host. This deserves special attention because popular tools in the self-hosting community require it. Portainer requires it for container management. Watchtower requires it for automatic updates. Traefik requires it (in its default configuration) for Docker service discovery. These are useful tools. Using them is a calculated tradeoff, not a security failure. But you should understand what you are granting: any vulnerability in Portainer becomes a vulnerability in everything. Keep socket-mounted containers on a separate, minimal network, keep them updated, and understand that they occupy a privileged position in your stack. I personally choose not to use any containers that run with full root access.

Do not use --privileged or --network host. Privileged mode disables nearly all container isolation. Host networking removes the network namespace boundary entirely, making the container's network stack identical to the host's. Either one effectively deletes the containment that makes Docker useful as a blast-radius tool.

By default, Docker containers can reach your LAN A compromised container could probe your NAS, printer, or IoT devices. Block Docker bridge subnets from your LAN range with an iptables rule. For containers that need NAS storage, mount the share on the host and bind-mount individual paths into the container so the container accesses files through the host filesystem, not the network. ie: -v /mnt/media:/media
Gotcha

Docker's firewall bypass catches people regularly. When you publish a port in Docker with -p 8080:8080, Docker binds it to 0.0.0.0 on the host and writes iptables rules that bypass your host firewall entirely. If you have ufw configured to deny all incoming traffic, Docker does not care. It manipulates iptables directly, at a level that sits below ufw and firewalld. Your firewall says "deny all." Docker has already punched a hole around it. Sidenote: This is exactly why people say you can't run docker on Proxmox, but they're also wrong, it's just a pain and not recommended.

This means a container with -p 8080:8080 is reachable from the public internet if your router forwards that port — or if UPnP is enabled and something requests it. Many self-hosters discover this the hard way, after assuming their firewall was protecting services that were, in fact, wide open.

The fix is straightforward. Any service that should only be reached through your reverse proxy should bind to localhost: -p 127.0.0.1:8080:8080. This restricts the published port to the loopback interface. The reverse proxy, running on the same host, can reach it. The outside world cannot. Your reverse proxy's ports (80 and 443) are the only ones that should ever bind to 0.0.0.0.

While you are at it, disable UPnP on your router. UPnP allows any application on your network to silently open ports on the router without authentication. It is a convenience feature designed for a threat model that no longer exists. Turn it off. It's pretty easy to find what ports are needed for specific things and a clean list of port forwards in your router is simple to manage.

Verify your exposure. After setting everything up, scan your own public IP from an external network. Use an online port scanner, or run nmap against your public address from a VPS or a friend's machine. You should see port 443 open (and optionally 80 for the HTTPS redirect). Nothing else. If you see anything else, something is misconfigured. Fix it before you do anything else.
A reference architecture

Concretely, the stack looks like this:

Domain and DNS. Register a domain. Point it at your public IP. If your ISP assigns dynamic addresses (most residential ISPs do), run a DDNS client — ddclient, the one built into your router, or a container like oznu/cloudflare-ddns. This updates your DNS record automatically when your IP changes. Dynamic IPs are not an obstacle. They are solved. OPNSense and PFSense have them built in.

Optionally, enable Cloudflare's DNS proxy (orange cloud) on your A record. This provides DDoS absorption and hides your origin IP from DNS lookups, without routing your traffic through a tunnel or allowing Cloudflare to terminate your TLS.

Router. Forward ports 80 and 443 only. Disable UPnP. That is the entire router configuration. But a big take away here is that self hosting starts at your networking/routing/firewall.

Reverse proxy. Caddy or Traefik, running in a Docker container on a frontend network. Caddy is the simpler choice for this audience — automatic HTTPS with zero configuration beyond the Caddyfile, sane TLS defaults out of the box. The reverse proxy is the only container with ports bound to 0.0.0.0.

Service containers. Each service group on its own backend Docker bridge network. The reverse proxy connects to each backend network to reach the services it proxies. Services bind to localhost (127.0.0.1) or are not published to the host at all (using Docker's internal networking). Media stack on one network. Productivity tools on another. Password manager isolated. Services that need to talk to each other (Jellyfin ↔ Radarr ↔ Sonarr) share a network. Services that do not need to talk to each other do not.

TLS. Handled automatically by the reverse proxy via ACME (Let's Encrypt or similar). You do not manage certificates manually. You do not think about cipher suites. The proxy does this correctly by default.
Tunnels

Tunnels are not wrong. They solve real problems. If you are behind CGNAT and cannot get a public IP, a tunnel or a VPS relay is your only option. If you do not want to learn reverse proxy configuration, Cloudflare Tunnel is a one-click solution that works. If your threat model genuinely includes targeted attacks and you want to minimize your public footprint, outbound-only tunnels reduce your exposure. These are legitimate reasons to use them.

Cloudflare Tunnel terminates TLS at Cloudflare's edge. Your traffic is decrypted at their infrastructure, inspected (or at least inspectable), and re-encrypted before being forwarded to your origin. This is a man-in-the-middle by design. Cloudflare states they do not inspect content, but they technically can, and you have no way to verify that they do not. Their free tier also includes usage restrictions that prohibit serving large volumes of non-web content — which directly conflicts with what most self-hosters run. Jellyfin libraries, Immich photo collections, Nextcloud file shares. Cloudflare has enforced these restrictions selectively, and accounts have been flagged.

The point is not that tunnels are insecure or that you should avoid them. The point is that they are one option in a space where the community has quietly decided they are the only option. When you run your own reverse proxy with your own TLS certificates, end-to-end encryption is genuinely end-to-end. You control the certificate, the termination point, and the traffic path. No third party decrypts your data at any point in transit. It is the RIGHT WAY to host your services.
VPNs

Tailscale is better in this respect. It uses WireGuard, which provides true end-to-end encryption between nodes. The Tailscale coordination server handles key exchange and NAT traversal but does not see your traffic. However, Tailscale solves the private access problem, not the public access problem. You cannot give your family a URL that works in a normal browser without Tailscale Funnel, which is a different product with its own limitations.
Minimum Recommended Secure Setup

    Forward only ports 80 and 443 on your router. Nothing else.
    Disable UPnP on your router.
    Run a reverse proxy (Caddy or Traefik) as your only public-facing service.
    Bind all other container ports to 127.0.0.1, not 0.0.0.0.
    Segment Docker networks by trust level. Do not run everything on a single flat network.
    Do not mount the Docker socket unless you understand the tradeoff (Portainer, Watchtower, Traefik Docker provider).
    Do not use --privileged or --network host.
    Block Docker bridge subnets from your LAN range with an iptables rule
    Keep your images updated. docker compose pull && docker compose up -d on a regular schedule, or use Watchtower with the socket tradeoff understood.
    Enable two-factor authentication on every service that supports it, and certainly use strong passwords.
    Only host well maintained applications.
    Use a DDNS client if your ISP assigns dynamic IPs.
    Scan your public IP from outside your network to verify only 80/443 are reachable.
    Check your reverse proxy access logs periodically. Run Uptime Kuma or similar to know when something goes down or behaves unexpectedly.

That is it. That is the same posture as a production web service. The tools are mature, the patterns are well understood, and the architecture is the one that runs the rest of the internet. You do not need a tunnel to do this safely. You need to understand what you are running, and configure it with intention.
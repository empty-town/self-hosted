# Host & base OS setup

> **Scope note.** This is a transparency record of everything *I* did to stand up the demo, not part of the guide. The reader's server and OS are out of scope for the guide. Bring your own home server.

**Environment:** DigitalOcean droplet — 1 vCPU / 1 GB RAM / 25 GB SSD, **Debian 13 (trixie)**, minimal image. Logged in as `root` over SSH key. Date: 2026-08-03.

## Provider setup (done in the DO control panel)

- Created the droplet with SSH-key auth at creation.
- **Cloud Firewall, two inbound rules:**
  - TCP **80 + 443** from anywhere (HTTP/HTTPS).
  - TCP **22 (SSH)** from **my IP only**.
  - Everything else denied inbound; outbound left open.

> Home-server equivalent: the cloud firewall becomes the router's port-forward for 80/443. The SSH-from-my-IP rule has no home equivalent and isn't needed — it's a VPS convenience.

## 1. Update

```bash
apt update && apt upgrade -y
# rebooted (kernel updated)
```

## 2. Non-root sudo user (`deploy`)

```bash
adduser --disabled-password --gecos "" deploy
usermod -aG sudo deploy
rsync --archive --chown=deploy:deploy ~/.ssh /home/deploy
# passwordless sudo (box is key-only, user has no password):
echo "deploy ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/deploy
chmod 440 /etc/sudoers.d/deploy
```

> Note: passwordless sudo and (later) `docker` group membership are each **root-equivalent**. That's an accepted convenience on this disposable, dummy-data demo box. On a server holding real family data, require a sudo password and treat any account in the `docker` group as root when you decide who gets it.

## 3. Verified new user before hardening

From a second terminal (kept the root session open as a fallback):

```bash
ssh deploy@<droplet-ip>
sudo whoami        # -> root  ✓
```

## 4. SSH hardening

```bash
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/;
             s/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

Result: key-only auth, no root login. (Layered on top of the DO SSH-from-my-IP firewall rule.)

## 5. Swap + swappiness

**Used 4 GB** of swap as insurance for the memory-hungry xcaddy (Go) build on a 1 GB box.

```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swap.conf
sudo sysctl --system
```

## 6. Unattended security upgrades

```bash
sudo apt install -y unattended-upgrades
echo 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";' | sudo tee /etc/apt/apt.conf.d/20auto-upgrades
```

## 7. Docker CE + log rotation

Official docker.com script (Debian's `docker.io` lags), plus global json-file log rotation so container logs can't fill the 25 GB disk.

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker deploy
sudo mkdir -p /etc/docker
echo '{ "log-driver": "json-file", "log-opts": { "max-size": "10m", "max-file": "3" } }' \
  | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker
```

Verified (after re-login for the `docker` group):

```bash
docker run --rm hello-world   # -> "Hello from Docker!"  ✓
free -h                       # Swap: 4.0Gi total  ✓
```

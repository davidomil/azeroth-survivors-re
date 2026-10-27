# Docker Compose

## Start the game

Requires Docker Engine with Compose v2 or later. The build downloads the
pinned Rust/WASM toolchain and compiles the browser client and native
asset host. Rendering runs on the player’s device; the server needs no
GPU, realm, or database.

``` bash
git clone https://github.com/davidomil/azeroth-survivors-re.git
cd azeroth-survivors-re
cp .env.example .env
```

Set the address and storage location in `.env` before starting. Defaults
serve this computer at `https://localhost:8443/`. For a private LAN
server, use its address for both `GAME_HOST` and `BIND_ADDRESS`.

``` bash
# Example .env for the requested LAN host
GAME_HOST=192.168.8.100
BIND_ADDRESS=192.168.8.100
HTTPS_PORT=8443
WOW_DATA_DIR=/mnt/big-disk-fast/azeroth-survivors/wow-data
```

`WOW_DATA_DIR` is the parent of `Data/`. Create that directory on a
filesystem with enough space before fetching. The game mount fails if
`Data/` is absent. Ports used by other applications are independent of
this Compose project.

## Prepare game data and build

Supply the English WoW 1.12.1 build 5875 `Data/` directory at
`$WOW_DATA_DIR/Data/`, or run the upstream downloader through Compose:

``` bash
docker compose --profile tools run --rm --build fetch-data
```

The downloader temporarily stores both the roughly 5.5 GB archive and
the extracted MPQs. Reserve at least 12 GB for this step, plus separate
space for Docker’s Rust build cache. `WOW_DATA_URL` can specify another
direct ZIP containing `Data/*.MPQ`. Game data stays outside the runtime
image and repository.

``` bash
docker compose config --quiet
docker compose up -d --build --wait --wait-timeout 120
```

The image build runs the upstream host and browser tests. Real-MPQ host
tests skip during the image build because the build contains no game
data. The running game’s health check reads both the page and
`DBFilesClient\Map.dbc` from the mounted data.

## Trust HTTPS on each playing device

The browser world needs WebGPU and a secure context. Caddy issues a
certificate for `GAME_HOST` from its own persistent local CA. Export the
public CA certificate:

``` bash
docker compose cp caddy:/data/caddy/pki/authorities/local/root.crt ./azeroth-survivors-root.crt
```

Transfer that certificate to each playing device and install it as a
trusted root in the operating system or browser certificate settings.
Restart the browser, then open `https://192.168.8.100:8443/` for the LAN
example. The certificate must be trusted; an HTTPS response alone does
not verify browser WebGPU availability.

Use a browser/device with WebGPU support. Check `navigator.gpu` in its
developer console if the world cannot start. See [Chrome’s WebGPU
troubleshooting](https://developer.chrome.com/docs/web-platform/webgpu/troubleshooting-tips)
and [Caddy’s Docker certificate
instructions](https://caddyserver.com/docs/running#local-https-with-docker).

This deployment serves your game files to the selected private address
without login. Keep that address on your private LAN. The survivors game
does not use the host’s legacy WebSocket relay; the proxy blocks
`/ws/*`.

## Operate and update

``` bash
docker compose ps
docker compose logs --tail 50 game caddy
curl --cacert ./azeroth-survivors-root.crt -I https://192.168.8.100:8443/
```

To update this checkout and rebuild:

``` bash
git pull --ff-only
docker compose up -d --build --wait --wait-timeout 120
```

A resource-constrained server can run an image built on another machine
of the same CPU architecture. From the build machine:

``` bash
docker compose build game
docker image save azeroth-survivors:local | ssh david@192.168.8.100 docker image load
ssh david@192.168.8.100 'cd ~/azeroth-survivors && docker compose up -d --no-build --wait --wait-timeout 120'
```

The server needs the same fork revision and its own `.env` before that
command. `docker compose down` stops this project while preserving data
and certificates. Keep the Caddy volumes when recreating services so
playing devices retain trust.

# Docker Images

Lean PHP-FPM base images for Laravel projects. Each PHP version ships in two variants (base + `-grpc`), with **nvm**-managed Node — the image ships Node 24 as the default, and projects switch to any other version with one command.

These images install **binaries and runtimes only** — `php.ini`, OPcache tuning, FPM pool config, `WORKDIR`, and `CMD` are intentionally left to downstream project Dockerfiles, since those vary per project.

## What's included

- PHP-FPM with `bcmath`, `exif`, `gd`, `gmp`, `intl`, `opcache`, `pcntl`, `pdo_mysql`, `pdo_pgsql`, `pdo_sqlite`, `sodium`, `zip`, plus PECL `redis`
- Optional PECL `grpc` (`-grpc` tag variants)
- Optional extra PHP extensions via `PHP_EXTENSIONS` build arg (e.g. `--build-arg PHP_EXTENSIONS="mysqli sockets calendar"`)
- Composer (pinned via `COMPOSER_VERSION`)
- **nvm** + Node 24 (default) at `/usr/local/nvm`; `node`/`npm`/`npx`/`yarn`/`pnpm`/`corepack` symlinked into `/usr/local/bin`
- `nvm-use` helper script — install + activate a different Node version in one line
- DB clients: `default-mysql-client`, `postgresql-client`, `sqlite3`
- Git (with `safe.directory '*'` set for root), Supervisor, `zip`/`unzip`, `xz-utils`, `ca-certificates`

## Tag matrix

| Tag | PHP | gRPC | Upstream support |
|---|---|---|---|
| `:7.4` / `:7.4-grpc` | 7.4 | no / yes | EOL — see [Security](#security) |
| `:8.0` / `:8.0-grpc` | 8.0 | no / yes | EOL — see [Security](#security) |
| `:8.1` / `:8.1-grpc` | 8.1 | no / yes | EOL — see [Security](#security) |
| `:8.2` / `:8.2-grpc` | 8.2 | no / yes | security fixes only |
| `:8.3` / `:8.3-grpc` | 8.3 | no / yes | active |
| `:8.4` / `:8.4-grpc` | 8.4 | no / yes | active |
| `:8.5` / `:8.5-grpc` | 8.5 | no / yes | active |
| `:latest` | 8.4 | no | alias for `:8.4` |

All tags come with Node 24 pre-installed. To use a different Node version inside your project image, see [Switching Node versions](#switching-node-versions) below.

## Security

Each Dockerfile tracks a floating `php:<minor>-fpm` base tag rather than pinning
a patch release, so **every rebuild picks up the newest upstream patch for that
branch automatically**. Bake sets `pull = true` to guarantee the floating tag is
re-resolved instead of being served from a stale local cache. Keeping these
images current is therefore a matter of rebuilding and pushing — no Dockerfile
edit is needed when upstream ships a fix.

### CVE-2026-109618 / CVE-2026-109619 ("php2shell")

A pre-auth RCE in `session.upload_progress`, reachable on any multipart POST
endpoint under default configuration. Upstream patched it on 2026-10-21 in PHP
8.2.35, 8.3.36, 8.4.27 and 8.5.12.

- **`:8.2` – `:8.5`** — carry the patched runtime as soon as they are rebuilt.
- **`:7.4`, `:8.0`, `:8.1`** — these branches are EOL and will never receive the
  fix. They instead ship
  [`laravel-php/conf.d/zzz-php2shell-mitigation.ini`](./laravel-php/conf.d/zzz-php2shell-mitigation.ini),
  which sets `session.upload_progress.enabled = Off`. The `zzz-` prefix makes it
  load after a project's own `conf.d` drop-ins so the feature cannot be
  re-enabled by accident. This is a mitigation, not a patch — **migrate off EOL
  PHP.**

Verify an image before deploying it:

```shell
docker run --rm puncoz/laravel-php:8.4 php -v
docker run --rm puncoz/laravel-php:8.1 php -i | grep session.upload_progress.enabled
```

## Setup

Create the multi-platform builder once:

```shell
docker buildx create --use --platform=linux/amd64,linux/arm64 --name multi-platform-builder
docker buildx inspect --bootstrap
```

## Build

All builds are driven by `docker-bake.hcl` at the repo root. A `Makefile` wraps the common commands — run `make help` to see them all.

```shell
make builder         # one-time: create the multi-platform buildx builder
make build           # build all 14 images locally for host arch
make push            # build + push all 14 images, multi-arch
make 8.4             # build 8.4 + 8.4-grpc locally
make push-8.4        # build + push 8.4 + 8.4-grpc, multi-arch
make print           # inspect resolved targets as JSON
make smoke           # quick single-image build to validate setup
```

The bake CLI works directly too:

```shell
docker buildx bake                          # all
docker buildx bake --push                   # all + push
docker buildx bake 'laravel-8-2*' --push    # one PHP version
docker buildx bake laravel-8-2 --push       # one specific tag
docker buildx bake --print                  # dry run
```

### Build args

| Variable | Default | What it controls |
|---|---|---|
| `REGISTRY` | `puncoz` | Image registry |
| `IMAGE_NAME` | `laravel-php` | Repository name |
| `PHP_VERSIONS` | `["7.4", "8.0", "8.1", "8.2", "8.3", "8.4", "8.5"]` | PHP branches to build |
| `DEFAULT_PHP_VERSION` | `"8.4"` | PHP version that owns `:latest` |
| `COMPOSER_VERSION` | `"2.10.1"` | Pinned Composer release |
| `NVM_VERSION` | `"0.40.5"` | Pinned nvm release |
| `DEFAULT_NODE_VERSION` | `"24"` | Node version pre-installed in the base |
| `PHP_EXTENSIONS` | `""` | Extra extensions to install via `docker-php-ext-install` (space-separated) |
| `PLATFORMS` | `["linux/amd64", "linux/arm64"]` | Target arches |

Override per-invocation, e.g. to downgrade the baked default to Node 20 or to bundle extra extensions:

```shell
DEFAULT_NODE_VERSION=20 docker buildx bake --push
PHP_EXTENSIONS="mysqli sockets calendar" docker buildx bake --push
```

## Switching Node versions

The base image ships with Node 24 active. To use a different version inside your project's Dockerfile:

**Pin via `.nvmrc`** (recommended — keeps the version next to your code):

```dockerfile
FROM puncoz/laravel-php:8.4

COPY .nvmrc ./
RUN nvm-use
```

**Or specify explicitly:**

```dockerfile
RUN nvm-use 20
```

`nvm-use` does three things: `nvm install <version>`, re-aliases it as `default`, and re-links `node`/`npm`/`yarn`/`pnpm` symlinks under `/usr/local/bin` so they're picked up by non-bash shells (sh, php-fpm, supervisor).

If Node 24 (the baked-in default) is fine, you don't need to call `nvm-use` at all — `node`, `npm`, `yarn`, and `pnpm` are already on `PATH`.

## Using the base image in a project

See [`example/`](./example) for a full production-ready setup: multi-stage Dockerfile, `.nvmrc`, tuned `php.ini` / OPcache / FPM config, and an entrypoint that runs `php artisan optimize` at container start. Copy `example/Dockerfile`, `example/.dockerignore`, `example/.nvmrc`, and `example/docker/` into your Laravel project root.

Minimal sketch:

```dockerfile
FROM puncoz/laravel-php:8.4 AS app
WORKDIR /var/www/html

COPY .nvmrc ./
RUN nvm-use

COPY docker/php/opcache.ini  /usr/local/etc/php/conf.d/10-opcache.ini
COPY docker/php/php.ini      /usr/local/etc/php/conf.d/zz-app.ini
COPY docker/php-fpm/www.conf /usr/local/etc/php-fpm.d/zz-app.conf

COPY . .
RUN composer install --no-dev --optimize-autoloader \
    && npm ci && npm run build \
    && php artisan optimize

CMD ["php-fpm", "--nodaemonize"]
```

## Publishing to Docker Hub

```shell
docker login
docker buildx bake --push
```

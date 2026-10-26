// docker-bake.hcl
// Matrix-built Laravel base images: PHP version × gRPC on/off.
// Node is managed via nvm at runtime — see `nvm-use` inside the image.
//
// Usage:
//   docker buildx bake                              # build everything
//   docker buildx bake --push                       # build + push all
//   docker buildx bake 'laravel-8-2*'               # 8.2 (base + grpc)
//   docker buildx bake laravel-8-2 --push           # one specific tag
//   docker buildx bake --print                      # inspect resolved targets
//
// Override defaults via env or `--set`:
//   REGISTRY=myorg IMAGE_NAME=php-laravel docker buildx bake --push
//   DEFAULT_NODE_VERSION=20 docker buildx bake          # bake-in Node 20 default
//   docker buildx bake --set '*.platform=linux/amd64'

variable "REGISTRY" {
  default = "puncoz"
}

variable "IMAGE_NAME" {
  default = "laravel-php"
}

variable "PHP_VERSIONS" {
  default = ["7.4", "8.0", "8.1", "8.2", "8.3", "8.4", "8.5"]
}

// The PHP version that owns the `:latest` tag.
variable "DEFAULT_PHP_VERSION" {
  default = "8.4"
}

variable "COMPOSER_VERSION" {
  default = "2.10.1"
}

variable "NVM_VERSION" {
  default = "0.40.5"
}

// Pinned so the grpc build stage has a stable cache key. Unpinned, `pecl
// install grpc` silently follows the latest release and rebuilds for ~15 min
// whenever upstream publishes one.
variable "GRPC_VERSION" {
  default = "1.84.0"
}

// Node version pre-installed via nvm and aliased as `default`. Projects can
// switch with `nvm-use <other>` in their own Dockerfile.
variable "DEFAULT_NODE_VERSION" {
  default = "24"
}

// Extra PHP extensions to install via docker-php-ext-install (space-separated).
// Only works for extensions whose runtime libs ship in the base — others must
// be installed in a downstream Dockerfile.
variable "PHP_EXTENSIONS" {
  default = ""
}

// amd64 only. arm64 has no native builder here, so bake would cross-build it
// under QEMU — which turns the grpc compile (~3000 vendored C++ units) from
// roughly 15 minutes into the better part of an hour. Add "linux/arm64" back
// only alongside a native arm64 builder node.
variable "PLATFORMS" {
  default = ["linux/amd64"]
}

group "default" {
  targets = ["laravel"]
}

target "laravel" {
  name = "laravel-${replace(php, ".", "-")}${grpc == "true" ? "-grpc" : ""}"

  matrix = {
    php  = PHP_VERSIONS
    grpc = ["false", "true"]
  }

  context    = "."
  dockerfile = "./laravel-php/laravel-php-${php}.Dockerfile"
  platforms  = PLATFORMS

  // The Dockerfiles track floating `php:<minor>-fpm` tags so every rebuild picks
  // up the newest upstream patch release. Without this, a stale locally-cached
  // base would silently keep shipping an unpatched PHP.
  pull = true

  args = {
    COMPOSER_VERSION     = COMPOSER_VERSION
    NVM_VERSION          = NVM_VERSION
    DEFAULT_NODE_VERSION = DEFAULT_NODE_VERSION
    INSTALL_GRPC         = grpc
    GRPC_VERSION         = GRPC_VERSION
    PHP_EXTENSIONS       = PHP_EXTENSIONS
  }

  tags = concat(
    ["${REGISTRY}/${IMAGE_NAME}:${php}${grpc == "true" ? "-grpc" : ""}"],
    php == DEFAULT_PHP_VERSION && grpc == "false"
      ? ["${REGISTRY}/${IMAGE_NAME}:latest"]
      : []
  )

  labels = {
    "org.opencontainers.image.title"   = "${IMAGE_NAME}"
    "org.opencontainers.image.source"  = "https://github.com/puncoz/laravel-docker-images"
    "org.opencontainers.image.version" = "${php}${grpc == "true" ? "-grpc" : ""}"
  }
}

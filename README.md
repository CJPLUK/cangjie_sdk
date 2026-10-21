# Cangjie SDK build framework

This repository is used to pin down versions of relevant repos to build a fork of the Cangjie SDK (with deferred effect handlers in certain branches), including the versions of some third party dependencies to keep the build system reproducible (and not time-dependent).

A biproduct is to build the custom SDK to host on the Cangjie UK website. The goal is to set up containerised builds for all the supported platforms. Maybe later this could also include CI testing pinned down to specific revisions of cangjie_test and cangjie_test_framework.

## Cloning
This repo makes use of git submodules so make sure to `git clone` with the `--recurse-submodules`... or if you forgot to do that the first time, you can run `git submodule update --init`.

## Build (plain)

With the environment set up as dictated by cangjie_build, you can build the SDK with:
```shell
// linux:
bash build_scripts/linux/all.sh // observed to work on linux/x64
// mac:
bash build_scripts/mac/all.sh // observed to work on macos/aarch64
```

## Build (containerized)

There are services defined in `compose.yaml` which will build the SDK for different targets. These will appear as a .tar.gz file under the software/cangjie directory. 

### Linux/x86_64
```shell
FIXUID=`id -u` docker compose run --rm build-sdk-linux64
```

### Linux/aarch64
```shell
FIXUID=`id -u` docker compose run --rm build-sdk-linuxarm
```

## Containerized unrestricted vibing (opencode)

First copy the credentials from your host opencode (v2) install into the `opencode-data` volume using `opencode auth export`/`opencode auth import`.
Rerun this whenever your host credentials change.
The first argument selects the compose provider and defaults to `docker compose`.
`podman-compose` also picks up `podman-compose.yaml` automatically.

```shell
container/opencode-import-auth.sh ["docker compose"|podman-compose|"nerdctl compose"]
```

Then start containerized sessions with:
```shell
FIXUID=`id -u` docker compose run --rm opencode
```

The image is only built if missing, so add `--build` after changing the `Containerfile` or `container/opencode.json`.

Credentials and sessions persist in the `opencode-data` volume; remove it with `docker compose down -v` to start fresh.

### Others
TODO (with cross compilation instructions)

For cross compilation to windows, it appears the container images have the necessary toolchain already, it may work with the following env var:
```shell
MINGW_PATH=/opt/buildtools/llvm-mingw-w64
```

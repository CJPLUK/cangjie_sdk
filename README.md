# Cangjie SDK build framework

This repository is used to pin down versions of relevant repos to build a fork of the Cangjie SDK (with deferred effect handlers in certain branches), including the versions of some third party dependencies to keep the build system reproducible (and not time-dependent).

A biproduct is to build the custom SDK to host on the Cangjie UK website. The goal is to set up containerised builds for all the supported platforms. Maybe later this could also include CI testing pinned down to specific revisions of cangjie_test and cangjie_test_framework.

## Cloning
This repo makes use of git submodules so make sure to `git clone` with the `--recurse-submodules`... or if you forgot to do that the first time, you can run `git submodule update --init`.

## Build (plain)

With the environment set up as dictated by cangjie_build, you can build the SDK with:
```shell
// linux:
bash build_scripts/linux/all.sh
// mac:
bash build_scripts/mac/all.sh
```

## Build (containerized)

There are services defined in `compose.yaml` which will build the SDK for different targets. These will appear as a .tar.gz file under the software/cangjie directory. 

**docker**
```shell
FIXUID=`id -u` docker-compose run --rm build-sdk
```

**podman**
```shell
podman-compose run --rm build-sdk
```

## Dev service

You can start the `dev` service to start a container:
```

Commands can then be run inside with:
```
podman-compose exec dev bash -i
```

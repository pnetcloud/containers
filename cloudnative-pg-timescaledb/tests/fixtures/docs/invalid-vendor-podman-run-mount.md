The build mounts the reference checkout into a runtime container:

```sh
podman run --mount type=bind,source=vendor,target=/vendor,readonly ghcr.io/example/build:latest ./build.sh
```

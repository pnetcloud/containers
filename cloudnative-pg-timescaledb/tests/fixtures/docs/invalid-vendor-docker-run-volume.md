The build mounts the reference checkout into a runtime container:

```sh
docker run --rm -v "$PWD/vendor:/vendor:ro" ghcr.io/example/build:latest ./build.sh
```

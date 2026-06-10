The build stores a parent-relative reference checkout path in a variable:

```sh
CTX="$PWD/../vendor"
docker build "$CTX"
```

BuildKit receives the reference checkout as a named build context:

```sh
docker build --build-context=deps=vendor .
```

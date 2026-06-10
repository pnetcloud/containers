A workflow must not execute local actions from the reference checkout:

```yaml
steps:
  - uses: cloudnative-pg-timescaledb/vendor/actions/build
```

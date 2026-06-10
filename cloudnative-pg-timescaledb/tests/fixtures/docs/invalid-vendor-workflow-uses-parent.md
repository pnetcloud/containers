A workflow must not execute parent-relative actions from the reference checkout:

```yaml
steps:
  - uses: ../vendor/actions/build
```

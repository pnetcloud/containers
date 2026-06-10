The build stores the reference checkout in a variable and uses it as context:

```sh
ctx=vendor/
docker build "$ctx" --push
```

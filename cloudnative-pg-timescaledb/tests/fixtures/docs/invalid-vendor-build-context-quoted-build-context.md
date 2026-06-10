The image build injects the reference checkout as a named context:

```sh
docker build --build-context deps="./vendor" .
```

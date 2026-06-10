declare -A CTX
CTX[deps]=vendor
docker build "${CTX[@]}"

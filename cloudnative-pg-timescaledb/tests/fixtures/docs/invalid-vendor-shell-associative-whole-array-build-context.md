declare -A CTX=([deps]=vendor)
docker build "${CTX[@]}"

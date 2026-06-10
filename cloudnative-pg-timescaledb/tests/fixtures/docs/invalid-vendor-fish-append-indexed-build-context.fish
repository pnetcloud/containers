set CTX other
set --append CTX vendor
docker build $CTX[-1]

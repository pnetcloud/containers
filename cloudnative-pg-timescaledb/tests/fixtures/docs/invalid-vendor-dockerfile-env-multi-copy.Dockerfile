FROM scratch
ENV FOO=bar VENDOR_DIR=vendor
COPY ${VENDOR_DIR}/ /app/vendor/

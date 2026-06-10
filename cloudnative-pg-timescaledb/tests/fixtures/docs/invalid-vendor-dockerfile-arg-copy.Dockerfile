FROM scratch
ARG VENDOR_DIR=vendor
COPY ${VENDOR_DIR}/ /app/vendor/

FROM scratch
ENV VENDOR_DIR vendor
COPY ${VENDOR_DIR}/ /app/vendor/

# Invalid Vendor Dockerfile Forms

COPY --chmod=0755 vendor/ /app/vendor/

COPY ["vendor/", "/app/vendor/"]

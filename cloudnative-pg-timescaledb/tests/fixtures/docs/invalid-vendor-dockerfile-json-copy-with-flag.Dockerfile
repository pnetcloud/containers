FROM scratch
COPY --chmod=0755 ["vendor/", "/app/vendor/"]

FROM scratch AS vendor
COPY --from=vendor /usr/lib/postgresql /usr/lib/postgresql

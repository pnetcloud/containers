# Invalid Vendor BuildKit Mount

RUN --mount=type=bind,source=vendor,target=/vendor make build

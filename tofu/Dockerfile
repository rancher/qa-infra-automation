# This can be built from the root directory with the command:
# docker build -t tofu-runner -f tofu/Dockerfile .

# Use this image to run the OpenTofu CLI in a container. 
# This is a very minimal image that just has the OpenTofu binary and its dependencies, so it should be very lightweight and fast to start up. 
# It can be used in CI pipelines or other environments where you want to run OpenTofu commands without installing it on the host machine.

FROM alpine:latest
RUN apk add --no-cache opentofu
WORKDIR /tofu
ENTRYPOINT ["/bin/sh"]

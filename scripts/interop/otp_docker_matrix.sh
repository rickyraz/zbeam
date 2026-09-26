#!/bin/sh
# Linux host networking lets containerized OTP reach the host's loopback peer.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
wrappers=$(mktemp -d)
trap 'rm -rf "$wrappers"' EXIT
trap 'exit 130' INT TERM
for version in 25 26 27; do
    case "$version" in
        25) image=erlang@sha256:d838e3fd8b61d29f60be47e826253d97e5758a22cbf070b9686365fa8b498106 ;;
        26) image=erlang@sha256:cb3039645b89c9fbae3beb608e55cd06df131328d608a1e51beb2bce8ef3a2d3 ;;
        27) image=erlang@sha256:f64e891340b38f89adc33e63be00eb027bffa84481f230f981422707efe3fa5e ;;
    esac
    docker image inspect "$image" >/dev/null 2>&1 || docker pull "$image"
    printf '#!/bin/sh\nexec docker run --rm --network host "%s" erl "$@"\n' "$image" >"$wrappers/erl$version"
    chmod +x "$wrappers/erl$version"
    export "OTP_ERL_$version=$wrappers/erl$version"
    echo "OTP $version image: $image"
done
ZBEAM_REQUIRE_ALL_OTP=1 OTP_VERSIONS='25 26 27' "$root/scripts/interop/otp_matrix.sh"

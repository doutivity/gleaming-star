# Mission Control — task runner. Everything runs inside Docker; the host only needs docker and just.

# Keep in sync with GLEAM_VERSION in the Dockerfile.
gleam_image := "ghcr.io/gleam-lang/gleam:v1.19.2-erlang"
packages := "shared server client"

# Run a command in the Gleam image, with the repo mounted and files owned by the current user.
docker_gleam := "docker run --rm -u $(id -u):$(id -g) -e HOME=/tmp -v \"$PWD\":/work " + gleam_image

default:
    @just --list

# Build and start the app in the foreground: http://localhost:8000
up:
    docker compose up --build

# Build and start the app in the background
up-d:
    docker compose up --build -d

# Stop and remove the containers
down:
    docker compose down

# Follow the app logs
logs:
    docker compose logs -f mission-control

# Run every test (format check + gleam test in all packages) in Docker
test:
    docker compose --profile test run --rm --build test

# Format all Gleam sources
fmt:
    {{ docker_gleam }} sh -c 'for p in {{ packages }}; do (cd /work/$p && gleam format src test); done'

# Check formatting without changing files
fmt-check:
    {{ docker_gleam }} sh -c 'for p in {{ packages }}; do (cd /work/$p && gleam format --check src test) || exit 1; done'

# Run `gleam <args>` in one package, e.g. `just gleam server add mist` or `just gleam shared test`
gleam package *args:
    {{ docker_gleam }} sh -c 'cd /work/{{ package }} && gleam {{ args }}'

# Probe the running app: /health plus the index page
check:
    curl -fsS localhost:8000/health && echo
    curl -fsS -o /dev/null -w "/ -> %{http_code}\n" localhost:8000/

# Stream the live event feed from /ws (Ctrl-C to stop). Extra args go to websocat, e.g. `just ws -E`
ws *args:
    docker run --rm -i --network host ghcr.io/vi/websocat:nightly -t {{ args }} ws://localhost:8000/ws

# Remove containers, images built by compose and local build artefacts
clean:
    docker compose --profile test down --rmi local --remove-orphans
    rm -rf shared/build server/build client/build

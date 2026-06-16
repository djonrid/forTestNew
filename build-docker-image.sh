#!/bin/sh
set -e

PROJECT_NAME=${VERSIONIZE_PROJECT_NAME:-Granch.RTServerCore}
TAG_PREFIX="${PROJECT_NAME}-v"
BASE_NAME=${DOCKER_IMAGE_NAME:-sw_develop/granch.scada.rtserver}
GITEA_HOST=${DOCKER_REGISTRY:-gitea.granch.local:3000}
DOCKERFILE_PATH=${DOCKERFILE_PATH:-./Granch.RTServerCore/Dockerfile}

resolve_version() {
  if [ -n "${VERSION:-}" ]; then
    printf '%s\n' "$VERSION"
    return
  fi

  latest_tag=$(git describe --tags --match "${TAG_PREFIX}*" --abbrev=0 2>/dev/null || true)
  if [ -n "$latest_tag" ]; then
    printf '%s\n' "${latest_tag#$TAG_PREFIX}"
    return
  fi

  if [ -f ./version.json ]; then
    grep AssemblyInformationalVersion ./version.json | cut -d'"' -f4
    return
  fi

  echo "Unable to resolve version. Run versionize or set VERSION." >&2
  exit 1
}

VERSION=$(resolve_version)

if [ -z "$VERSION" ]; then
  echo "Resolved version is empty." >&2
  exit 1
fi

echo "Building $BASE_NAME:$VERSION"
mkdir -p ./images

DOCKER_BUILDKIT=1 docker rmi --force "$GITEA_HOST/$BASE_NAME:$VERSION" || true
DOCKER_BUILDKIT=1 docker rmi --force "$BASE_NAME:$VERSION" || true

DOCKER_BUILDKIT=1 docker build --progress=plain -t "$BASE_NAME:$VERSION" \
  -f "$DOCKERFILE_PATH" .

DOCKER_BUILDKIT=1 docker tag "$BASE_NAME:$VERSION" "$GITEA_HOST/$BASE_NAME:$VERSION"
DOCKER_BUILDKIT=1 docker save "$BASE_NAME:$VERSION" | gzip > "./images/granch.scada.rtserver-$VERSION.tar.gz"
DOCKER_BUILDKIT=1 docker push "$GITEA_HOST/$BASE_NAME:$VERSION"

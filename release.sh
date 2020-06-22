#!/bin/bash

set -euo pipefail

if [[ -z "${1:-}" ]]; then
  echo "version not set" | chalk red
  exit 1
fi

VERSION=$(echo $1 | sed 's/^v//')

LATEST_VERSION=$(git tag | sort --version-sort | tail -n 1)

if [[ -z $LATEST_VERSION ]]; then
  LATEST_VERSION=$(git rev-list --max-parents=0 HEAD)
fi

echo "latest release: $LATEST_VERSION" | chalk green
echo "new version:    $VERSION" | chalk green

updated=""

if ! semver $VERSION -r "^$LATEST_VERSION" > /dev/null; then
  echo "breaking change!" | chalk yellow
  updated=$(ls functions)
fi

changed_files=$(git diff --name-status $LATEST_VERSION | grep -v "^D" | awk '{print $2}')

for d in $changed_files; do
  fdir=$(dirname $d)
  # if dependencies change, republish everything
  if [[ "$d" == "package-lock.json" ]]; then
    echo "detected a change in package-lock.json"
    updated=$(ls functions)
    break
  fi
  ! [[ $fdir =~ ^functions/ ]] && continue
  fname=$(dirname ${d:10})
  updated="$updated $fname"
done

REPO_SLUG=${GITHUB_REPOSITORY:-"FaaSterMetrics/test-functions"}
PACKAGE_PREFIX="@FaaSterMetrics/exp-test-"
PACKAGE_JSON="{\"name\":\"${PACKAGE_PREFIX}NAME\",\"version\":\"$VERSION\",\"publishConfig\":{\"registry\":\"https://npm.pkg.github.com/\"},\"repository\":{\"type\":\"git\",\"url\":\"ssh://git@github.com/${REPO_SLUG}.git\",\"directory\":\"functions/NAME\"}}"

for fname in $(echo $updated | tr ' ' '\n' | sort -u); do
  echo "publishing $fname" | chalk cyan
  fdir="functions/${fname}"
  echo "process.env.FAASTERMETRICS_FN_NAME='${fname}';$(cat $fdir/index.js)" > $fdir/_index.js
  npx ncc build $fdir/_index.js -o $fdir/build
  echo $PACKAGE_JSON | sed "s/NAME/${fname}/g" > $fdir/build/package.json
  npm publish $fdir/build
  rm -rf $fdir/build $fdir/_index.js
done

echo "done." | chalk green

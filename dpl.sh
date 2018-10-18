#!/bin/bash
set -euo pipefail

: ${PROJECT:=$(basename -s .git `git config --get remote.origin.url`)}
: ${CIRCLE_SHA1:=$(git rev-parse --verify HEAD)}
: ${CIRCLE_BRANCH:=$(git rev-parse --abbrev-ref HEAD)}

REGISTRY=575449495505.dkr.ecr.us-east-1.amazonaws.com
TAG=$REGISTRY/$PROJECT:git_$CIRCLE_SHA1
TAG_LATEST=$REGISTRY/$PROJECT:latest


function login {
    : ${AWS_ACCESS_KEY_ID?"Missing environment variable"}
    : ${AWS_SECRET_ACCESS_KEY?"Missing environment variable"}

    local SECRET=$(docker run --rm \
        -e REGISTRY=$REGISTRY \
        -e AWS_ACCESS_KEY_ID \
        -e AWS_SECRET_ACCESS_KEY \
        takumihq/amazon-ecr-credential-helper | \
        node -pe "JSON.parse(require('fs').readFileSync('/dev/stdin').toString()).Secret")

    docker login -u AWS -p $SECRET -e none $REGISTRY
}

function build {
    docker build --build-arg BUILD_VERSION=$CIRCLE_SHA1 -t $TAG_LATEST -t $TAG .
}

function push {
    docker push $TAG

    if [ "$CIRCLE_BRANCH" == "master" ]; then
        docker push $TAG_LATEST
    fi
}

function deploy {
    # args: default-context master-context
    local DEPLOYMENT_IMAGE=$REGISTRY/utilities:kubectl

    if [ "$CIRCLE_BRANCH" == "master" ]; then
        CONTEXT=$3
    else
        CONTEXT=$2
    fi

    docker pull $DEPLOYMENT_IMAGE > /dev/null

    echo "Deploying $TAG to $CONTEXT"

    docker run $DEPLOYMENT_IMAGE kubectl --context $CONTEXT set image deployment $PROJECT $PROJECT=$TAG
}

if [ `type -t $1`"" == 'function' ]; then
    $1
else
    echo "Usage: dpl [login build push deploy]"
    exit 1
fi
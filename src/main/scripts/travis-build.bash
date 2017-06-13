#!/bin/bash
# build, test, and publish maven projects on Travis CI

set -o pipefail

declare Pkg=travis-build-mvn
declare Version=0.4.0

function msg() {
    echo "$Pkg: $*"
}

function err() {
    msg "$*" 1>&2
}

function main() {
    msg "branch is ${TRAVIS_BRANCH}"

    local mvn="mvn --settings .settings.xml -B -V -U -Datomist.enabled=false"

    local project_version
    if [[ $TRAVIS_TAG =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(m|rc)\.[0-9]+)?$ ]]; then
        if ! mvn build-helper:parse-version versions:set -DnewVersion="$TRAVIS_TAG" versions:commit; then
            err "failed to set project version to $TRAVIS_TAG"
            return 1
        fi
        project_version=$TRAVIS_TAG
    else
        project_version=$(mvn help:evaluate -Dexpression=project.version | grep -E '^[0-9]+\.[0-9]+\.[0-9](-([0-9]{14}|SNAPSHOT))?$' | tail -n 1)
        if [[ $? != 0 || ! $project_version ]]; then
            err "failed to parse project version"
            return 1
        fi
    fi

    if ! $mvn install -Dmaven.javadoc.skip=true; then
        err "maven install failed"
        return 1
    fi

    if [[ $TRAVIS_PULL_REQUEST != false ]]; then
        msg "not deploying pull request"
        return 0
    fi

    if [[ $TRAVIS_BRANCH == master || $TRAVIS_TAG =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(m|rc)\.[0-9]+)?$ ]]; then
        if [[ $TRAVIS_REPO_SLUG == *-seed ]]; then
            msg "not deploying seed project"
        else
            if ! $mvn deploy -DskipTests; then
                err "maven deploy failed"
                return 1
            fi
        fi

        if ! git config --global user.email "travis-ci@atomist.com"; then
            err "failed to set git user email"
            return 1
        fi
        if ! git config --global user.name "Travis CI"; then
            err "failed to set git user name"
            return 1
        fi
        local git_tag=$project_version+travis$TRAVIS_BUILD_NUMBER
        if ! git tag "$git_tag" -m "Generated tag from TravisCI build $TRAVIS_BUILD_NUMBER"; then
            err "failed to create git tag: $git_tag"
            return 1
        fi
        local remote=origin
        if [[ $GITHUB_TOKEN ]]; then
            remote=https://$GITHUB_TOKEN@github.com/$TRAVIS_REPO_SLUG
        fi
        if ! git push --quiet --tags "$remote" > /dev/null 2>&1; then
            err "failed to push git tags"
            return 1
        fi
    fi
}

main "$@" || exit 1
exit 0

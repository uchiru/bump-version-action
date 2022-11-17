#!/bin/bash
set -o pipefail

# config
default_semvar_bump=${DEFAULT_BUMP:-minor}
with_v=${WITH_V:-false}
release_branches=${RELEASE_BRANCHES:-master,main}
custom_tag=${CUSTOM_TAG}
source=${SOURCE:-.}
dryrun=${DRY_RUN:-false}
initial_version=${INITIAL_VERSION:-0.0}
# since https://github.blog/2022-04-12-git-security-vulnerability-announced/
git config --global --add safe.directory /github/workspace

cd ${GITHUB_WORKSPACE}/${source}

echo "*** CONFIGURATION ***"
echo -e "\tDEFAULT_BUMP: ${default_semvar_bump}"
echo -e "\tWITH_V: ${with_v}"
echo -e "\tRELEASE_BRANCHES: ${release_branches}"
echo -e "\tCUSTOM_TAG: ${custom_tag}"
echo -e "\tSOURCE: ${source}"
echo -e "\tDRY_RUN: ${dryrun}"
echo -e "\tINITIAL_VERSION: ${initial_version}"

current_branch=$(git rev-parse --abbrev-ref HEAD)

pre_release="true"
IFS=',' read -ra branch <<< "$release_branches"
for b in "${branch[@]}"; do
    echo "Is $b a match for ${current_branch}"
    if [[ "${current_branch}" =~ $b ]]; then
        pre_release="false"
        continue
    fi
done
echo "pre_release = $pre_release"

# fetch tags
git fetch --tags

# get latest tag that looks like a ver (with or without v)
tag=$(basename $(git for-each-ref --sort=-v:refname --format '%(refname)' | grep -o "^refs/tags/v\?[0-9]\+\.[0-9]\+$" | head -1))

# trim 'v' if $with_v=false
if ! $with_v; then
  tag=$(echo $tag | tr -d 'v')
fi

# get current commit hash for tag
tag_commit=$(git rev-list -n 1 $tag)

# get current commit hash
commit=$(git rev-parse HEAD)

if [ "$tag_commit" == "$commit" ]; then
    echo "No new commits since previous tag. Skipping..."
    echo "tag=$tag" >> $GITHUB_OUTPUT
    exit 0
fi

# if there are none, start tags at INITIAL_VERSION which defaults to 0.0.0
if [ -z "$tag" ]; then
    log=$(git log --pretty='%B' | head -1)
    tag="$initial_version"
else
    log=$(git log $tag..HEAD --pretty='%B')
fi

echo $log

# this will bump the semvar using the default bump level,
# or it will simply pass if the default was "none"
function default-bump {
  if [ "$default_semvar_bump" == "none" ]; then
    echo "Default bump was set to none. Skipping..."
    exit 0
  else
    bump "${default_semvar_bump}" $tag
  fi
}

# get commit logs and determine home to bump the version
# supports #major, #minor, #patch (anything else will be 'minor')
case "$log" in
    *#major* ) new=$(bump major $tag); part="major";;
    *#minor* ) new=$(bump minor $tag); part="minor";;
    * ) new=$(default-bump); part=$default_semvar_bump;;
esac

echo $part

# did we get a new tag?
if [ ! -z "$new" ]; then
    # prefix with 'v'
    if $with_v; then
        new="v$new"
    fi

    if $pre_release; then
        new="$new-${commit:0:7}"
    fi
fi

if [ ! -z $custom_tag ]; then
    new="$custom_tag"
fi

echo $new

# set outputs
echo "new_tag=$new" >> $GITHUB_OUTPUT
echo "part=$part" >> $GITHUB_OUTPUT

# use dry run to determine the next tag
if $dryrun; then
    echo "tag=$tag" >> $GITHUB_OUTPUT
    exit 0
fi 

echo "tag=$new" >> $GITHUB_OUTPUT

if $pre_release; then
    echo "This branch is not a release branch. Skipping the tag creation."
    exit 0
fi

# push new tag ref to github
dt=$(date '+%Y-%m-%dT%H:%M:%SZ')
full_name=$GITHUB_REPOSITORY
git_refs_url=$(jq .repository.git_refs_url $GITHUB_EVENT_PATH | tr -d '"' | sed 's/{\/sha}//g')

echo "$dt: **pushing tag $new to repo $full_name"

curl -s -X POST $git_refs_url \
-H "Authorization: token $GITHUB_TOKEN" \
-d @- << EOF
{
  "ref": "refs/tags/$new",
  "sha": "$commit"
}
EOF

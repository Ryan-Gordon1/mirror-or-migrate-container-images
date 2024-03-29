#!/bin/bash

# Title:         mirror-images.sh
# Author:        ryan.gordon1@ibm.com
# Description:   Facilitates the transfer of a number of named images from a source registry to a destination one
# License:       MIT

# Version:       1.0.0
set -x

# v1: At a high level; with this script we want to:
# 0. Determine whether to use docker or podman
# 1. Query the QUAY REST API to gather all repos for the given namespace
# 2. For each repo:
# 2.1 Query each repo for tags and for each tag
# 2.1 Pull the tagged image from the source registry
# 2.2 Tag the image with its new destination tag before push
# 2.3 Push the image with its new tag to the destination registry
# 2.4 Delete both the local image we pushed aswell as the destination retagged image(Local step)

## Functions
# Function used to check the existance of a command
function cmd_exists() {
  command -v $1 > /dev/null 2>&1
}
## Variables
readonly IMAGE_REGISTRY="${SOURCE_REGISTRY_DOMAIN:-quay.io}"
readonly REGISTRY_ORG="${SOURCE_REGISTRY_ORG:-ibmresilient}"
# The registry we will pull images from 
readonly SOURCE_REGISTRY="$IMAGE_REGISTRY/$REGISTRY_ORG"
# This is an exposed cred; the cred has only the repo:read permission and is used to get a list of all images and tags from the REST API
readonly AUTH_TOKEN="j0ZG8Jm3hD3HRmXOaDMFsL0zWrRKjqsFJeswCHDF"

# In order to determine what images are available and what tags are available for those images, we need to make api calls. 
# These are the URLS for quay and may differ for you. 
readonly REPO_API_ENDPOINT='https://quay.io/api/v1/repository'

# The registry we will push images too
destination_registry=""

# ========================================
#
# Checks for arguments and the needed unix commands
#
# ========================================

# Check if string is empty using -z. For more 'help test'    
if [[ -z "$1" ]]; then
   printf '%s\n' "No destination registry provided. Registry must be provided in the form: fqdn.registry.io/ exiting"
   exit 1
fi
destination_registry=$1

cmd_exists jq || { echo >&2 "Jq is required for parsing the API call responses from Quay and was not found in the envionment."; exit 1; }

# Before trying to pull or push anything, check for the existance of either docker or podman
container_engine=""
# Users may provide a preferred container engine using arg 2, otherwise the script checks whether it can use docker or podman.    
if [[ ! -z "$2" ]]; then
    # Ensure the user provided command is available to use 
    if cmd_exists "${2}"; then
        container_engine=$2
    else # the user provided container engine command does not exist, exit with a message.
        echo >&2 "Script was provided with ${2} command to be used, but this command was not found."; exit 1;
    fi
elif cmd_exists podman; then
    # If podman exists, use that as our container engine
    container_engine=podman

elif cmd_exists docker; then
    # Or if docker is there and docker isin't use that
    container_engine=docker
else # neither of the engines were found, exit with a message
    echo >&2 "Image mirroring requires either Docker or Podman but neither were found. Aborting."; exit 1;
fi

# # ========================================
# #
# # Operational Logic to get images tags and transfer them
# #
# # ========================================

# First get a handle on all the repositories; use jq to parse the json and return only the names
repos=`curl -s "${REPO_API_ENDPOINT}?namespace=${REGISTRY_ORG}" -H "authorization: Bearer ${AUTH_TOKEN}" | jq ".repositories[$count].name" | tr -d '"'`

while IFS= read -r repo;
do 
    echo "Starting to process all tags for repository: ${repo}"
    # Get all tags for the repo 
    tags=`curl -s "${REPO_API_ENDPOINT}/${REGISTRY_ORG}/${repo}/tag/" -H "authorization: Bearer ${AUTH_TOKEN}" | jq ".tags[$count].name" | tr -d '"'`
    echo "Made an API Call to Registry for repository $repo; Found these tags ${tags[@]}"
    while IFS= read -r tag;
    do
        # Pull the given image from the SOURCE_REGISTRY
        $container_engine pull "$SOURCE_REGISTRY/$repo:$tag"

        echo "Image pulled; Retagging image before pushing"

        # Tag the image with our destination registry
        $container_engine tag "$SOURCE_REGISTRY/$repo:$tag" "$destination_registry/$repo:$tag"

        # Uncomment this if you are on AWS and want to have repositories created for your newly tagged images
        # aws ecr describe-repositories  --region us-east-2 --repository-names $image 2>&1 > /dev/null
        # status=$?
        # if [[ ! "${status}" -eq 0 ]]; then
        #     aws ecr create-repository --repository-name $image --region us-east-2
        # fi

        echo "Image tagged; Pushing now to destination registry: $destination_registry"

        # Push our newly tagged image to the destination
        $container_engine push "$destination_registry/$repo:$tag"

        echo "Transfer completed for image $image. Now cleaning up and removing these local images: $destination_registry/$repo:$tag, $SOURCE_REGISTRY/$repo:$tag"
    
        # Delete the images locally to avoid using up all storage during transfer
        $container_engine rmi -f "$destination_registry/$repo:$tag"
        
        $container_engine rmi -f "$SOURCE_REGISTRY/$repo:$tag"

    echo "Finished processing all tags for repository: ${repo}"
    # Finish processing the tags for a repository
    done <<< "$tags"
# Finish processing a repository
done <<< "$repos"


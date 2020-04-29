# mirror-or-migrate-container-images
Looking for contributors! 

A repo used to take a given list of image names from a source registry and then pulls, retags and pushes them to some other registry.



## General Instructions
For the most part, pushing images to different container registries will be similar to each other in that they follow these high level steps :

1. Login to the destination registry using the platform specific method or `docker login`
2. Build and tag the image with the destination registry; `ryanibm/ubuntu` becomes `quay.io/ryanibm/ubuntu` for example
3. Push the appropriately tagged image to the registry. 

The steps of building and tagging the images is handled for you in the script using the first arg passed to the script as the destination registry.

Example :
This example will mirror images from the source registry to a registry called `mycoolazurecr.azurecr.io` using the docker engine.
```bash
sh mirror-images.sh mycoolazurecr.azurecr.io docker
```

## Platform Specific Instructions
This script has been tested with the following registries; AWS ECR, Azure CR, Gitlab CR, Dockerhub, JFrog CR and Quay
Depending on the platform there are certain differences in how things are done or what you must do before hand.

In all cases, docker login is handled outside of the script. The script assumes you have logged into the registry which is passed as the first arg to the script 

Example: 
```
sh mirror-images.sh myazurecr.azurecr.io docker
```
assumes you have already logged into this registry `myazurecr.azurecr.io` and have push access. 
In most cases logins are handled through 

### Azure Login :
Login for an acr instance can be handled through the Azure CLI. For information on installing head [here](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest)

With the cli installed a command can be run to manage to docker login through an Azure account. This will authenticate you into Azure and then Azure Container Registry: 

`az acr login -—name <your_registry_name> `

Alternatively you can login with `docker login` however this involves provisioning a service account or IAM user to use the service. 

Pushing to a registry in the Azure Container Registry involves retagging an image as needed and pushing using `docker` or another container tool such as `podman`.
Images which come from other registries should be tagged to match their new destination registry


If you are using just Dockerfiles and want to build and push the resultant image; the azure command line can handle the operation with azure container registries build command :

```bash
az acr build --image sample/hello-world:v1 \
  --registry myContainerRegistry008 \
  --file Dockerfile .
```
[Source](https://docs.microsoft.com/en-us/azure/container-registry/container-registry-quickstart-task-cli)

### AWS ECR Login:
Setting up a container registry on Amazon involves setting up the Elastic Container Registry service with an IAM user. 

Login for an ecr instance can be handled through the AWS CLI. For information on installing head [here](<https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html>)

With the cli installed you can run a command to get your login password and then pipe this to the docker login command. 

`aws ecr get-login-password —region \<your\_region\> | docker login --username AWS --password-stdin <your_registry> `

> There is a caveat with pushing images to ECR in that the repository where you are pushing must exist. In most cases if the repository does not exist when an image is being pushed it is created. Ex: docker push ryanibm/mynewrepo will create `mynewrepo` in the `ryanibm` namespace. ECR however does not so an additional check must be performed the determine if the repository needs to be created. 

The above describes the largest difference between ECR and other registries, in the scripts there is a commented out section which will specifically handle the checking and creation of the repository before push. If you are using ECR as a destination ensure to uncomment this block in the scripts: 
```bash
# Uncomment this if you are on AWS and want to have repositories created for your newly tagged images
# aws ecr describe-repositories  --region us-east-2 --repository-names $image 2>&1 > /dev/null
# status=$?
# if [[ ! "${status}" -eq 0 ]]; then
#     aws ecr create-repository --repository-name $image --region us-east-2
# fi
```

Provided a repository exists in ECR that matches the name of your image the pushing of the image remains similar to pushing to Dockerhub or another registry.
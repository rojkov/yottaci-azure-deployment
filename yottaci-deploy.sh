#!/bin/sh -e

subscription_id=$1
resource_group_name=$2
resource_group_location="northeurope"

if [ -z "${subscription_id}" ]; then
    echo "No subscription provided"
    exit 1
fi

if [ -z "${resource_group_name}" ]; then
    echo "No resource group provided"
    exit 1
fi

CWD=`dirname $0`

set +e

az account show

if [ $? != 0 ]; then
    echo "Log in..."
    az login
fi

set -e
az account set --subscription $subscription_id

set +e

#Check for existing RG
az group list -o table | grep -q "$resource_group_name"
if [ $? != 0 ]; then
    echo "Resource group with name" $resource_group_name "could not be found. Creating new resource group.."
    set -e
    (
	set -x
	az group create --name $resource_group_name --location $resource_group_location
    )
else
    echo "Using existing resource group..."
fi

set -ex

NS=$resource_group_name

echo "Start deployment"
az group deployment create \
   --resource-group $resource_group_name \
   --template-file "$CWD/yottaci-template.json" \
   --parameters "$CWD/yottaci-parameters.json" \
   --verbose

PRODUCTION_QUEUE_CS=`az storage account show-connection-string --name "${NS}production" --resource-group ${resource_group_name} -o tsv`
STAGING_QUEUE_CS=`az storage account show-connection-string --name "${NS}staging" --resource-group ${resource_group_name} -o tsv`
#FUNCTIONS_CS=`az storage account show-connection-string --name "${NS}functions" --resource-group ${resource_group_name} -o tsv`

for CS in "${PRODUCTION_QUEUE_CS}" "${STAGING_QUEUE_CS}"
do
    az storage queue create --name "gitupdates" --connection-string "${CS}"
    az storage queue create --name "buildresults" --connection-string "${CS}"
    az storage queue create --name "installationevents" --connection-string "${CS}"
done

az functionapp deployment source config-local-git \
   --resource-group $resource_group_name \
   --name "${NS}webhooks"

az functionapp deployment source config-local-git \
   --resource-group $resource_group_name \
   --name "${NS}webhooksstaging"

az webapp deployment source config-local-git \
   --slot staging \
   --name "${NS}backend" \
   --resource-group $resource_group_name

echo "Success"

#!/usr/bin/env bash
set -euo pipefail

# Trace.Pay Azure foundation bootstrap.
# This creates the core resources; it does not guess your subscription, region, domain, or secrets.

: "${AZ_SUBSCRIPTION_ID:?Set AZ_SUBSCRIPTION_ID}"
: "${AZ_LOCATION:?Set AZ_LOCATION, e.g. centralindia}"
: "${AZ_RESOURCE_GROUP:?Set AZ_RESOURCE_GROUP}"
: "${ACR_NAME:?Set globally-unique lowercase ACR name}"
: "${PG_NAME:?Set globally-unique PostgreSQL server name}"
: "${REDIS_NAME:?Set Azure Managed Redis name}"
: "${KEYVAULT_NAME:?Set globally-unique Key Vault name}"
: "${EVENTHUB_NAMESPACE:?Set globally-unique Event Hubs namespace name}"
: "${EVENTHUB_NAME:?Set Event Hub name}"
: "${STORAGE_NAME:?Set globally-unique lowercase storage account name}"

az account set --subscription "$AZ_SUBSCRIPTION_ID"
az provider register --namespace Microsoft.App >/dev/null
az provider register --namespace Microsoft.OperationalInsights >/dev/null
az provider register --namespace Microsoft.ContainerRegistry >/dev/null
az provider register --namespace Microsoft.DBforPostgreSQL >/dev/null
az provider register --namespace Microsoft.EventHub >/dev/null
az provider register --namespace Microsoft.KeyVault >/dev/null
az provider register --namespace Microsoft.Storage >/dev/null
az group create -n "$AZ_RESOURCE_GROUP" -l "$AZ_LOCATION" >/dev/null

az acr create -g "$AZ_RESOURCE_GROUP" -n "$ACR_NAME" --sku Basic >/dev/null
az postgres flexible-server create \
  -g "$AZ_RESOURCE_GROUP" -n "$PG_NAME" -l "$AZ_LOCATION" \
  --admin-user tracepayadmin --admin-password "$PG_ADMIN_PASSWORD" \
  --sku-name Standard_B1ms --tier Burstable --version 16 --storage-size 32 \
  --public-access 0.0.0.0 >/dev/null
az postgres flexible-server db create -g "$AZ_RESOURCE_GROUP" -s "$PG_NAME" -d tracepay >/dev/null

az redisenterprise create -g "$AZ_RESOURCE_GROUP" -n "$REDIS_NAME" -l "$AZ_LOCATION" --sku Balanced_B0 >/dev/null

az keyvault create -g "$AZ_RESOURCE_GROUP" -n "$KEYVAULT_NAME" -l "$AZ_LOCATION" --enable-rbac-authorization true >/dev/null

az storage account create -g "$AZ_RESOURCE_GROUP" -n "$STORAGE_NAME" -l "$AZ_LOCATION" --sku Standard_LRS --kind StorageV2 >/dev/null
az storage container create --account-name "$STORAGE_NAME" --name tracepay-ingestion --auth-mode login >/dev/null
az storage container create --account-name "$STORAGE_NAME" --name tracepay-private --auth-mode login >/dev/null

az eventhubs namespace create -g "$AZ_RESOURCE_GROUP" -n "$EVENTHUB_NAMESPACE" -l "$AZ_LOCATION" --sku Standard >/dev/null
az eventhubs eventhub create -g "$AZ_RESOURCE_GROUP" --namespace-name "$EVENTHUB_NAMESPACE" -n "$EVENTHUB_NAME" --partition-count 4 --retention-time 24 >/dev/null
az eventhubs eventhub consumer-group create -g "$AZ_RESOURCE_GROUP" --namespace-name "$EVENTHUB_NAMESPACE" --eventhub-name "$EVENTHUB_NAME" -n tracepay-worker >/dev/null

az containerapp env create -g "$AZ_RESOURCE_GROUP" -n tracepay-env -l "$AZ_LOCATION" >/dev/null

echo "Foundation created. Next: store secrets in Key Vault, build ACR images, then create API/worker/web Container Apps."

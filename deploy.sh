#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-localhost}"      # localhost | preprod | prod
FUNCTION_NAME="${FUNCTION_NAME:?FUNCTION_NAME not set}"
REGION="${REGION:-eu-west-1}"

echo "==> Deploying to ENV=$ENVIRONMENT for function=$FUNCTION_NAME in $REGION"

# 1) Met à jour la config pour fixer ENVIRONMENT dans la révision en cours ($LATEST)
echo "Updating environment variables on \$LATEST..."
EXISTING_ENV=$(aws lambda get-function-configuration \
  --function-name $FUNCTION_NAME \
  --region $REGION \
  --query 'Environment.Variables' \
  --output json)

if [[ "$ENVIRONMENT" == "localhost" ]]; then
  echo "Updating \$LATEST to ENVIRONMENT=localhost only..."
  UPDATED_ENV_LOCAL=$(echo "$EXISTING_ENV" | jq --arg env "localhost" '. + {ENVIRONMENT: $env}' | jq -c '.')
  aws lambda update-function-configuration \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION" \
    --environment "{\"Variables\":$UPDATED_ENV_LOCAL}"
  echo "Done: \$LATEST has ENVIRONMENT=localhost."
  exit 0
fi

UPDATED_ENV=$(echo "$EXISTING_ENV" | jq --arg env "$ENVIRONMENT" '. + {ENVIRONMENT: $env}')

# ----- ICI: preprod / prod -----
# 1) Met temporairement ENVIRONMENT à la cible pour figer la version
UPDATED_ENV_TARGET=$(echo "$EXISTING_ENV" | jq --arg env "$ENVIRONMENT" '. + {ENVIRONMENT: $env}' | jq -c '.')
echo "Temporarily setting ENVIRONMENT=$ENVIRONMENT on \$LATEST to publish a version..."
aws lambda update-function-configuration \
  --function-name "$FUNCTION_NAME" \
  --region "$REGION" \
  --environment "{\"Variables\":$UPDATED_ENV_TARGET}"

# Attendre la fin de la mise à jour avant de publier une version
echo "Waiting for Lambda update to complete..."
aws lambda wait function-updated --function-name $FUNCTION_NAME --region $REGION

# 2) Publie la version (les env vars sont figées maintenant)
DESC="Release $(date +%Y-%m-%dT%H:%M:%S) ENV=$ENVIRONMENT"
echo "Publishing version with ENVIRONMENT=$ENVIRONMENT..."
PV_OUT=$(aws lambda publish-version \
  --region "$REGION" \
  --function-name "$FUNCTION_NAME" \
  --description "$DESC")

NEW_VERSION=$(echo "$PV_OUT" | python -c 'import sys,json;print(json.load(sys.stdin)["Version"])')
echo "Published version: $NEW_VERSION"

# 3) Mettre à jour l’alias correspondant (preprod ou prod)
ALIAS_NAME="$ENVIRONMENT"   # alias 'preprod' ou 'prod'
echo "Pointing alias '$ALIAS_NAME' to version $NEW_VERSION..."
# Temporarily disable -e to capture non-zero exit from update-alias without exiting
set +e
ALIAS_UPDATE_OUTPUT=$(aws lambda update-alias \
  --region "$REGION" \
  --function-name "$FUNCTION_NAME" \
  --name "$ALIAS_NAME" \
  --function-version "$NEW_VERSION" 2>&1)
UPDATE_RC=$?
set -e

if [ $UPDATE_RC -eq 0 ]; then
  echo "Alias '$ALIAS_NAME' updated to version $NEW_VERSION."
else
  if echo "$ALIAS_UPDATE_OUTPUT" | grep -q "ResourceNotFoundException"; then
    echo "Alias '$ALIAS_NAME' not found. Creating it..."
    aws lambda create-alias \
      --region "$REGION" \
      --function-name "$FUNCTION_NAME" \
      --name "$ALIAS_NAME" \
      --function-version "$NEW_VERSION" \
      >/dev/null
    echo "Alias '$ALIAS_NAME' created at version $NEW_VERSION."
  else
    echo "Failed to update alias '$ALIAS_NAME' (rc=$UPDATE_RC):"
    echo "$ALIAS_UPDATE_OUTPUT"
    exit $UPDATE_RC
  fi
fi

# 4) **RESTAURe $LATEST à localhost**
echo "Restoring \$LATEST back to ENVIRONMENT=localhost..."
# Reprend les variables existantes (celles visibles sur $LATEST après l'étape cible)
EXISTING_AFTER=$(aws lambda get-function-configuration \
  --function-name "$FUNCTION_NAME" \
  --region "$REGION" \
  --query 'Environment.Variables' \
  --output json)

UPDATED_ENV_LOCAL=$(printf '%s' "${EXISTING_AFTER:-null}" | jq -c --arg env "localhost" '(. // {}) + {ENVIRONMENT: $env}')
aws lambda update-function-configuration \
  --function-name "$FUNCTION_NAME" \
  --region "$REGION" \
  --environment "{\"Variables\":$UPDATED_ENV_LOCAL}"

echo "Done: alias '$ALIAS_NAME' -> version $NEW_VERSION (ENVIRONMENT=$ENVIRONMENT) and \$LATEST restored to ENVIRONMENT=localhost."
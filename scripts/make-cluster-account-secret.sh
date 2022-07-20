#!/usr/bin/env bash

print_usage() {
  echo "Makes a kubernetes secret containing keys for a dscp account. The final line of this script will output a JSON object containing the new account's accountId."
  echo ""
  echo "Usage:"
  echo "  ./scripts/make-cluster-account-secret.sh [ -h ] [ -f ] [ -n <namespace> ] [ -c <container> ] <cluster_name> <account_name>"
  echo ""
  echo "Example Usage:"
  echo "  ./scripts/make-cluster-account-secret.sh inteli-stage api"
  echo ""
  echo "Flags: "
  echo "  -h              Print this message"
  echo "  -f              Force re-creation of new secret for an existing account. Note this is destructive"
  echo "  -c <container>  Container image to use for key generation"
  echo "  -n <namespace>  Namespace in which to create the secret. Defaults to dscp"
}

FORCE_RECREATE=
NAMESPACE="dscp"
CONTAINER="digicatapult/dscp-node:latest"
while getopts ":n:c:fh" opt; do
  case ${opt} in
    h )
      print_usage
      exit 0
      ;;
    f )
      FORCE_RECREATE="yes"
      ;;
    n )
      NAMESPACE=${OPTARG}
      ;;
    c )
      CONTAINER=${OPTARG}
      ;;
    : )
      echo "Error: -${OPTARG} requires an argument." >&2
      exit 1
      ;;
   \? )
     echo "Invalid Option: -$OPTARG" 1>&2
     echo "\n"
     print_usage
     exit 1
     ;;
  esac
done
shift $((OPTIND -1))
CLUSTER=$1
ACCOUNT_NAME=$2

assert_cluster() {
  local cluster=$1

  printf "Checking cluster $cluster is configured correctly..." >&2
  if [ ! -d "./clusters/$cluster/secrets" ]; then
    echo -e "Cannot add secrets for cluster $cluster which does not exist" >&2
    exit 1
  fi
  printf "OK\n" >&2
}

assert_not_account() {
  local cluster=$1
  local namespace=$2
  local account_name=$3

  printf "Checking account $account_name:$namespace does not already exist in cluster $cluster..." >&2
  if [ ! -z "$FORCE_RECREATE" ]; then
    printf "SKIP\n" >&2
  else
    if [ -f "./clusters/$cluster/secrets/${account_name}_${namespace}_account-keys.yaml" ] ||
       [ -f "./clusters/$cluster/secrets/${account_name}_${namespace}_account-keys.unc.yaml" ]; then
      echo -e "Account $account_name:${namespace} already exists in cluster $cluster. Use -f to overrite anyway." >&2
      exit 1
    fi
    printf "OK\n" >&2
  fi
}

assert_namespace() {
  local namespace=$1

  printf "Checking that namespace $namespace is valid..." >&2
  if [[ ! $namespace =~ ^[a-z0-9][-a-z0-9]{0,61}[a-z0-9]$ ]]; then
    echo -e "$namespace is not a valid Kubernetes namespace" >&2
    exit 1
  fi
  printf "OK'\n" >&2
}

assert_command() {
  local command=$1

  printf "Checking for presense of $command..." >&2
  local path_to_executable=$(command -v ${command})

  if [ -z "$path_to_executable" ] ; then
    echo -e "Cannot find ${command} executable. Is it on your \$PATH?" >&2
    exit 1
  fi
  printf "OK\n" >&2
}

pull_container() {
  local container=$1

  printf "Pulling container $container..." >&2
  docker pull $container > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    printf "OK\n" >&2
  else
    printf "FAIL\n" >&2
    exit 1
  fi
}

ACCOUNT_SEED=
ACCOUNT_ADDR=
generate_account_key() {
  local container=$1

  printf "Generating account-key..." >&2
  if output=$(docker run --rm -t $container key generate --scheme Sr25519 --output-type Json 2>&1); then
    printf "OK\n" >&2
    ACCOUNT_SEED=$(echo $output | jq -r .secretPhrase)
    ACCOUNT_ADDR=$(echo $output | jq -r .ss58Address)
  else
    printf "FAIL\n" >&2
    echo "$output" >&2
    exit 1
  fi
}

create_k8s_secret() {
  local cluster=$1
  local namespace=$2
  local account_name=$3
  local account_seed=$4

  printf "Generating k8s secret for $account_name..." >&2
  kubectl create secret generic ${account_name}-keys \
    --type=Opaque \
    --namespace=$namespace \
    --from-literal=account_seed="$account_seed" \
    --dry-run=client \
    --output=yaml > ./clusters/${cluster}/secrets/${account_name}_${namespace}_account-keys.unc.yaml

  if [ "$?" -ne "0" ]; then
    printf "FAIL\n" >&2
    exit 1
  fi
  printf "OK\n" >&2
}

# first check the encironment and args are sane
assert_command kubectl
assert_command docker
assert_command jq
assert_cluster $CLUSTER
assert_namespace $NAMESPACE
assert_not_account $CLUSTER $NAMESPACE $ACCOUNT_NAME
# make sure we can pull the container
pull_container $CONTAINER

# Generate keys
generate_account_key $CONTAINER

# generate kubernetes secret
create_k8s_secret "$CLUSTER" "$NAMESPACE" "$ACCOUNT_NAME" "$ACCOUNT_SEED"

# Generate output as JSON
echo $(jq --null-input --arg account_addr $ACCOUNT_ADDR '{ "accountId": $account_addr }')

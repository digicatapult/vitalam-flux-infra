#!/usr/bin/env bash

print_usage() {
  echo "Makes a kubernetes secret containing keys for a sqnc-node. The final line of this script will output a JSON object containing the new node's PeerId, BabeId and GrandpaId."
  echo ""
  echo "Usage:"
  echo "  ./scripts/make-cluster-node-secret.sh [ -h ] [ -f ] [ -n <namespace> ] [ -c <container> ] <cluster_name> <node_name>"
  echo ""
  echo "Example Usage:"
  echo "  ./scripts/make-cluster-node-secret.sh inteli-stage red"
  echo ""
  echo "Flags: "
  echo "  -h              Print this message"
  echo "  -f              Force re-creation of new secret for an existing node. Note this is destructive"
  echo "  -c <container>  Container image to use for key generation"
  echo "  -n <namespace>  Namespace in which to create the secret. Defaults to sqnc"
}

FORCE_RECREATE=
NAMESPACE="sqnc"
CONTAINER="digicatapult/sqnc-node:latest"
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
NODE_NAME=$2

assert_cluster() {
  local cluster=$1

  printf "Checking cluster $cluster is configured correctly..." >&2
  if [ ! -d "./clusters/$cluster/secrets" ]; then
    echo -e "Cannot add secrets for cluster $cluster which does not exist" >&2
    exit 1
  fi
  printf "OK\n" >&2
}

assert_not_node() {
  local cluster=$1
  local namespace=$2
  local node_name=$3

  printf "Checking node $node_name:$namespace does not already exist in cluster $cluster..." >&2
  if [ ! -z "$FORCE_RECREATE" ]; then
    printf "SKIP\n" >&2
  else
    if [ -f "./clusters/$cluster/secrets/${node_name}_${namespace}_node-keys.yaml" ] ||
       [ -f "./clusters/$cluster/secrets/${node_name}_${namespace}_node-keys.unc.yaml" ]; then
      echo -e "Node $node_name:${namespace} already exists in cluster $cluster. Use -f to overrite anyway." >&2
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

NODE_KEY=
NODE_ID=
generate_node_key() {
  local container=$1

  printf "Generating node-key..." >&2
  if output=$(docker run --rm -t $container key generate-node-key 2>&1); then
    printf "OK\n" >&2
    output=(${output[@]})
    NODE_ID=(${output[0]})
    NODE_KEY=(${output[1]})
  else
    printf "FAIL\n" >&2
    echo "$output" >&2
    exit 1
  fi
}

AUTH_KEY=
AUTH_ADDR=
generate_authority_key() {
  local container=$1
  local scheme=$2
  local output=

  printf "Generating authority key with scheme $scheme..." >&2
  if output=$(docker run --rm -t $container key generate --scheme $scheme --output-type Json 2>&1); then
    printf "OK\n" >&2
    AUTH_KEY=$(echo $output | jq -r .secretPhrase)
    AUTH_ADDR=$(echo $output | jq -r .ss58Address)
  else
    printf "FAIL\n" >&2
    echo "$output" >&2
    exit 1
  fi
}

create_k8s_secret() {
  local cluster=$1
  local namespace=$2
  local node_name=$3
  local node_key=$4
  local owner_seed=$5
  local babe_seed=$6
  local grandpa_seed=$7

  printf "Generating k8s secret for $node_name..." >&2
  kubectl create secret generic ${node_name}-keys \
    --type=Opaque \
    --namespace=$namespace \
    --from-literal=node_id=$node_key \
    --from-literal=owner_seed="$owner_seed" \
    --from-literal=babe_seed="$babe_seed" \
    --from-literal=grandpa_seed="$grandpa_seed" \
    --dry-run=client \
    --output=yaml > ./clusters/${cluster}/secrets/${node_name}_${namespace}_node-keys.unc.yaml

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
assert_not_node $CLUSTER $NAMESPACE $NODE_NAME
# make sure we can pull the container
pull_container $CONTAINER

# Generate keys
generate_node_key $CONTAINER
generate_authority_key $CONTAINER Sr25519
OWNER_ADDR=$AUTH_ADDR
OWNER_SEED=$AUTH_KEY
generate_authority_key $CONTAINER Sr25519
BABE_ADDR=$AUTH_ADDR
BABE_SEED=$AUTH_KEY
generate_authority_key $CONTAINER Ed25519
GRANDPA_ADDR=$AUTH_ADDR
GRANDPA_SEED=$AUTH_KEY

# generate kubernetes secret
create_k8s_secret "$CLUSTER" "$NAMESPACE" "$NODE_NAME" "$NODE_KEY" "$OWNER_SEED" "$BABE_SEED" "$GRANDPA_SEED"

# Generate output as JSON
echo $(jq --null-input \
  --arg node_id $NODE_ID \
  --arg owner_id $OWNER_ADDR \
  --arg babe_id $BABE_ADDR \
  --arg grandpa_id $GRANDPA_ADDR \
  '{ "nodeId": $node_id, "ownerId": $owner_id, "babeId": $babe_id, "grandpaId": $grandpa_id }')

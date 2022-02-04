#!/usr/bin/env bash


print_usage() {
  echo "TODO"
  echo ""
  echo "Usage:"
  echo "  ./scripts/make-new-cluster-genesis.sh [ -h ] [ -n <namespace> ] [ -b <base_chain> ] [ -c <container> ] [ -v <validator_node_name> ] [ -a <additional_node_name> ] <cluster_name>"
  echo ""
  echo "Example Usage:"
  echo "  # Create keys and a genesis for cluster inteli-stage with three validator nodes (red, green, blue) and two additional nodes (bootnode, api-light)"
  echo "  ./scripts/make-new-cluster-genesis.sh -v red -v green -v blue -a bootnode -a api-light inteli-stage"
  echo ""
  echo "Flags: "
  echo "  -h                         Print this message"
  echo "  -n <namespace>             Namespace in which to create the secret. Defaults to `dscp`"
  echo "  -b <base_chain>            Base chain-spec to generate spec from. Defaults to `local`."
  echo "  -c <container>             Container image to use for key generation"
  echo "  -v <validator_node_name>   Adds a validator node with name <validator_node_name>. To add multiple validators add multiple -v flags"
  echo "  -a <additional_node_name>  Adds an additional (non-validator) node with name <additional_node_name>. To add multiple additional nodes add multiple -a flags"
}

NAMESPACE="dscp"
BASE_CHAIN="local"
CONTAINER="ghcr.io/digicatapult/vitalam-node:latest"
VALIDATOR_NAMES=()
ADDITIONAL_NAMES=()
GENESIS=
while getopts ":n:b:c:v:a:h" opt; do
  case ${opt} in
    h )
      print_usage
      exit 0
      ;;
    n )
      NAMESPACE=${OPTARG}
      ;;
    b )
      BASE_CHAIN=${OPTARG}
      ;;
    c )
      CONTAINER=${OPTARG}
      ;;
    v )
      VALIDATOR_NAMES+=("${OPTARG}")
      ;;
    a )
      ADDITIONAL_NAMES+=("${OPTARG}")
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

# echo $CLUSTER
# echo "$NAMESPACE"
# echo "$CONTAINER"
# for value in "${VALIDATOR_NAMES[@]}"
# do
#   echo "VALIDATOR: $value"
# done
# for value in "${ADDITIONAL_NAMES[@]}"
# do
#   echo "ADDITIONAL $value"
# done

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
  local node_name=$2

  printf "Checking node $node_name does not already exist in cluster $cluster..." >&2
  if [ ! -z "$FORCE_RECREATE" ]; then
    printf "SKIP\n" >&2
  else
    if [ -f "./clusters/$cluster/secrets/${node_name}_keys.yaml" ] ||
       [ -f "./clusters/$cluster/secrets/${node_name}_keys.unc.yaml" ]; then
      echo -e "Node $node_name already exists in cluster $cluster. Use -f to overrite anyway." >&2
      exit 1
    fi
    printf "OK\n" >&2
  fi
}

assert_label() {
  local type=$1
  local name=$2

  printf "Checking that $type $name is valid..." >&2
  if [[ ! $name =~ ^[a-z0-9][-a-z0-9]{0,61}[a-z0-9]$ ]]; then
    echo -e "$name is not a valid Kubernetes name" >&2
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

create_node_identity() {
  local node_type=$1
  local cluster=$2
  local namespace=$3
  local container=$4
  local node_name=$5

  local output=

  output=$(./scripts/make-cluster-node-secret \
    -n "$namespace" \
    -c "$container" \
    "$cluster" "$node_name" | \
    tail -n 1)
}

SUDO_SEED=
SUDO_ADDR=
generate_sudo() {
  local container=$1
  local output=

  printf "Generating sudo key with scheme Sr25519..." >&2
  if output=$(docker run -t $container key generate --scheme Sr25519 --output-type Json 2>&1); then
    printf "OK\n" >&2
    SUDO_SEED=$(echo $output | jq -r .secretPhrase)
    SUDO_ADDR=$(echo $output | jq -r .ss58Address)
    GENESIS=$(echo $GENESIS | jq --arg sudo $SUDO_ADDR '.genesis.runtime.palletSudo.key |= $sudo')
  else
    printf "FAIL\n" >&2
    echo "$output" >&2
    exit 1
  fi
}

generate_validator() {
  local cluster=$1
  local namespace=$2
  local container=$3
  local node_name=$4
  local output=
  local node_id=
  local aura_id=
  local grandpa_id=

  printf "Generating keys for validator $node_name..." >&2
  if output=$(./scripts/make-cluster-node-secret.sh -n $namespace -c $container $cluster $node_name 2>/dev/null); then
    printf "OK\n" >&2
    # extract ids
    node_id=$(echo $output | jq -r '.nodeId')
    aura_id=$(echo $output | jq -r '.auraId')
    grandpa_id=$(echo $output | jq -r '.grandpaId')
    # update genesis
    GENESIS=$(echo $GENESIS | jq --arg aura_id $aura_id '.genesis.runtime.palletAura.authorities += [$aura_id]')
    GENESIS=$(echo $GENESIS | jq --arg grandpa_id $grandpa_id '.genesis.runtime.palletGrandpa.authorities += [[$grandpa_id, 1]]')
    # convert node_id to hex
    node_id=$(docker run -a stdout python:alpine /bin/sh -c "\
      pip install base58 1>/dev/null; \
      printf \"$node_id\" | base58 -d | xxd -p | tr -d '[:space:]'")
    node_id=($(echo $node_id | fold -w2))

    GENESIS=$(echo $GENESIS | jq --arg sudo_id $SUDO_ADDR '.genesis.runtime.palletNodeAuthorization.nodes += [[[], $sudo_id]]')
    for byte in "${node_id[@]}"
    do
      GENESIS=$(echo $GENESIS | jq --arg sudo_id $SUDO_ADDR --arg byte 0x$byte '.genesis.runtime.palletNodeAuthorization.nodes[-1][0] += [$byte]')
    done
  else
    printf "FAIL\n" >&2
    echo "$output" >&2
    exit 1
  fi
}

assert_command kubectl
assert_command docker
assert_command jq
assert_cluster $CLUSTER
assert_label "namespace" $NAMESPACE

for validator_name in "${VALIDATOR_NAMES[@]}"
do
  assert_label "name" "$validator_name"
  assert_not_node "$CLUSTER" "$validator_name"
done

for additional_name in "${ADDITIONAL_NAMES[@]}"
do
  assert_label "name" "$additional_name"
  assert_not_node "$CLUSTER" "$additional_name"
done

# make sure we can pull the container
pull_container $CONTAINER

# swap out names and set chain type
GENESIS=$(docker run -a stdout $CONTAINER build-spec --disable-default-bootnode --chain $BASE_CHAIN)
GENESIS=$(echo $GENESIS | jq --arg cluster $CLUSTER '.name |= $cluster')
GENESIS=$(echo $GENESIS | jq --arg cluster ${CLUSTER//[-]/_} '.id |= $cluster')
GENESIS=$(echo $GENESIS | jq '.chainType |= "Live"')

# remove all pallet configuration
GENESIS=$(echo $GENESIS | jq '.genesis.runtime.palletAura.authorities |= []')
GENESIS=$(echo $GENESIS | jq '.genesis.runtime.palletGrandpa.authorities |= []')
GENESIS=$(echo $GENESIS | jq '.genesis.runtime.palletBalances.balances |= []')
GENESIS=$(echo $GENESIS | jq '.genesis.runtime.palletNodeAuthorization.nodes |= []')
GENESIS=$(echo $GENESIS | jq '.genesis.runtime.palletMembership.members |= []')

# Generate sudo
generate_sudo $CONTAINER


# loop through validators and add them in
NODE_CREATE_OUTPUT=
for validator_name in "${VALIDATOR_NAMES[@]}"
do
  generate_validator $CLUSTER $NAMESPACE $CONTAINER $validator_name
done

echo $GENESIS

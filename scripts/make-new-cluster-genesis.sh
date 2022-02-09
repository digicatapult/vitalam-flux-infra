#!/usr/bin/env bash

print_usage() {
  echo "TODO"
  echo ""
  echo "Usage:"
  echo "  ./scripts/make-new-cluster-genesis.sh [ -h ] [ -b <base_chain> ] [ -c <container> ] [ -v <validator_node_name> ] [ -a <additional_node_name> ] <cluster_name>"
  echo ""
  echo "Example Usage:"
  echo "  # Create keys and a genesis for cluster inteli-stage with three validator nodes (red, green, blue) and two additional nodes (bootnode, api-light)"
  echo "  ./scripts/make-new-cluster-genesis.sh -v red -v green -v blue -a bootnode -a api-light inteli-stage"
  echo ""
  echo "Flags: "
  echo "  -h                                            Print this message"
  echo "  -n <namespace>                                Namespace in which to create the secret. Defaults to dscp"
  echo "  -b <base_chain>                               Base chain-spec to generate spec from. Defaults to local"
  echo "  -c <container>                                Container image to use for key generation."
  echo "                                                Defaults to ghcr.io/digicatapult/vitalam-node:latest"
  echo "  -o <owner>:<namespace>:<balance>              Adds a node owner account giving the specified balance."
  echo "                                                The secret for the owner will be placed in the Kubernetes <namespace>"
  echo "  -v <validator_node_name>:<namespace>:<owner>  Adds a validator node with name <validator_node_name> which will be owned by <owner>."
  echo "                                                The secrets will be added to the specified Kubernetes <namespace>."
  echo "                                                The <owner> must be in the same namesapce as the node."
  echo "                                                To add multiple validators add multiple -v flags"
  echo "  -a <additional_node_name:<namespace>:<owner>  Adds an additional (non-validator) node with name <additional_node_name>"
  echo "                                                which will be owned by <owner>. The secrets will be added to the specified"
  echo "                                                Kubernetes <namespace>. The <owner> must be in the same namesapce as the node."
  echo "                                                To add multiple additional nodes add multiple -a flags"
}

BASE_CHAIN="local"
CONTAINER="ghcr.io/digicatapult/vitalam-node:latest"
OWNER_NAMES=()
VALIDATOR_NAMES=()
ADDITIONAL_NAMES=()
GENESIS=
while getopts ":b:c:o:v:a:h" opt; do
  case ${opt} in
    h )
      print_usage
      exit 0
      ;;
    b )
      BASE_CHAIN=${OPTARG}
      ;;
    c )
      CONTAINER=${OPTARG}
      ;;
    o )
      OWNER_NAMES+=("${OPTARG}")
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
      echo -e "Node $node_name already exists in cluster $cluster" >&2
      exit 1
    fi
    printf "OK\n" >&2
  fi
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
      echo -e "Account $account_name:$namespace already exists in cluster $cluster" >&2
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
  printf "OK\n" >&2
}

assert_balance() {
  local balance=$1
  printf "Checking that balance $balance is valid..." >&2
  if [[ ! $balance =~ ^[1-9][0-9]*$ ]]; then
    echo -e "$balance is not a valid integer" >&2
    exit 1
  fi
  printf "OK\n" >&2
}

assert_node_valid() {
  local node_input=$1
  local node=$(echo $node_input | cut -f1 -d:)
  local namespace=$(echo $node_input | cut -f2 -d:)
  local node_owner=$(echo $node_input | cut -f3 -d:)
  local owner_name=
  local owner_namespace=

  assert_label "namespace" $namespace
  assert_label "name" $node
  assert_not_node "$CLUSTER" "$namespace" "$node"

  assert_label "owner" $node_owner
  printf "Checking that owner for node $node:$namespace is valid..." >&2
  for owner in "${OWNER_NAMES[@]}"
  do
    owner_name=$(echo $owner | cut -f1 -d:)
    owner_namespace=$(echo $owner | cut -f2 -d:)
    if [[ "$namespace" == "$owner_namespace" ]] && [[ "$node_owner" == "$owner_name" ]]; then
      printf "OK\n" >&2
      return 0
    fi
  done

  printf "Owner is not present in account list\n" >&2
  exit 1
}

assert_owner_valid() {
  local owner_input=$1
  local owner=$(echo $owner_input | cut -f1 -d:)
  local namespace=$(echo $owner_input | cut -f2 -d:)
  local balance=$(echo $owner_input | cut -f3 -d:)

  assert_label "namespace" $namespace
  assert_label "owner" $owner
  assert_balance $balance
  assert_not_account "$CLUSTER" "$namespace" "$owner"
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
  if output=$(docker run --rm -t $container key generate --scheme Sr25519 --output-type Json 2>&1); then
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

OWNER_ACCOUNTS=()
generate_owner() {
  local cluster=$1
  local container=$2
  local owner_name_namespace_balance=$3

  local owner_name=$(echo "$owner_name_namespace_balance" | cut -f1 -d:)
  local owner_namespace=$(echo "$owner_name_namespace_balance" | cut -f2 -d:)
  local owner_balance=$(echo "$owner_name_namespace_balance" | cut -f3 -d:)

  printf "Generating owner account ${owner_name}:${owner_namespace}..." >&2
  if output=$(./scripts/make-cluster-account-secret.sh -n $owner_namespace -c $container $cluster $owner_name 2>/dev/null); then
    printf "OK\n" >&2
    account_id=$(echo $output | jq -r '.accountId')
    OWNER_ACCOUNTS+=("${owner_name}:${owner_namespace}:${account_id}")
    GENESIS=$(echo $GENESIS | jq --arg account_id $account_id --arg balance $owner_balance '.genesis.runtime.palletBalances.balances += [[$account_id, ($balance | tonumber)]]')
    GENESIS=$(echo $GENESIS | jq --arg account_id $account_id '.genesis.runtime.palletMembership.members += [$account_id]')
  else
    printf "FAIL\n" >&2
    echo "$output" >&2
    exit 1
  fi
}

generate_node() {
  local type=$1
  local cluster=$2
  local container=$3
  local node_name_namespace_owner=$4

  local node_name=$(echo "$node_name_namespace_owner" | cut -f1 -d:)
  local namespace=$(echo "$node_name_namespace_owner" | cut -f2 -d:)
  local node_owner=$(echo "$node_name_namespace_owner" | cut -f3 -d:)
  local node_owner_account=

  local output=
  local node_id=
  local aura_id=
  local grandpa_id=
  local owner_name=
  local owner_namespace=
  local owner_account=

  for owner in "${OWNER_ACCOUNTS[@]}"
  do
    owner_name=$(echo $owner | cut -f1 -d:)
    owner_namespace=$(echo $owner | cut -f2 -d:)
    owner_account=$(echo $owner | cut -f3 -d:)
    if [[ "$namespace" == "$owner_namespace" ]] && [[ "$node_owner" == "$owner_name" ]]; then
      node_owner_account=$owner_account
    fi
  done

  printf "Generating keys for $type node $node_name..." >&2
  if output=$(./scripts/make-cluster-node-secret.sh -n $namespace -c $container $cluster $node_name 2>/dev/null); then
    printf "OK\n" >&2
    # extract ids
    node_id=$(echo $output | jq -r '.nodeId')
    aura_id=$(echo $output | jq -r '.auraId')
    grandpa_id=$(echo $output | jq -r '.grandpaId')
    # update genesis
    if [ "$type" == "validator" ]; then
      GENESIS=$(echo $GENESIS | jq --arg aura_id $aura_id '.genesis.runtime.palletAura.authorities += [$aura_id]')
      GENESIS=$(echo $GENESIS | jq --arg grandpa_id $grandpa_id '.genesis.runtime.palletGrandpa.authorities += [[$grandpa_id, 1]]')
    fi
    # convert node_id to hex
    node_id=$(docker run --rm -a stdout python:alpine /bin/sh -c "\
      pip install base58 1>/dev/null; \
      printf \"$node_id\" | base58 -d | xxd -p | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]'")
    node_id=($(echo $node_id | fold -w2))

    GENESIS=$(echo $GENESIS | jq --arg owner $node_owner_account '.genesis.runtime.palletNodeAuthorization.nodes += [[[], $owner]]')
    for byte in "${node_id[@]}"
    do
      GENESIS=$(echo $GENESIS | jq --arg byte $(echo "obase=10; ibase=16; $byte" | bc) '.genesis.runtime.palletNodeAuthorization.nodes[-1][0] += [($byte | tonumber)]')
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

for owner in "${OWNER_NAMES[@]}"
do
  assert_owner_valid $owner
done

for validator_name in "${VALIDATOR_NAMES[@]}"
do
  assert_node_valid $validator_name
done

for additional_name in "${ADDITIONAL_NAMES[@]}"
do
  assert_node_valid $additional_name
done

# make sure we can pull the container
pull_container $CONTAINER

# swap out names and set chain type
GENESIS=$(docker run --rm -a stdout $CONTAINER build-spec --disable-default-bootnode --chain $BASE_CHAIN)
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

# loop through nodes and add them in
for owner in "${OWNER_NAMES[@]}"
do
  generate_owner $CLUSTER $CONTAINER $owner
done

# loop through validators and add them in
for validator_name in "${VALIDATOR_NAMES[@]}"
do
  generate_node "validator" $CLUSTER $CONTAINER $validator_name
done

# loop through additional nodes and add them in
for additional_name in "${ADDITIONAL_NAMES[@]}"
do
  generate_node "additional" $CLUSTER $CONTAINER $additional_name
done

GENESIS_DIR=$(mktemp -d -t inteli-genesis.XXXXXX)
echo $GENESIS > $GENESIS_DIR/genesis.json

GENESIS=$(docker run --rm -a stdout --mount type=bind,source="$GENESIS_DIR",target=/config $CONTAINER \
  build-spec --disable-default-bootnode --raw --chain /config/genesis.json)

echo $GENESIS
printf "\n************************ IMPORTANT SUDO SEED ************************\n\n" >&2
echo "$SUDO_SEED" >&2

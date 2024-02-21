#!/usr/bin/env bash

# sanitise environment.
# check for presense of sensible version of kubectl, hydra
# check for valid cluster
# kubectl wait for deployment of postgresql and hydra
# creates hydra client
# creates hydra client token
# outputs hydra client id, secret and token

HYDRA_ADMIN_URL=http://localhost:3080/hydra-admin/
HYDRA_PUBLIC_URL=http://localhost:3080/hydra-public/
CLIENT_NAME=sqnc-client-id
CLIENT_SECRET=sqnc-client-secret
CONTEXT_NAME=kind-sqnc-flux-infra
NAMESPACE=ory
HYDRA_AUDIENCES=offline_access,offline,openid
HYDRA_AUTHENTICATION_HEADER='none: none'

print_usage() {
    echo "Retrieve an OAuth2 token from Ory Hydra"
    echo ""
    echo "Usage:"
    echo "  ./scripts/install-flux.sh [ -h ] [ -a <hydra_admin_url> ] [ -p <hydra_public_url> ] [ -n <namespace> ] [ -c <kind_context_name> ] [ -i <client_id> ] [ -s <client_secret> ]"
    echo ""
    echo "Options:"
    echo "  -a        Specify an alternative hydra admin url to use"
    echo "            (default: http://localhost:3080/hydra-admin/)"
    echo "  -p        Specify an alternative hydra public url to use."
    echo "            (default: http://localhost:3080/hydra-public/)"
    echo "  -n        Specify an alternative namespace that postgres and hydra are located in."
    echo "            (default: ory)"
    echo "  -c        Specify the context name of your cluster"
    echo "            (default: kind-sqnc-flux-infra)"
    echo "  -i        Specify an alternative alternative client-id to use for hydra"
    echo "            (default: sqnc-client-id)"
    echo "  -s        Specify an alternative alternative client-secret to use for hydra"
    echo "            (default: sqnc-client-secret)"
    echo "  -u        A comma seperated list of audiences to set when creating the client"
    echo "            (default: offline_access,offline,openid)"
    echo "  -b        Specify a header to use when authenticating to Hydra, format should be"
    echo "            'Authorization: Bearer <token>'"
    echo "            (default: 'none: none')"
    echo ""
    echo "Flags: "
    echo "  -h        Prints this message"
}

while getopts ":a:p:n:c:i:s:h:u:b:" opt; do
  case ${opt} in
    a )
      HYDRA_ADMIN_URL=${OPTARG}
      ;;
    p )
      HYDRA_PUBLIC_URL=${OPTARG}
      ;;
    n )
      NAMESPACE=${OPTARG}
      ;;
    c )
      CONTEXT_NAME=${OPTARG}
      ;;
    i )
      CLIENT_NAME=${OPTARG}
      ;;
    s )
      CLIENT_SECRET=${OPTARG}
      ;;
    h )
      print_usage
      exit 0
      ;;
    u )
      HYDRA_AUDIENCES=${OPTARG}
      ;;
    b )
      HYDRA_AUTHENTICATION_HEADER=${OPTARG}
      ;;
   \? )
     echo "Invalid Option: $OPTARG" 1>&2
     printf ""
     print_usage
     exit 1
     ;;
  esac
done

assert_env() {
  local context=$1
  local namespace=$2

  # first check that cluster actually exists
    printf "Checking for presense of context $context..."
    kubectl cluster-info --context $context &> /dev/null
    local ret=$?
    if [ "$ret" -ne 0 ]; then
        printf "NOT OK\nError accessing kind cluster $context. Have you created the kind cluster?\n"
        exit 1
    fi
    printf "OK\nCluster $context exists\n"

    printf "Checking if $namespace/postgresql is currently ready..."
    kubectl wait -l statefulset.kubernetes.io/pod-name=pg-hydra-postgresql-0 --for=condition=ready pod -n $namespace  --timeout=300s &> /dev/null
    local ret=$?
    if [ "$ret" -eq 0 ]; then
        printf "OK\n$namespace/postgresql is currently ready\n"
    elif [ "$ret" -ne 0 ]; then
        printf "ERROR\n$namespace/postgresql is not ready, please check the helmrelease\n"
        exit 1
    fi

    printf "Checking if $namespace/hydra is currently ready..."
    kubectl wait deployment/hydra --for=condition=available -n $namespace --timeout=300s &> /dev/null
    local ret=$?
    if [ "$ret" -eq 0 ]; then
        printf "OK\n$namespace/hydra is currently ready\n"
    elif [ "$ret" -ne 0 ]; then
        printf "ERROR\n$namespace/hydra is not ready, please check the helmrelease\n"
        exit 1
    fi
}

assert_command() {
    local command=$1

    printf "Checking for presense of $command..."
    local path_to_executable=$(command -v ${command})

    if [ -z "$path_to_executable" ] ; then
        echo -e "Cannot find ${command} executable. Is it on your \$PATH?"
        exit 1
    fi
    printf "OK\n"
}

create_hydra_client() {
    local hydra_admin_url=$1
    local client_name=$2
    local client_secret=$3
    local hydra_audiences=$4
    local hydra_authentication_header=$5
    printf "Creating a hydra oauth2 client...\n"
    client_id=$(hydra create oauth2-client \
    --endpoint $hydra_admin_url \
    --name "$client_name" \
    --grant-type client_credentials \
    --secret $client_secret \
    --audience $hydra_audiences \
    --http-header "$hydra_authentication_header" \
    --format json| jq -r '.client_id')
    local ret=$?
    if [ "$ret" -eq 0 ]; then
        printf "Ok\nClient $client_name successfully created with id: $client_id\n"
        export client_id
    elif [ "$ret" -ne 0 ]; then
        printf "ERROR\nClient $client_name failed to create, please check manually using \'hydra create oauth2-client\` command\n"
        exit 1
    fi
}

retrieve_hydra_token() {
    local hydra_public_url=$1
    local client_secret=$2
    local hydra_audiences=$3
    printf "Creating a hydra OAuth2 token which will be valid for 7 days...\n"
    hydra perform client-credentials --endpoint $hydra_public_url --client-id $client_id --client-secret $client_secret --audience $hydra_audiences --format json-pretty
    local ret=$?
    if [ "$ret" -eq 0 ]; then
        exit 0
    elif [ "$ret" -ne 0 ]; then
        printf "ERROR\nToken failed to create access token for $client_id failed to create, please see above error\n"
        exit 1
    fi
}

assert_command kubectl
assert_command hydra
assert_command jq
assert_env $CONTEXT_NAME $NAMESPACE
create_hydra_client $HYDRA_ADMIN_URL $CLIENT_NAME $CLIENT_SECRET $HYDRA_AUDIENCES "$HYDRA_AUTHENTICATION_HEADER"
retrieve_hydra_token $HYDRA_PUBLIC_URL $CLIENT_SECRET $HYDRA_AUDIENCES

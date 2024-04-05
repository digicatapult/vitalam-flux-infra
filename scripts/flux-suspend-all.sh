#!/usr/bin/env bash

flux_suspend () {
  case $# in
    3) flux suspend $1 $3 -n $2;;
    4) flux suspend $1 $2 $4 -n $3;;
    *) printf "Expected 3 or 4 parameters, got %s\n" "$#" >&2; exit 1;;
  esac
}

export -f flux_suspend

flux get source git -A --no-header --cluster kind-sqnc-flux-infra | awk -F '\ *\t' -v OFS='\t' '$3 ~ /^[:space]*$/ { $3 = "X" } 1' | awk '$4=="False" { print $1,$2 }' | xargs -I {} bash -c 'flux_suspend source git {}'
flux get source helm -A --no-header --cluster kind-sqnc-flux-infra | awk -F '\ *\t' -v OFS='\t' '$3 ~ /^[:space]*$/ { $3 = "X" } 1' | awk '$4=="False" { print $1,$2 }' | xargs -I {} bash -c 'flux_suspend source helm {}'
flux get source chart -A --no-header --cluster kind-sqnc-flux-infra | awk -F '\ *\t' -v OFS='\t' '$3 ~ /^[:space]*$/ { $3 = "X" } 1' | awk '$4=="False" { print $1,$2 }' | xargs -I {} bash -c 'flux_suspend source chart {}'
flux get kustomization -A --no-header --cluster kind-sqnc-flux-infra | awk -F '\ *\t' -v OFS='\t' '$3 ~ /^[:space]*$/ { $3 = "X" } 1' | awk '$4=="False" { print $1,$2 }' | xargs -I {} bash -c 'flux_suspend kustomization {}'
flux get helmrelease -A --no-header --cluster kind-sqnc-flux-infra | awk -F '\ *\t' -v OFS='\t' '$3 ~ /^[:space]*$/ { $3 = "X" } 1' | awk '$4=="False" { print $1,$2 }' | xargs -I {} bash -c 'flux_suspend helmrelease {}'

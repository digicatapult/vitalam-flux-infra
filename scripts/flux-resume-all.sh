#!/usr/bin/env bash

flux_resume () {
  case $# in
    3) flux resume $1 $3 -n $2;;
    4) flux resume $1 $2 $4 -n $3;;
    *) printf "Expected 3 or 4 parameters, got %s\n" "$#" >&2; exit 1;;
  esac
}

export -f flux_resume

flux get source git -A --no-header --cluster kind-sqnc-flux-infra | awk -F '\ *\t' -v OFS='\t' '$3 ~ /^[:space]*$/ { $3 = "X" } 1' | awk '$4=="True" { print $1,$2 }' | xargs -I {} bash -c 'flux_resume source git {}'
flux get source helm -A --no-header --cluster kind-sqnc-flux-infra | awk -F '\ *\t' -v OFS='\t' '$3 ~ /^[:space]*$/ { $3 = "X" } 1' | awk '$4=="True" { print $1,$2 }' | xargs -I {} bash -c 'flux_resume source helm {}'
flux get source chart -A --no-header --cluster kind-sqnc-flux-infra | awk -F '\ *\t' -v OFS='\t' '$3 ~ /^[:space]*$/ { $3 = "X" } 1' | awk '$4=="True" { print $1,$2 }' | xargs -I {} bash -c 'flux_resume source chart {}'
flux get kustomization -A --no-header --cluster kind-sqnc-flux-infra | awk -F '\ *\t' -v OFS='\t' '$3 ~ /^[:space]*$/ { $3 = "X" } 1' | awk '$4=="True" { print $1,$2 }' | xargs -I {} bash -c 'flux_resume kustomization {}'
flux get helmrelease -A --no-header --cluster kind-sqnc-flux-infra | awk -F '\ *\t' -v OFS='\t' '$3 ~ /^[:space]*$/ { $3 = "X" } 1' | awk '$4=="True" { print $1,$2 }' | xargs -I {} bash -c 'flux_resume helmrelease {}'

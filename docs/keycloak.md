Identity in SQNC is managed using [`Keycloak`](https://www.keycloak.org/)

After following instructions in [getting-started](./getting-started.md) to start a flux cluster, run `kubectl port-forward -n keycloak service/keycloak 8080:80` then the admin console for Keycloak will be available at http://localhost:8080/admin.

Default user is `user`
Password can be retrieved with `kubectl -n keycloak get secret keycloak -o jsonpath='{.data.admin-password}' | base64 -d && echo`

The Keycloak instance comes with a realm named `simple`, set up to use Keycloak's built-in simple user login/registration. The default client for logging in is at http://localhost:8080/realms/simple/account/.

Debugging
`kubectl get services -n keycloak`
`flux get kustomizations -A`
`kubectl describe configmaps -n keycloak`
`flux reconcile helmrelease keycloak -n keycloak`

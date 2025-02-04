# Keycloak

Authentication in SQNC is managed using [`Keycloak`](https://www.keycloak.org/)

## Kind Cluster

### Admin

After following instructions in [getting-started](./getting-started.md) to start a flux cluster, the admin console for Keycloak is available at http://localhost:3080/auth/.

Default user is `user`
Password is retrieved with `kubectl -n keycloak get secret keycloak -o jsonpath='{.data.admin-password}' | base64 -d && echo`

The Keycloak instance comes with a realm per persona named `alice`, `bob` and `charlie`, set up to use Keycloak's built-in simple user login/registration. The default client for logging in is for example for `alice` http://localhost:3080/auth/realms/alice/account/.

It's recommended that you import these realms manually with the Keycloak admin console, using the individual JSON blobs for `alice`, `bob`, and `charlie` located under `./clusters/kind-cluster/keycloak`.

### Authenticating swagger

A client exists in each realm called `sequence` which supports the clientCredentials flow. When visiting any of the swagger interfaces, for example `http://localhost:3080/alice/swagger`, you will need to authenticate by clicking `Authorize`. The "secret" for all three realms is configured to be the value `secret`. Once authenticated you will then be able to make calls through the swagger interface.

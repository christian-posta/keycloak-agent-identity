# Keycloak and SPIRE for Agent Identity

A development environment for integrating Keycloak with SPIRE for workload identity and MCP (Model Context Protocol) authentication.

Specifically this project allows you to :

* Quickly bootstrap a test Keycloak for local dev
* Configure clients / authentication mechansims / flows / scopes / mappings
* Pre-loads SPIs for DCR based on SPIFFE and Client Authentication based on SPIFFE
* Based on these blogs:
  * [Implementing MCP Dynamic Client Registration With SPIFFE and Keycloak](https://blog.christianposta.com/implementing-mcp-dynamic-client-registration-with-spiffe/)
  * [Authenticating MCP OAuth Clients With SPIFFE and SPIRE](https://blog.christianposta.com/authenticating-mcp-oauth-clients-with-spiffe/)

Uses these three projects as dependencies to implement the SPI / SPIRE plugins:

* https://github.com/christian-posta/spiffe-svid-client-authenticator
* https://github.com/christian-posta/spiffe-dcr-keycloak
* https://github.com/christian-posta/spire-software-statements


## Quick Start

```bash
# Start Keycloak (uses config.json by default)
uv run keycloak

# Start SPIRE components
uv run spire

# Stop services
uv run keycloak --down
uv run spire --down
```

## Configuration

- **Default config**: Uses `config.json` from project root
- **Custom config**: `uv run keycloak --config path/to/config.json`
- **Verbose output**: Add `--verbose` to any command

## Services

- **Keycloak**: Identity provider on http://localhost:8080
- **SPIRE**: Workload identity with SVID-based authentication
- **MCP Integration**: Token exchange and SPIFFE-based client authentication

## Development

```bash
# Install dependencies
uv sync

# View logs
docker compose -f keycloak/docker-compose.yml logs
docker compose -f spire/docker-compose.yml logs
```


After setting things up, you can test a DCR example with the following:

```bash
./spire/test-spiffe-drc.sh
```


To run a test of the client authentication:

```bash
./spire/test-spiffe-authentication.sh
```
# Keycloak Agent Identity

A development environment for integrating Keycloak with SPIRE for workload identity and MCP (Model Context Protocol) authentication.

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

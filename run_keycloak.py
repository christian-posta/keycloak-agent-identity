#!/usr/bin/env python3
"""
Wrapper script to run boot_keycloak.py from the keycloak directory.
This allows uv run keycloak to work from the project root.
"""

import os
import sys
import subprocess
from pathlib import Path

def main():
    # Get the project root directory (where this script is located)
    project_root = Path(__file__).parent
    keycloak_dir = project_root / "keycloak"
    
    # Change to the keycloak directory
    os.chdir(keycloak_dir)
    
    # Fix any config file paths that might have "keycloak/" prefix
    # since we're already in the keycloak directory
    for i, arg in enumerate(sys.argv):
        if arg == "--config" and i + 1 < len(sys.argv):
            config_path = sys.argv[i + 1]
            if config_path.startswith("keycloak/"):
                # Remove the "keycloak/" prefix since we're already in that directory
                sys.argv[i + 1] = config_path[9:]  # Remove "keycloak/"
    
    # Import and run the main function from boot_keycloak
    sys.path.insert(0, str(keycloak_dir))
    
    try:
        from boot_keycloak import main as keycloak_main
        keycloak_main()
    except ImportError as e:
        print(f"Error importing boot_keycloak: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error running keycloak: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()

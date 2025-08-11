#!/usr/bin/env python3
"""
Wrapper script to run boot_keycloak.py from the keycloak directory.
This allows uv run keycloak to work from the project root.
Defaults to using config.json at the project root.
"""

import os
import sys
import argparse
from pathlib import Path

def main():
    # Get the project root directory (where this script is located)
    project_root = Path(__file__).parent
    keycloak_dir = project_root / "keycloak"
    
    # Parse arguments to handle config file path
    parser = argparse.ArgumentParser(description="Boot and configure Keycloak", add_help=False)
    parser.add_argument("--config", "--configure", default=None, help="Path to config file")
    parser.add_argument("--url", default=None, help="Keycloak URL")
    parser.add_argument("--summary", action="store_true", help="Show detailed summary")
    parser.add_argument("--verbose", action="store_true", help="Verbose output")
    parser.add_argument("--down", action="store_true", help="Stop Keycloak containers")
    parser.add_argument("--help", "-h", action="store_true", help="Show help")
    
    # Parse known args to avoid errors with unrecognized arguments
    args, unknown_args = parser.parse_known_args()
    
    # If help is requested, pass it through to boot_keycloak.py
    if args.help:
        os.chdir(keycloak_dir)
        sys.path.insert(0, str(keycloak_dir))
        from boot_keycloak import main as keycloak_main
        sys.argv = ["boot_keycloak.py", "--help"]
        keycloak_main()
        return
    
    # If --down is requested, stop Keycloak containers
    if args.down:
        import subprocess
        os.chdir(keycloak_dir)
        
        print("🔽 Stopping Keycloak containers...")
        try:
            result = subprocess.run(
                ["docker", "compose", "down"],
                check=True,
                capture_output=True,
                text=True
            )
            print("✅ Keycloak containers stopped successfully")
            if args.verbose:
                print(f"Command output: {result.stdout}")
        except subprocess.CalledProcessError as e:
            print(f"❌ Failed to stop Keycloak containers: {e}")
            if e.stderr:
                print(f"Error details: {e.stderr}")
            sys.exit(1)
        except Exception as e:
            print(f"❌ Unexpected error stopping Keycloak: {e}")
            sys.exit(1)
        return
    
    # Default to config.json at project root if no config specified
    if args.config is None:
        default_config = project_root / "config.json"
        if default_config.exists():
            # Use absolute path to config.json at project root
            config_path = str(default_config)
        else:
            # Fall back to keycloak/config.json (original behavior)
            config_path = "config.json"  # This will be relative to keycloak dir
    else:
        # User specified a config path
        config_arg = Path(args.config)
        if config_arg.is_absolute():
            config_path = str(config_arg)
        else:
            # Make it relative to project root, then convert to absolute
            config_path = str((project_root / config_arg).resolve())
    
    # Change to the keycloak directory
    os.chdir(keycloak_dir)
    
    # Rebuild sys.argv for boot_keycloak.py
    new_argv = ["boot_keycloak.py"]
    
    # Add the config argument
    new_argv.extend(["--config", config_path])
    
    # Add other arguments
    if args.url:
        new_argv.extend(["--url", args.url])
    if args.summary:
        new_argv.append("--summary")
    if args.verbose:
        new_argv.append("--verbose")
    
    # Add any unknown arguments
    new_argv.extend(unknown_args)
    
    # Set sys.argv for boot_keycloak
    sys.argv = new_argv
    
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
